// Shared SVG drawing helpers for Storm Catcher Simulator artwork.
// Every function returns an SVG markup string. Pages build one big <svg> from them.

const INK = "#0d1030";
let _uid = 0;
const uid = (prefix) => `${prefix}${++_uid}`;

function lin(stops, x1 = 0, y1 = 0, x2 = 0, y2 = 1, units = "") {
  const id = uid("lg");
  const body = stops
    .map(([o, c, a]) => `<stop offset="${o}" stop-color="${c}"${a !== undefined ? ` stop-opacity="${a}"` : ""}/>`)
    .join("");
  return {
    id,
    url: `url(#${id})`,
    def: `<linearGradient id="${id}" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}"${units ? ` gradientUnits="${units}"` : ""}>${body}</linearGradient>`,
  };
}

function rad(stops, cx = 0.5, cy = 0.5, r = 0.5) {
  const id = uid("rg");
  const body = stops
    .map(([o, c, a]) => `<stop offset="${o}" stop-color="${c}"${a !== undefined ? ` stop-opacity="${a}"` : ""}/>`)
    .join("");
  return { id, url: `url(#${id})`, def: `<radialGradient id="${id}" cx="${cx}" cy="${cy}" r="${r}">${body}</radialGradient>` };
}

function baseDefs() {
  return `<defs>
    <filter id="glow" x="-60%" y="-60%" width="220%" height="220%">
      <feGaussianBlur stdDeviation="12" result="b"/>
      <feMerge><feMergeNode in="b"/><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
    <filter id="softGlow" x="-60%" y="-60%" width="220%" height="220%">
      <feGaussianBlur stdDeviation="22"/>
    </filter>
    <filter id="drop" x="-20%" y="-20%" width="140%" height="150%">
      <feDropShadow dx="0" dy="10" stdDeviation="0" flood-color="${INK}" flood-opacity="0.85"/>
    </filter>
  </defs>`;
}

// ---------------------------------------------------------------- backgrounds
function sky(w, h, colors = ["#8a6bff", "#3f2db4", "#140e50"], cx = 0.5, cy = 0.42) {
  const g = rad([[0, colors[0]], [0.55, colors[1]], [1, colors[2]]], cx, cy, 0.8);
  return `<defs>${g.def}</defs><rect width="${w}" height="${h}" fill="${g.url}"/>`;
}

function rays(cx, cy, radius, count, color = "#ffffff", opacity = 0.1, spread = 0.45) {
  let out = `<g transform="translate(${cx},${cy})" opacity="${opacity}">`;
  for (let i = 0; i < count; i++) {
    const a0 = (i / count) * Math.PI * 2;
    const a1 = a0 + ((Math.PI * 2) / count) * spread;
    out += `<path d="M0,0 L${Math.cos(a0) * radius},${Math.sin(a0) * radius} L${Math.cos(a1) * radius},${Math.sin(a1) * radius} Z" fill="${color}"/>`;
  }
  return out + `</g>`;
}

function sparkle(x, y, r, fill = "#ffffff", opacity = 1) {
  const k = r * 0.16;
  return `<path transform="translate(${x},${y})" opacity="${opacity}" fill="${fill}" d="M0,${-r} Q${k},${-k} ${r},0 Q${k},${k} 0,${r} Q${-k},${k} ${-r},0 Q${-k},${-k} 0,${-r} Z"/>`;
}

function hills(w, baseY, amp, color, phase = 0, freq = 2, bottom = 2000) {
  let d = `M0,${bottom} L0,${baseY}`;
  for (let x = 0; x <= w; x += 20) {
    const y = baseY - Math.sin((x / w) * Math.PI * freq + phase) * amp - Math.sin((x / w) * Math.PI * freq * 2.3 + phase * 2) * amp * 0.25;
    d += ` L${x},${y.toFixed(1)}`;
  }
  return `<path d="${d} L${w},${bottom} Z" fill="${color}"/>`;
}

// ---------------------------------------------------------------- weather
const CLOUD_PUFFS = [
  [0, 0, 62], [-72, 22, 46], [74, 20, 50], [-32, -36, 44], [38, -32, 48], [-114, 38, 30], [116, 38, 30],
];

function cloud(x, y, s = 1, fill = "#ffffff", shade = "#cfe0ff", ink = INK, outline = 9) {
  let out = `<g transform="translate(${x},${y}) scale(${s})">`;
  if (ink) {
    for (const [cx, cy, r] of CLOUD_PUFFS) out += `<circle cx="${cx}" cy="${cy}" r="${r + outline}" fill="${ink}"/>`;
    out += `<rect x="${-122 - outline}" y="18" width="${244 + outline * 2}" height="${50 + outline}" rx="30" fill="${ink}"/>`;
  }
  for (const [cx, cy, r] of CLOUD_PUFFS) out += `<circle cx="${cx}" cy="${cy}" r="${r}" fill="${shade}"/>`;
  out += `<rect x="-122" y="18" width="244" height="50" rx="26" fill="${shade}"/>`;
  for (const [cx, cy, r] of CLOUD_PUFFS) out += `<circle cx="${cx - 5}" cy="${cy - 9}" r="${r - 7}" fill="${fill}"/>`;
  out += `<rect x="-120" y="12" width="232" height="38" rx="20" fill="${fill}"/>`;
  return out + `</g>`;
}

function tornado(x, y, s = 1, o = {}) {
  const n = o.bands || 10;
  const step = o.step || 46;
  const rTop = o.rTop || 190;
  const rBot = o.rBot || 24;
  const g = lin([[0, o.dark || "#3b66d4"], [0.3, o.light || "#eafaff"], [0.62, o.mid || "#8fd6ff"], [1, o.dark || "#3b66d4"]], 0, 0, 1, 0);
  let out = `<defs>${g.def}</defs><g transform="translate(${x},${y}) scale(${s})">`;
  const bands = [];
  for (let i = 0; i < n; i++) {
    const t = i / (n - 1);
    const r = rTop + (rBot - rTop) * Math.pow(t, 0.78);
    bands.push({ r, cx: Math.sin(t * 3.4 + (o.phase || 0)) * 52 * t, cy: i * step, ry: 15 + r * 0.17 });
  }
  for (let i = n - 1; i >= 0; i--) {
    const b = bands[i];
    out += `<ellipse cx="${b.cx}" cy="${b.cy}" rx="${b.r + 8}" ry="${b.ry + 8}" fill="${INK}"/>`;
    out += `<ellipse cx="${b.cx}" cy="${b.cy}" rx="${b.r}" ry="${b.ry}" fill="${g.url}"/>`;
    out += `<path d="M${b.cx - b.r * 0.74},${b.cy + 3} Q${b.cx},${b.cy + b.ry * 1.3} ${b.cx + b.r * 0.74},${b.cy + 3}" fill="none" stroke="#ffffff" stroke-opacity="0.7" stroke-width="6" stroke-linecap="round"/>`;
  }
  return out + `</g>`;
}

function bolt(x, y, s = 1, rot = 0, c1 = "#fff36b", c2 = "#ffb21e") {
  const g = lin([[0, c1], [1, c2]]);
  const pts = "30,0 -30,86 8,86 -24,178 62,64 22,64 48,0";
  return `<defs>${g.def}</defs><g transform="translate(${x},${y}) rotate(${rot}) scale(${s})">
    <polygon points="${pts}" fill="${INK}" stroke="${INK}" stroke-width="16" stroke-linejoin="round"/>
    <polygon points="${pts}" fill="${g.url}"/>
    <polygon points="30,8 2,50 20,50 36,8" fill="#ffffff" opacity="0.55"/>
  </g>`;
}

function beam(x1, y1, x2, y2, w1, w2, color = "#6fe3ff") {
  const dx = x2 - x1, dy = y2 - y1;
  const len = Math.hypot(dx, dy);
  const nx = -dy / len, ny = dx / len;
  const g = lin([[0, color, 0.95], [0.7, color, 0.45], [1, color, 0.05]], x1, y1, x2, y2, "userSpaceOnUse");
  const g2 = lin([[0, "#ffffff", 0.95], [0.6, "#ffffff", 0.35], [1, "#ffffff", 0]], x1, y1, x2, y2, "userSpaceOnUse");
  const poly = (a, b) =>
    `${x1 + nx * a},${y1 + ny * a} ${x2 + nx * b},${y2 + ny * b} ${x2 - nx * b},${y2 - ny * b} ${x1 - nx * a},${y1 - ny * a}`;
  let out = `<defs>${g.def}${g2.def}</defs>`;
  out += `<polygon points="${poly(w1, w2)}" fill="${g.url}" filter="url(#glow)"/>`;
  out += `<polygon points="${poly(w1 * 0.4, w2 * 0.35)}" fill="${g2.url}"/>`;
  for (let i = 1; i <= 6; i++) {
    const t = i / 7;
    const side = (i % 2 === 0 ? 1 : -1) * (w1 + (w2 - w1) * t) * 0.6;
    out += sparkle(x1 + dx * t + nx * side, y1 + dy * t + ny * side, 10 + t * 14, "#ffffff", 0.9 - t * 0.4);
  }
  return out;
}

// ---------------------------------------------------------------- props
function vacuum(x, y, s = 1, rot = 0) {
  const body = lin([[0, "#f2f6ff"], [0.5, "#b7c2e0"], [1, "#7c88ad"]]);
  const dark = lin([[0, "#5a648c"], [1, "#2a3052"]]);
  return `<defs>${body.def}${dark.def}</defs><g transform="translate(${x},${y}) rotate(${rot}) scale(${s})" stroke="${INK}" stroke-width="7" stroke-linejoin="round">
    <rect x="-16" y="14" width="30" height="54" rx="10" fill="${dark.url}"/>
    <rect x="6" y="20" width="12" height="18" rx="4" fill="#ffd23c"/>
    <rect x="-78" y="-30" width="30" height="60" rx="11" fill="${dark.url}"/>
    <rect x="-60" y="-25" width="152" height="50" rx="22" fill="${body.url}"/>
    <rect x="8" y="-27" width="12" height="54" rx="4" fill="#5fdcff"/>
    <rect x="36" y="-27" width="12" height="54" rx="4" fill="#5fdcff"/>
    <polygon points="86,-27 150,-46 150,46 86,27" fill="${dark.url}"/>
    <ellipse cx="150" cy="0" rx="13" ry="44" fill="#8cecff"/>
    <circle cx="-12" cy="-46" r="26" fill="#d6f3ff"/>
    <circle cx="-12" cy="-46" r="14" fill="#48cfff" stroke="none"/>
    <circle cx="-20" cy="-55" r="6" fill="#ffffff" stroke="none"/>
  </g>`;
}

function egg(x, y, s = 1, color = "#96e66e", accent = "#fff08c", rot = 0) {
  const g = rad([[0, "#ffffff", 0.75], [0.35, color], [1, color]], 0.35, 0.28, 0.9);
  const clip = uid("clip");
  const shape = "M0,-104 C56,-104 88,-22 88,30 C88,84 46,112 0,112 C-46,112 -88,84 -88,30 C-88,-22 -56,-104 0,-104 Z";
  return `<defs>${g.def}<clipPath id="${clip}"><path d="${shape}"/></clipPath></defs>
  <g transform="translate(${x},${y}) rotate(${rot}) scale(${s})">
    <path d="${shape}" fill="${INK}" stroke="${INK}" stroke-width="16" stroke-linejoin="round"/>
    <path d="${shape}" fill="${g.url}"/>
    <g clip-path="url(#${clip})" fill="${accent}">
      <ellipse cx="-46" cy="-10" rx="22" ry="26"/><ellipse cx="40" cy="-48" rx="18" ry="20"/>
      <ellipse cx="52" cy="38" rx="26" ry="24"/><ellipse cx="-22" cy="70" rx="24" ry="20"/>
      <ellipse cx="-78" cy="52" rx="18" ry="22"/><ellipse cx="2" cy="-92" rx="16" ry="14"/>
    </g>
    <ellipse cx="-34" cy="-58" rx="16" ry="26" fill="#ffffff" opacity="0.45" transform="rotate(24 -34 -58)"/>
  </g>`;
}

// Coin seen from the front with a lightning emblem
function coinFront(x, y, r = 60) {
  const g = lin([[0, "#fff68a"], [0.55, "#ffd23c"], [1, "#ff9a1e"]]);
  const k = r / 110;
  return `<defs>${g.def}</defs><g transform="translate(${x},${y})">
    <circle r="${r + 8}" fill="${INK}"/>
    <circle r="${r}" fill="#e08a1a"/>
    <circle r="${r}" cy="${-r * 0.07}" fill="${g.url}"/>
    <circle r="${r * 0.76}" cy="${-r * 0.07}" fill="none" stroke="#fff7b0" stroke-width="${r * 0.07}" opacity="0.8"/>
    <polygon transform="translate(${-14 * k},${-96 * k}) scale(${k})" points="30,0 -30,86 8,86 -24,178 62,64 22,64 48,0" fill="#fffbe0" stroke="#d9801a" stroke-width="${8}" stroke-linejoin="round"/>
  </g>`;
}

// Stack of coins seen at an angle. Origin = center of the bottom coin.
function coinStack(x, y, count = 3, r = 70) {
  const g = lin([[0, "#fff68a"], [1, "#ffb21e"]]);
  const ry = r * 0.4;
  const h = r * 0.3;
  let out = `<defs>${g.def}</defs><g transform="translate(${x},${y})">`;
  for (let i = 0; i < count; i++) {
    const cy = -i * h;
    out += `<path d="M${-r},${cy} v${h} a${r},${ry} 0 0 0 ${r * 2},0 v${-h} Z" fill="#e08a1a" stroke="${INK}" stroke-width="8" stroke-linejoin="round"/>`;
    out += `<ellipse cx="0" cy="${cy}" rx="${r}" ry="${ry}" fill="${g.url}" stroke="${INK}" stroke-width="8"/>`;
    out += `<ellipse cx="0" cy="${cy}" rx="${r * 0.66}" ry="${ry * 0.66}" fill="none" stroke="#fff7b0" stroke-width="5" opacity="0.8"/>`;
  }
  return out + `</g>`;
}

// ---------------------------------------------------------------- pets
function petFace(o = {}) {
  const eye = o.eye || INK;
  return `
    <ellipse cx="-22" cy="-4" rx="10" ry="13" fill="${eye}"/><ellipse cx="22" cy="-4" rx="10" ry="13" fill="${eye}"/>
    <circle cx="-18" cy="-9" r="4" fill="#fff"/><circle cx="26" cy="-9" r="4" fill="#fff"/>
    <ellipse cx="-42" cy="14" rx="11" ry="7" fill="#ff8fb3" opacity="0.75"/><ellipse cx="42" cy="14" rx="11" ry="7" fill="#ff8fb3" opacity="0.75"/>
    <path d="M-9,14 Q0,24 9,14" fill="none" stroke="${INK}" stroke-width="4.5" stroke-linecap="round"/>`;
}

// o: { body: "round"|"cloud"|"drop"|"bean", color, accent, features: [...], eye, fill }
// fill: optional paint (e.g. a gradient url) for the body instead of the shaded `color`
function pet(x, y, s = 1, o = {}) {
  const color = o.color || "#ffffff";
  const accent = o.accent || "#ffd23c";
  const f = new Set(o.features || []);
  const g = rad([[0, "#ffffff", 0.9], [0.3, color], [1, color]], 0.34, 0.26, 0.95);
  const top = o.body === "drop" ? -100 : o.body === "cloud" ? -72 : o.body === "bean" ? -74 : -64;
  const bodyFill = o.fill || g.url;
  let back = "", front = "";
  const S = `stroke="${INK}" stroke-width="7" stroke-linejoin="round"`;

  if (f.has("rays")) {
    for (let i = 0; i < 10; i++) back += `<rect x="-9" y="-104" width="18" height="34" rx="8" fill="${accent}" ${S} transform="rotate(${i * 36})"/>`;
  }
  if (f.has("wings")) {
    back += `<ellipse cx="-78" cy="-18" rx="34" ry="20" fill="${accent}" ${S} transform="rotate(28 -78 -18)"/>`;
    back += `<ellipse cx="78" cy="-18" rx="34" ry="20" fill="${accent}" ${S} transform="rotate(-28 78 -18)"/>`;
  }
  if (f.has("ears")) {
    back += `<path d="M-52,${top + 26} L-44,${top - 22} L-14,${top + 8} Z" fill="${color}" ${S}/><path d="M52,${top + 26} L44,${top - 22} L14,${top + 8} Z" fill="${color}" ${S}/>`;
  }
  if (f.has("bunny")) {
    back += `<ellipse cx="-24" cy="${top - 16}" rx="14" ry="38" fill="${color}" ${S} transform="rotate(-10 -24 ${top - 16})"/><ellipse cx="24" cy="${top - 16}" rx="14" ry="38" fill="${color}" ${S} transform="rotate(10 24 ${top - 16})"/>`;
    back += `<ellipse cx="-24" cy="${top - 16}" rx="6" ry="24" fill="${accent}" transform="rotate(-10 -24 ${top - 16})"/><ellipse cx="24" cy="${top - 16}" rx="6" ry="24" fill="${accent}" transform="rotate(10 24 ${top - 16})"/>`;
  }
  if (f.has("horns")) {
    back += `<path d="M-40,${top + 22} Q-62,${top - 8} -46,${top - 34} Q-30,${top - 6} -20,${top + 10} Z" fill="${accent}" ${S}/><path d="M40,${top + 22} Q62,${top - 8} 46,${top - 34} Q30,${top - 6} 20,${top + 10} Z" fill="${accent}" ${S}/>`;
  }
  if (f.has("antenna")) {
    back += `<line x1="0" y1="${top + 8}" x2="0" y2="${top - 30}" stroke="${INK}" stroke-width="9" stroke-linecap="round"/><circle cx="0" cy="${top - 36}" r="12" fill="${accent}" ${S}/>`;
  }

  let body;
  if (o.body === "cloud") {
    const puffs = [[0, 0, 62], [-56, 16, 38], [56, 16, 38], [-26, -34, 36], [26, -36, 38]];
    body = puffs.map(([cx, cy, r]) => `<circle cx="${cx}" cy="${cy}" r="${r + 7}" fill="${INK}"/>`).join("") +
      puffs.map(([cx, cy, r]) => `<circle cx="${cx}" cy="${cy}" r="${r}" fill="${color}"/>`).join("") +
      `<circle cx="-14" cy="-22" r="34" fill="#ffffff" opacity="0.35"/>`;
  } else if (o.body === "drop") {
    body = `<path d="M0,-100 C30,-58 64,-28 64,8 A64,64 0 1 1 -64,8 C-64,-28 -30,-58 0,-100 Z" fill="${bodyFill}" ${S}/>`;
  } else if (o.body === "bean") {
    body = `<ellipse cx="0" cy="-4" rx="56" ry="70" fill="${bodyFill}" ${S}/>`;
  } else {
    body = `<circle cx="0" cy="0" r="64" fill="${bodyFill}" ${S}/>`;
  }

  if (o.fill) {
    front += `<ellipse cx="-20" cy="-36" rx="16" ry="24" fill="#ffffff" opacity="0.5" transform="rotate(20 -20 -36)"/>`;
  }
  if (f.has("flame")) {
    front += `<path d="M0,${top - 44} C18,${top - 22} 24,${top - 6} 0,${top + 10} C-24,${top - 6} -18,${top - 22} 0,${top - 44} Z" fill="#ff8a1e" ${S}/><path d="M0,${top - 24} C8,${top - 12} 10,${top - 2} 0,${top + 4} C-10,${top - 2} -8,${top - 12} 0,${top - 24} Z" fill="#ffe14a"/>`;
  }
  if (f.has("crown")) {
    front += `<path d="M-34,${top + 12} L-40,${top - 26} L-18,${top - 8} L0,${top - 36} L18,${top - 8} L40,${top - 26} L34,${top + 12} Z" fill="#ffd23c" ${S}/><circle cx="0" cy="${top - 2}" r="6" fill="#ff4d7a"/>`;
  }
  if (f.has("halo")) {
    front += `<ellipse cx="0" cy="${top - 30}" rx="34" ry="10" fill="none" stroke="${INK}" stroke-width="14"/><ellipse cx="0" cy="${top - 30}" rx="34" ry="10" fill="none" stroke="${accent}" stroke-width="7"/>`;
  }
  if (f.has("bolt")) {
    front += bolt(-8, top - 46, 0.3, 0);
  }

  return `<defs>${g.def}</defs><g transform="translate(${x},${y}) scale(${s})">${back}${body}${petFace(o)}${front}</g>`;
}

// ---------------------------------------------------------------- character
// Blocky storm chaser. Origin = between the feet. armAngle: 0 = pointing right, -90 = up.
function character(x, y, s = 1, o = {}) {
  const jacket = o.jacket || "#33b5f5";
  const pants = o.pants || "#2a2f63";
  const skin = o.skin || "#ffd8b0";
  const hair = o.hair || "#5b3a26";
  const arm = o.armAngle === undefined ? -35 : o.armAngle;
  const S = `stroke="${INK}" stroke-width="6" stroke-linejoin="round"`;
  return `<g transform="translate(${x},${y}) scale(${s})">
    <rect x="-66" y="-214" width="34" height="66" rx="13" fill="#d6f3ff" ${S}/>
    <rect x="-62" y="-184" width="26" height="32" rx="8" fill="#48cfff"/>
    <rect x="-36" y="-80" width="32" height="80" rx="7" fill="${pants}" ${S}/>
    <rect x="4" y="-80" width="32" height="80" rx="7" fill="${pants}" ${S}/>
    <rect x="-42" y="-16" width="40" height="18" rx="8" fill="#161935" ${S}/>
    <rect x="2" y="-16" width="40" height="18" rx="8" fill="#161935" ${S}/>
    <rect x="-68" y="-164" width="28" height="86" rx="10" fill="${jacket}" ${S}/>
    <rect x="-66" y="-90" width="24" height="22" rx="9" fill="${skin}" ${S}/>
    <rect x="-42" y="-168" width="84" height="94" rx="11" fill="${jacket}" ${S}/>
    <rect x="-5" y="-165" width="10" height="88" fill="#c8eeff"/>
    <rect x="-42" y="-92" width="84" height="14" fill="#1d2150"/>
    <rect x="-10" y="-94" width="20" height="18" rx="4" fill="#ffd23c" ${S}/>
    <g transform="translate(40,-150) rotate(${arm})">
      <rect x="-8" y="-14" width="92" height="28" rx="10" fill="${jacket}" ${S}/>
      <rect x="76" y="-13" width="24" height="26" rx="9" fill="${skin}" ${S}/>
    </g>
    <rect x="-38" y="-242" width="76" height="74" rx="15" fill="${skin}" ${S}/>
    <path d="M-42,-214 L-42,-234 Q-42,-252 -20,-252 L20,-252 Q42,-252 42,-234 L42,-214 L30,-226 L-30,-226 Z" fill="${hair}" ${S}/>
    <rect x="-42" y="-236" width="84" height="16" rx="6" fill="#1d2150" ${S}/>
    <circle cx="-17" cy="-229" r="12" fill="#8cecff" ${S}/><circle cx="17" cy="-229" r="12" fill="#8cecff" ${S}/>
    <circle cx="-21" cy="-233" r="4" fill="#ffffff"/><circle cx="13" cy="-233" r="4" fill="#ffffff"/>
    <rect x="-22" y="-208" width="11" height="17" rx="5" fill="${INK}"/><rect x="11" y="-208" width="11" height="17" rx="5" fill="${INK}"/>
    <path d="M-13,-184 Q0,-171 13,-184" fill="none" stroke="${INK}" stroke-width="5.5" stroke-linecap="round"/>
    <ellipse cx="-27" cy="-186" rx="7" ry="5" fill="#ff9db8" opacity="0.8"/><ellipse cx="27" cy="-186" rx="7" ry="5" fill="#ff9db8" opacity="0.8"/>
  </g>`;
}

// Where the character's hand ends up (for attaching the vacuum)
function characterHand(x, y, s, armAngle = -35) {
  const a = (armAngle * Math.PI) / 180;
  return { x: x + (40 + Math.cos(a) * 92) * s, y: y + (-150 + Math.sin(a) * 92) * s };
}

// ---------------------------------------------------------------- text
function title(x, y, text, size, o = {}) {
  const g = lin(o.colors ? o.colors.map((c, i) => [i / (o.colors.length - 1), c]) : [[0, "#fff68a"], [0.5, "#ffd23c"], [1, "#ff8a1e"]]);
  const stroke = o.stroke === undefined ? size * 0.2 : o.stroke;
  const font = o.font || "Luckiest Guy";
  const anchor = o.anchor || "middle";
  const rot = o.rot ? ` rotate(${o.rot})` : "";
  const common = `font-family="${font}" font-size="${size}" text-anchor="${anchor}" letter-spacing="${o.spacing || 0}"`;
  return `<defs>${g.def}</defs><g transform="translate(${x},${y})${rot}">
    <text ${common} y="${size * 0.09}" fill="${INK}" stroke="${INK}" stroke-width="${stroke}" stroke-linejoin="round" opacity="0.9">${text}</text>
    <text ${common} fill="${g.url}" stroke="${INK}" stroke-width="${stroke}" stroke-linejoin="round" paint-order="stroke">${text}</text>
    <text ${common} fill="${g.url}">${text}</text>
  </g>`;
}

function ribbon(x, y, w, h, text, o = {}) {
  const g = lin([[0, o.c1 || "#ff7ac0"], [1, o.c2 || "#c93a8f"]]);
  const rot = o.rot || 0;
  const size = o.size || h * 0.62;
  return `<defs>${g.def}</defs><g transform="translate(${x},${y}) rotate(${rot})">
    <rect x="${-w / 2}" y="${-h / 2 + 8}" width="${w}" height="${h}" rx="${h * 0.3}" fill="${INK}" opacity="0.85"/>
    <rect x="${-w / 2}" y="${-h / 2}" width="${w}" height="${h}" rx="${h * 0.3}" fill="${g.url}" stroke="${INK}" stroke-width="${o.outline || 8}"/>
    <rect x="${-w / 2 + 10}" y="${-h / 2 + 7}" width="${w - 20}" height="${h * 0.32}" rx="${h * 0.16}" fill="#ffffff" opacity="0.25"/>
    <text font-family="${o.font || "Luckiest Guy"}" font-size="${size}" text-anchor="middle" y="${size * 0.36}" fill="#ffffff" stroke="${INK}" stroke-width="${size * 0.16}" stroke-linejoin="round" paint-order="stroke" letter-spacing="${o.spacing || 2}">${text}</text>
  </g>`;
}

function svgDoc(w, h, content) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">${baseDefs()}${content}</svg>`;
}

function mount(w, h, content) {
  document.body.innerHTML = svgDoc(w, h, content);
}
