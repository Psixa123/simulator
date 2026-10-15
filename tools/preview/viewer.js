// World preview renderer (see viewer.html and tools/preview_map.py).
// Builds the dumped world with three.js — parts as instanced boxes/wedges/cylinders/balls, prop meshes
// from the WorldProps pack, Terrain as a height-field mesh, SurfaceGui/BillboardGui text drawn on canvases —
// then renders each requested shot and POSTs it back as a PNG.

import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';
import { FXAAShader } from 'three/addons/shaders/FXAAShader.js';

const post = (path, body) => fetch(path, { method: 'POST', body });
const log = (message) => post('/__log', String(message));
let failed = false;
function fail(message) {
  if (failed) return;
  failed = true;
  post('/__done?error=1', String(message));
}
window.addEventListener('error', (e) => fail(`${e.message} (${e.filename}:${e.lineno})`));
window.addEventListener('unhandledrejection', (e) => fail(`unhandled rejection: ${e.reason && (e.reason.stack || e.reason)}`));

const scene = await (await fetch('/__data/scene.json')).json();
const [W, H] = scene.size;
const settings = scene.settings || {};

// ------------------------------------------------------------------------------------ renderer
const renderer = new THREE.WebGLRenderer({ antialias: false, preserveDrawingBuffer: true, powerPreference: 'high-performance' });
renderer.setPixelRatio(1);
renderer.setSize(W, H);
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.NeutralToneMapping;
renderer.toneMappingExposure = settings.exposure ?? 1.0;
renderer.shadowMap.enabled = settings.shadows !== false;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
document.body.appendChild(renderer.domElement);

const world = new THREE.Scene();
const color = (hex) => new THREE.Color('#' + hex);

// ------------------------------------------------------------------------------------ sky, fog, lights
const L = scene.lighting;
const SKY = {
  zenith: color(L.sky.zenith),
  horizon: color(L.sky.horizon),
  below: color(L.sky.below),
};
const skyMaterial = new THREE.ShaderMaterial({
  side: THREE.BackSide,
  depthWrite: false,
  fog: false,
  uniforms: {
    zenith: { value: SKY.zenith },
    horizon: { value: SKY.horizon },
    below: { value: SKY.below },
    screenTop: { value: color(L.sky.screenTop) },
    screenBottom: { value: color(L.sky.screenBottom) },
    screenMix: { value: 0 },
    height: { value: H },
    stars: { value: 0 },
  },
  vertexShader: `
    varying vec3 vDir;
    void main() {
      vDir = position;
      vec4 p = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
      gl_Position = p.xyww;
    }`,
  fragmentShader: `
    uniform vec3 zenith; uniform vec3 horizon; uniform vec3 below;
    uniform vec3 screenTop; uniform vec3 screenBottom; uniform float screenMix; uniform float height;
    uniform float stars;
    varying vec3 vDir;
    float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
    void main() {
      vec3 d = normalize(vDir);
      vec3 col = d.y > 0.0 ? mix(horizon, zenith, pow(clamp(d.y, 0.0, 1.0), 0.55))
                           : mix(horizon, below, pow(clamp(-d.y * 3.0, 0.0, 1.0), 0.7));
      if (stars > 0.0 && d.y > 0.02) {
        vec3 cell = floor(d * 220.0);
        float h = hash(cell);
        vec3 centre = (cell + 0.5 + 0.35 * (vec3(hash(cell + 1.7), hash(cell + 3.1), hash(cell + 5.3)) - 0.5)) / 220.0;
        float star = smoothstep(0.0028, 0.0008, length(d - normalize(centre))) * step(0.965, h);
        col += star * stars * smoothstep(0.02, 0.25, d.y) * vec3(1.0, 0.97, 0.9) * (0.6 + 0.8 * hash(cell + 9.1));
      }
      // aerial shots look down at the void under the world: use a soft top-to-bottom gradient instead
      float t = gl_FragCoord.y / height;
      vec3 screen = mix(screenBottom, screenTop, smoothstep(0.0, 1.0, t));
      gl_FragColor = vec4(mix(col, screen, screenMix), 1.0);
    }`,
});
const sky = new THREE.Mesh(new THREE.SphereGeometry(1, 48, 24), skyMaterial);
sky.renderOrder = -1000;
sky.frustumCulled = false;
world.add(sky);

world.fog = new THREE.Fog(color(L.fog.color), 400, 2000);

const hemi = new THREE.HemisphereLight(color(L.hemi.sky), color(L.hemi.ground), L.hemi.intensity);
world.add(hemi);
const sun = new THREE.DirectionalLight(color(L.sun.color), L.sun.intensity);
sun.castShadow = true;
sun.shadow.mapSize.set(settings.shadowSize ?? 2048, settings.shadowSize ?? 2048);
sun.shadow.bias = -0.0004;
sun.shadow.normalBias = 0.6;
sun.shadow.radius = 3;
world.add(sun);
world.add(sun.target);
const SUN_DIR = new THREE.Vector3(...L.sun.direction).normalize();

// Toon ramp: soft steps so shapes read clearly without looking like plastic
function toonRamp(levels) {
  const data = new Uint8Array(levels.map((v) => Math.round(v * 255)));
  const texture = new THREE.DataTexture(data, levels.length, 1, THREE.RedFormat);
  texture.minFilter = THREE.NearestFilter;
  texture.magFilter = THREE.NearestFilter;
  texture.generateMipmaps = false;
  texture.needsUpdate = true;
  return texture;
}
const RAMP = toonRamp(settings.ramp || [0.42, 0.62, 0.8, 0.92, 1.0]);

// ------------------------------------------------------------------------------------ geometry
function wedgeGeometry() {
  // Roblox WedgePart: full bottom, full back (+Z), slope from the top back edge down to the front (-Z)
  const v = [
    [-0.5, -0.5, -0.5], [0.5, -0.5, -0.5], [0.5, -0.5, 0.5], [-0.5, -0.5, 0.5], // bottom
    [-0.5, 0.5, 0.5], [0.5, 0.5, 0.5], // top back edge
  ];
  const faces = [
    [0, 1, 2], [0, 2, 3], // bottom (normal -Y)
    [3, 2, 5], [3, 5, 4], // back (+Z)
    [0, 4, 5], [0, 5, 1], // slope
    [0, 3, 4], // left (-X)
    [1, 5, 2], // right (+X)
  ];
  const positions = [];
  for (const f of faces) for (const i of f) positions.push(...v[i]);
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
  g.computeVertexNormals();
  return g;
}
function cornerWedgeGeometry() {
  // Roblox CornerWedgePart: a pyramid-like corner with its tall edge at (+X, -Z)
  const v = [[-0.5, -0.5, -0.5], [0.5, -0.5, -0.5], [0.5, -0.5, 0.5], [-0.5, -0.5, 0.5], [0.5, 0.5, -0.5]];
  const faces = [[0, 1, 2], [0, 2, 3], [1, 4, 2], [0, 4, 1], [3, 2, 4], [0, 3, 4]];
  const positions = [];
  for (const f of faces) for (const i of f) positions.push(...v[i]);
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
  g.computeVertexNormals();
  return g;
}
const GEOMETRY = {
  box: new THREE.BoxGeometry(1, 1, 1),
  wedge: wedgeGeometry(),
  cornerwedge: cornerWedgeGeometry(),
  cylinder: new THREE.CylinderGeometry(0.5, 0.5, 1, 40, 1).rotateZ(Math.PI / 2), // Roblox cylinders run along X
  ycylinder: new THREE.CylinderGeometry(0.5, 0.5, 1, 40, 1),
  ball: new THREE.SphereGeometry(0.5, 40, 24),
};

async function loadBinary(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`can't load ${url}`);
  return response.arrayBuffer();
}

if (scene.meshes && scene.meshes.url) {
  const buffer = await loadBinary(scene.meshes.url);
  for (const [name, m] of Object.entries(scene.meshes.items)) {
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(buffer, m.position, m.vertices * 3), 3));
    g.setAttribute('normal', new THREE.BufferAttribute(new Float32Array(buffer, m.normal, m.vertices * 3), 3));
    g.setIndex(new THREE.BufferAttribute(new Uint32Array(buffer, m.index, m.indices), 1));
    GEOMETRY['mesh:' + name] = g;
  }
}

// ------------------------------------------------------------------------------------ materials
const materialCache = new Map();
function material(kind, opacity) {
  const key = kind + '|' + opacity;
  if (materialCache.has(key)) return materialCache.get(key);
  let m;
  if (kind === 'neon') {
    m = new THREE.MeshBasicMaterial({ color: 0xffffff });
  } else if (kind === 'force') {
    m = new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity, depthWrite: false,
      blending: THREE.AdditiveBlending, side: THREE.DoubleSide });
  } else {
    m = new THREE.MeshToonMaterial({ color: 0xffffff, gradientMap: RAMP });
    if (opacity < 1) {
      m.transparent = true;
      m.opacity = opacity;
      m.depthWrite = false;
    }
  }
  materialCache.set(key, m);
  return m;
}

// ------------------------------------------------------------------------------------ parts
// part: [shape, kind, opacity, castShadow, x, y, z, r00..r22, sx, sy, sz, "RRGGBB"]
const groups = new Map();
for (const p of scene.parts) {
  const key = p[0] + '|' + p[1] + '|' + p[2] + '|' + p[3];
  if (!groups.has(key)) groups.set(key, []);
  groups.get(key).push(p);
}
const matrix = new THREE.Matrix4();
const tmpColor = new THREE.Color();
let instanceCount = 0;
for (const [key, list] of groups) {
  const [shape, kind, opacityText, castText] = key.split('|');
  const geometry = GEOMETRY[shape] || GEOMETRY.box;
  const opacity = Number(opacityText);
  const mesh = new THREE.InstancedMesh(geometry, material(kind, opacity), list.length);
  list.forEach((p, i) => {
    const [x, y, z, a, b, c, d, e, f, g, h, k, sx, sy, sz] = p.slice(4, 19);
    matrix.set(a * sx, b * sy, c * sz, x,
      d * sx, e * sy, f * sz, y,
      g * sx, h * sy, k * sz, z,
      0, 0, 0, 1);
    mesh.setMatrixAt(i, matrix);
    tmpColor.set('#' + p[19]);
    if (kind === 'neon') {
      // Roblox Neon glows: brighter than white light allows, so the bloom pass picks it up
      tmpColor.lerp(new THREE.Color(1, 1, 1), 0.12).multiplyScalar(settings.neonBoost ?? 1.6);
    } else if (kind === 'force') {
      tmpColor.multiplyScalar(0.9);
    }
    mesh.setColorAt(i, tmpColor);
  });
  mesh.instanceMatrix.needsUpdate = true;
  if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
  mesh.castShadow = castText === '1' && kind !== 'force' && opacity >= 0.6;
  mesh.receiveShadow = kind !== 'neon' && kind !== 'force';
  mesh.frustumCulled = false;
  if (opacity < 1) mesh.renderOrder = 10;
  world.add(mesh);
  instanceCount += list.length;
}

// ------------------------------------------------------------------------------------ terrain
if (scene.terrain) {
  const t = scene.terrain;
  const buffer = await loadBinary(t.url);
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(buffer, t.position, t.vertices * 3), 3));
  g.setAttribute('color', new THREE.BufferAttribute(new Float32Array(buffer, t.color, t.vertices * 3), 3));
  g.setIndex(new THREE.BufferAttribute(new Uint32Array(buffer, t.index, t.indices), 1));
  g.computeVertexNormals();
  const m = new THREE.MeshToonMaterial({ vertexColors: true, gradientMap: RAMP });
  const mesh = new THREE.Mesh(g, m);
  mesh.receiveShadow = true;
  mesh.castShadow = true;
  mesh.frustumCulled = false;
  world.add(mesh);
}

// ------------------------------------------------------------------------------------ beams
for (const beam of scene.beams || []) {
  const a = new THREE.Vector3(...beam.a), b = new THREE.Vector3(...beam.b);
  const length = a.distanceTo(b);
  if (length < 0.01) continue;
  const width = (beam.w0 + beam.w1) / 2;
  const geo = new THREE.PlaneGeometry(length, Math.max(width, 0.05));
  const mat = new THREE.MeshBasicMaterial({ color: color(beam.color), transparent: true, opacity: beam.opacity,
    side: THREE.DoubleSide, depthWrite: false, blending: beam.additive ? THREE.AdditiveBlending : THREE.NormalBlending });
  const mesh = new THREE.Mesh(geo, mat);
  mesh.position.copy(a).add(b).multiplyScalar(0.5);
  mesh.quaternion.setFromUnitVectors(new THREE.Vector3(1, 0, 0), b.clone().sub(a).normalize());
  mesh.userData.beam = true;
  world.add(mesh);
}

// ------------------------------------------------------------------------------------ gui text
await Promise.all([
  document.fonts.load('48px "Fredoka One"'),
  document.fonts.load('48px "Luckiest Guy"'),
]).catch(() => {});

const FONT_FAMILIES = {
  FredokaOne: '"Fredoka One"', LuckiestGuy: '"Luckiest Guy"', Cartoon: '"Fredoka One"', Bangers: '"Luckiest Guy"',
};
const EMOJI = '"Noto Color Emoji"';
function cssFont(name, size) {
  name = String(name || 'SourceSans');
  const family = FONT_FAMILIES[name] || '"DejaVu Sans", sans-serif';
  const weight = /Black|Heavy/.test(name) ? 900 : /Bold/.test(name) ? 700 : /Medium|Semibold/.test(name) ? 600 : 400;
  return `${weight} ${size}px ${family}, ${EMOJI}`;
}
const rgba = (hex, alpha = 1) => {
  const n = parseInt(hex, 16);
  return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${alpha})`;
};
const stripRich = (text) => String(text).replace(/<[^>]*>/g, '');

function wrapLines(ctx, text, width, wrap) {
  const paragraphs = String(text).split('\n');
  const lines = [];
  for (const para of paragraphs) {
    if (!wrap) { lines.push(para); continue; }
    const words = para.split(' ');
    let line = '';
    for (const word of words) {
      const test = line ? line + ' ' + word : word;
      if (line && ctx.measureText(test).width > width) {
        lines.push(line);
        line = word;
      } else {
        line = test;
      }
    }
    lines.push(line);
  }
  return lines;
}

function layoutText(ctx, node, w, h, k) {
  const text = node.RichText ? stripRich(node.Text) : String(node.Text);
  const lineHeight = node.LineHeight || 1;
  const wrap = node.TextWrapped || node.TextScaled;
  const fits = (size) => {
    ctx.font = cssFont(node.Font, size);
    const lines = wrapLines(ctx, text, w, wrap);
    const widest = Math.max(...lines.map((l) => ctx.measureText(l).width));
    return { lines, ok: widest <= w * 1.001 && lines.length * size * lineHeight <= h * 1.001 };
  };
  let size;
  if (node.TextScaled) {
    const max = Math.min(h, (node.MaxTextSize || 100) * k);
    let lo = 1, hi = Math.max(1, max);
    while (hi - lo > 0.5) {
      const mid = (lo + hi) / 2;
      if (fits(mid).ok) lo = mid; else hi = mid;
    }
    size = lo;
  } else {
    size = (node.TextSize || 14) * k;
  }
  const { lines } = fits(size);
  return { size, lines, lineHeight };
}

function roundedRect(ctx, x, y, w, h, r) {
  r = Math.max(0, Math.min(r, w / 2, h / 2));
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

function gradientFill(ctx, gradient, x, y, w, h, base) {
  const angle = ((gradient.Rotation || 0) * Math.PI) / 180;
  const cx = x + w / 2, cy = y + h / 2;
  const dx = Math.cos(angle) * w / 2, dy = Math.sin(angle) * h / 2;
  const g = ctx.createLinearGradient(cx - dx, cy - dy, cx + dx, cy + dy);
  const baseColor = new THREE.Color('#' + base);
  for (const [t, hex] of gradient.Color) {
    const c = new THREE.Color('#' + hex).multiply(baseColor);
    g.addColorStop(Math.min(1, Math.max(0, t)), '#' + c.getHexString());
  }
  return g;
}

// Draws a GuiObject tree; px/py/pw/ph = parent rect in canvas pixels, k = canvas pixels per gui pixel
function drawGuiNode(ctx, node, px, py, pw, ph, k) {
  if (node.Visible === false) return;
  const [sxs, sxo, sys, syo] = node.Size;
  const [pxs, pxo, pys, pyo] = node.Position;
  const w = sxs * pw + sxo * k, h = sys * ph + syo * k;
  const ap = node.AnchorPoint || [0, 0];
  const x = px + pxs * pw + pxo * k - ap[0] * w;
  const y = py + pys * ph + pyo * k - ap[1] * h;
  ctx.save();
  if (node.Rotation) {
    ctx.translate(x + w / 2, y + h / 2);
    ctx.rotate((node.Rotation * Math.PI) / 180);
    ctx.translate(-(x + w / 2), -(y + h / 2));
  }
  const radius = node.Corner ? node.Corner[0] * Math.min(w, h) + node.Corner[1] * k : 0;
  const bgAlpha = 1 - (node.BackgroundTransparency ?? 0);
  if (bgAlpha > 0.003 && node.Class !== 'TextLabel' || (node.Class === 'TextLabel' && bgAlpha > 0.003)) {
    ctx.fillStyle = node.Gradient && !node.Text ? gradientFill(ctx, node.Gradient, x, y, w, h, node.BackgroundColor3)
      : rgba(node.BackgroundColor3, bgAlpha);
    ctx.globalAlpha = node.Gradient && !node.Text ? bgAlpha : 1;
    roundedRect(ctx, x, y, w, h, radius);
    ctx.fill();
    ctx.globalAlpha = 1;
  }
  if (node.Stroke && node.Stroke.Mode === 'Border') {
    ctx.strokeStyle = rgba(node.Stroke.Color, 1 - node.Stroke.Transparency);
    ctx.lineWidth = node.Stroke.Thickness * k;
    roundedRect(ctx, x, y, w, h, radius);
    ctx.stroke();
  }
  if (node.Text && node.TextTransparency < 1) {
    let tx = x, ty = y, tw = w, th = h;
    if (node.Padding) {
      const [l, r, t, b] = node.Padding;
      tx += l[0] * w + l[1] * k; tw -= l[0] * w + l[1] * k + r[0] * w + r[1] * k;
      ty += t[0] * h + t[1] * k; th -= t[0] * h + t[1] * k + b[0] * h + b[1] * k;
    }
    const { size, lines, lineHeight } = layoutText(ctx, node, tw, th, k);
    ctx.font = cssFont(node.Font, size);
    ctx.textBaseline = 'middle';
    const align = node.TextXAlignment === 'Left' ? 'left' : node.TextXAlignment === 'Right' ? 'right' : 'center';
    ctx.textAlign = align;
    const ax = align === 'left' ? tx : align === 'right' ? tx + tw : tx + tw / 2;
    const block = lines.length * size * lineHeight;
    let top = node.TextYAlignment === 'Top' ? ty : node.TextYAlignment === 'Bottom' ? ty + th - block : ty + (th - block) / 2;
    const alpha = 1 - node.TextTransparency;
    const stroke = node.Stroke && node.Stroke.Mode !== 'Border' ? node.Stroke
      : (node.TextStrokeTransparency < 1 ? { Color: node.TextStrokeColor3, Thickness: 1, Transparency: node.TextStrokeTransparency } : null);
    const fill = node.Gradient ? gradientFill(ctx, node.Gradient, x, y, w, h, node.TextColor3) : rgba(node.TextColor3, alpha);
    for (const line of lines) {
      const cy = top + (size * lineHeight) / 2;
      if (stroke) {
        ctx.lineJoin = 'round';
        ctx.lineWidth = stroke.Thickness * 2 * k;
        ctx.strokeStyle = rgba(stroke.Color, (1 - stroke.Transparency) * alpha);
        ctx.strokeText(line, ax, cy);
      }
      ctx.fillStyle = fill;
      ctx.globalAlpha = node.Gradient ? alpha : 1;
      ctx.fillText(line, ax, cy);
      ctx.globalAlpha = 1;
      top += size * lineHeight;
    }
  }
  const children = [...(node.Children || [])].sort((a, b) => (a.ZIndex || 1) - (b.ZIndex || 1));
  for (const child of children) drawGuiNode(ctx, child, x, y, w, h, k);
  ctx.restore();
}

function guiCanvas(gui, width, height, k) {
  const canvas = document.createElement('canvas');
  canvas.width = Math.max(2, Math.round(width * k));
  canvas.height = Math.max(2, Math.round(height * k));
  const ctx = canvas.getContext('2d');
  const children = [...gui.Children].sort((a, b) => (a.ZIndex || 1) - (b.ZIndex || 1));
  for (const child of children) drawGuiNode(ctx, child, 0, 0, canvas.width, canvas.height, k);
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.anisotropy = 8;
  return texture;
}

// Face frames of a part (local axes): normal n, gui right u, gui up v, and which size axes span the face
const FACES = {
  Front: { n: [0, 0, -1], u: [-1, 0, 0], v: [0, 1, 0], w: 0, h: 1, d: 2 },
  Back: { n: [0, 0, 1], u: [1, 0, 0], v: [0, 1, 0], w: 0, h: 1, d: 2 },
  Right: { n: [1, 0, 0], u: [0, 0, -1], v: [0, 1, 0], w: 2, h: 1, d: 0 },
  Left: { n: [-1, 0, 0], u: [0, 0, 1], v: [0, 1, 0], w: 2, h: 1, d: 0 },
  Top: { n: [0, 1, 0], u: [1, 0, 0], v: [0, 0, -1], w: 0, h: 2, d: 1 },
  Bottom: { n: [0, -1, 0], u: [1, 0, 0], v: [0, 0, 1], w: 0, h: 2, d: 1 },
};

const billboards = [];
for (const gui of scene.guis || []) {
  if (!gui.Children.length) continue;
  if (gui.Class === 'SurfaceGui' && gui.part) {
    const face = FACES[gui.Face] || FACES.Front;
    const size = gui.part.size;
    const fw = size[face.w], fh = size[face.h];
    const guiW = gui.SizingMode === 'PixelsPerStud' ? fw * gui.PixelsPerStud : gui.CanvasSize[0];
    const guiH = gui.SizingMode === 'PixelsPerStud' ? fh * gui.PixelsPerStud : gui.CanvasSize[1];
    const k = Math.min(2048 / Math.max(guiW, guiH), Math.max(1, 640 / Math.max(guiW, guiH)));
    const texture = guiCanvas(gui, guiW, guiH, k);
    const brightness = gui.LightInfluence < 0.5 ? (gui.Brightness || 1) : 1;
    const mat = gui.LightInfluence < 0.5
      ? new THREE.MeshBasicMaterial({ map: texture, transparent: true, depthWrite: false, color: new THREE.Color(brightness, brightness, brightness) })
      : new THREE.MeshToonMaterial({ map: texture, transparent: true, depthWrite: false, gradientMap: RAMP });
    mat.polygonOffset = true;
    mat.polygonOffsetFactor = -2;
    mat.polygonOffsetUnits = -2;
    if (gui.AlwaysOnTop) mat.depthTest = false;
    const plane = new THREE.Mesh(new THREE.PlaneGeometry(fw, fh), mat);
    const [x, y, z, a, b, c, d, e, f, g, h, kk] = gui.part.cframe;
    const R = new THREE.Matrix4().set(a, b, c, 0, d, e, f, 0, g, h, kk, 0, 0, 0, 0, 1);
    const u = new THREE.Vector3(...face.u), v = new THREE.Vector3(...face.v), n = new THREE.Vector3(...face.n);
    const basis = new THREE.Matrix4().makeBasis(u, v, n);
    plane.quaternion.setFromRotationMatrix(new THREE.Matrix4().multiplyMatrices(R, basis));
    const offset = n.clone().multiplyScalar(size[face.d] / 2 + 0.03).applyMatrix4(R);
    plane.position.set(x, y, z).add(offset);
    plane.renderOrder = 20;
    world.add(plane);
  } else if (gui.Class === 'BillboardGui' && gui.Position) {
    const [xs, xo, ys, yo] = gui.Size;
    const pixelW = xo, pixelH = yo;
    const studW = xs, studH = ys;
    if (pixelW + studW <= 0 || pixelH + studH <= 0) continue;
    const guiW = pixelW + studW * 50, guiH = pixelH + studH * 50;
    const texture = guiCanvas(gui, guiW, guiH, 2);
    const mat = new THREE.SpriteMaterial({ map: texture, transparent: true, depthWrite: false,
      sizeAttenuation: false, depthTest: !gui.AlwaysOnTop, fog: false });
    const sprite = new THREE.Sprite(mat);
    sprite.renderOrder = 30;
    sprite.visible = false;
    world.add(sprite);
    billboards.push({ gui, sprite, pixelW, pixelH, studW, studH });
  }
}

// ------------------------------------------------------------------------------------ post-processing
const target = new THREE.WebGLRenderTarget(W, H, { type: THREE.HalfFloatType, samples: settings.msaa ?? 0 });
const composer = new EffectComposer(renderer, target);
const renderPass = new RenderPass(world, null);
composer.addPass(renderPass);
const bloom = new UnrealBloomPass(new THREE.Vector2(W, H), L.bloom.strength, L.bloom.radius, L.bloom.threshold);
if (settings.bloom !== false) composer.addPass(bloom);
composer.addPass(new OutputPass());
const grade = new ShaderPass({
  uniforms: {
    tDiffuse: { value: null },
    saturation: { value: L.grade.saturation },
    contrast: { value: L.grade.contrast },
    brightness: { value: L.grade.brightness },
    tint: { value: new THREE.Vector3(...L.grade.tint) },
    vignette: { value: settings.vignette ?? 0.18 },
  },
  vertexShader: `varying vec2 vUv; void main() { vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`,
  fragmentShader: `
    uniform sampler2D tDiffuse; uniform float saturation; uniform float contrast; uniform float brightness;
    uniform vec3 tint; uniform float vignette; varying vec2 vUv;
    void main() {
      vec4 c = texture2D(tDiffuse, vUv);
      vec3 col = c.rgb + brightness;
      col = (col - 0.5) * (1.0 + contrast) + 0.5;
      float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
      col = mix(vec3(l), col, 1.0 + saturation) * tint;
      vec2 q = vUv - 0.5;
      col *= 1.0 - vignette * smoothstep(0.35, 0.85, length(q * vec2(1.2, 1.0)));
      gl_FragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
    }`,
});
composer.addPass(grade);
const fxaa = new ShaderPass(FXAAShader);
fxaa.material.uniforms.resolution.value.set(1 / W, 1 / H);
if (settings.fxaa !== false) composer.addPass(fxaa);

// ------------------------------------------------------------------------------------ shots
function fitDistance(camera, center, box, dir) {
  // distance along `dir` (target -> camera) at which every corner of `box` is inside the frame
  const forward = dir.clone().negate();
  const right = new THREE.Vector3().crossVectors(forward, new THREE.Vector3(0, 1, 0)).normalize();
  const up = new THREE.Vector3().crossVectors(right, forward).normalize();
  const tanV = Math.tan(THREE.MathUtils.degToRad(camera.fov / 2));
  const tanH = tanV * camera.aspect;
  let distance = 1;
  for (const x of [box[0], box[3]]) for (const y of [box[1], box[4]]) for (const z of [box[2], box[5]]) {
    const p = new THREE.Vector3(x, y, z).sub(center);
    const px = p.dot(right), py = p.dot(up), pz = p.dot(forward);
    distance = Math.max(distance, Math.abs(px) / tanH - pz, Math.abs(py) / tanV - pz);
  }
  return distance;
}

function setShadowBox(box) {
  // fit the sun's shadow camera around `box` (minX, minY, minZ, maxX, maxY, maxZ)
  const center = new THREE.Vector3((box[0] + box[3]) / 2, (box[1] + box[4]) / 2, (box[2] + box[5]) / 2);
  const radius = new THREE.Vector3(box[3] - box[0], box[4] - box[1], box[5] - box[2]).length() / 2;
  sun.position.copy(center).addScaledVector(SUN_DIR, radius + 400);
  sun.target.position.copy(center);
  const cam = sun.shadow.camera;
  cam.left = -radius; cam.right = radius; cam.top = radius; cam.bottom = -radius;
  cam.near = 1; cam.far = radius * 2 + 800;
  cam.updateProjectionMatrix();
  sun.shadow.needsUpdate = true;
  sun.target.updateMatrixWorld();
}

function placeBillboards(camera) {
  const right = new THREE.Vector3(), up = new THREE.Vector3(), back = new THREE.Vector3();
  camera.matrixWorld.extractBasis(right, up, back);
  const tanV = Math.tan(THREE.MathUtils.degToRad(camera.fov / 2));
  const height = currentSize[1];
  const guiScale = height / 1080; // Roblox gui pixels on a 1080p screen
  for (const b of billboards) {
    const g = b.gui;
    const p = new THREE.Vector3(...g.Position).add(new THREE.Vector3(...g.StudsOffsetWorldSpace));
    const so = g.StudsOffset;
    p.addScaledVector(right, so[0]).addScaledVector(up, so[1]).addScaledVector(back, so[2]);
    const distance = p.distanceTo(camera.position);
    const inFront = p.clone().sub(camera.position).dot(back) < 0;
    b.sprite.visible = inFront && distance <= (g.MaxDistance ?? 1e9) && distance > 1;
    if (!b.sprite.visible) continue;
    b.sprite.position.copy(p);
    // pixel part: constant size on screen; stud part: grows with closeness
    const toScreen = (2 * tanV) / height; // view-space units at distance 1 per screen pixel
    const sw = b.pixelW * guiScale * toScreen + (b.studW / distance);
    const sh = b.pixelH * guiScale * toScreen + (b.studH / distance);
    b.sprite.scale.set(sw, sh, 1);
  }
}

// Per-shot lighting (each region uses its zone's Lighting preset)
function applyLighting(l) {
  skyMaterial.uniforms.zenith.value.set('#' + l.sky.zenith);
  skyMaterial.uniforms.horizon.value.set('#' + l.sky.horizon);
  skyMaterial.uniforms.below.value.set('#' + l.sky.below);
  skyMaterial.uniforms.screenTop.value.set('#' + l.sky.screenTop);
  skyMaterial.uniforms.screenBottom.value.set('#' + l.sky.screenBottom);
  skyMaterial.uniforms.stars.value = l.sky.stars || 0;
  world.fog.color.set('#' + l.fog.color);
  hemi.color.set('#' + l.hemi.sky);
  hemi.groundColor.set('#' + l.hemi.ground);
  hemi.intensity = l.hemi.intensity;
  sun.color.set('#' + l.sun.color);
  sun.intensity = l.sun.intensity;
  SUN_DIR.set(...l.sun.direction).normalize();
  renderer.toneMappingExposure = (settings.exposure ?? 1.0) * (l.exposure ?? 1);
  bloom.strength = l.bloom.strength;
  bloom.radius = l.bloom.radius;
  bloom.threshold = l.bloom.threshold;
  grade.uniforms.saturation.value = l.grade.saturation;
  grade.uniforms.contrast.value = l.grade.contrast;
  grade.uniforms.brightness.value = l.grade.brightness;
  grade.uniforms.tint.value.set(...l.grade.tint);
}

let currentSize = [W, H];
function resize(w, h) {
  if (currentSize[0] === w && currentSize[1] === h) return;
  currentSize = [w, h];
  renderer.setSize(w, h);
  composer.setSize(w, h);
  fxaa.material.uniforms.resolution.value.set(1 / w, 1 / h);
  skyMaterial.uniforms.height.value = h;
}

const results = [];
for (const shot of scene.shots) {
  const t0 = performance.now();
  const [sw, sh] = shot.size || [W, H];
  resize(sw, sh);
  applyLighting(shot.lighting || L);
  const camera = new THREE.PerspectiveCamera(shot.fov, sw / sh, 0.5, 20000);
  let focusDistance;
  if (shot.kind === 'eye') {
    camera.position.set(...shot.position);
    camera.lookAt(new THREE.Vector3(...shot.look));
    focusDistance = 160;
  } else {
    const box = shot.focus;
    const center = new THREE.Vector3((box[0] + box[3]) / 2, (box[1] + box[4]) / 2, (box[2] + box[5]) / 2);
    if (shot.center) center.set(...shot.center);
    const dir = new THREE.Vector3(...shot.dir).normalize();
    const distance = fitDistance(camera, center, box, dir) * (shot.margin ?? 1.04);
    camera.position.copy(center).addScaledVector(dir, distance);
    camera.lookAt(center);
    focusDistance = distance;
  }
  camera.updateMatrixWorld();
  sky.position.copy(camera.position);
  sky.scale.setScalar(15000);
  skyMaterial.uniforms.screenMix.value = shot.kind === 'eye' ? 0 : 1;
  const fog = shot.fog || [focusDistance * 1.2, focusDistance * 4.5];
  world.fog.near = fog[0];
  world.fog.far = fog[1];
  setShadowBox(shot.shadow);
  placeBillboards(camera);
  renderPass.camera = camera;
  composer.render();
  const blob = await new Promise((resolve) => renderer.domElement.toBlob(resolve, 'image/png'));
  await post('/__shot?name=' + encodeURIComponent(shot.name), blob);
  results.push(`${shot.name} ${Math.round(performance.now() - t0)}ms`);
}

log(`rendered ${scene.shots.length} shots, ${instanceCount} part instances: ${results.join(', ')}`);
post('/__done', 'ok');
