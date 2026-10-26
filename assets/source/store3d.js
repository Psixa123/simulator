// Storm Catcher Simulator - 3D store badges: drawing helpers (assets/source/store3d.html uses them).
//
// A badge is 1024 x 1024 (rendered at 512 by tools/render_art.py): a sunburst in the item's colour, a soft glow,
// the item's 3D hero render (assets/source/store3d/Store_<Key>.png, made by tools/icons/render_icons.py --set
// store from the SketchUp models), sparkles, then candy labels with thick Ink outlines. Roblox shows pass icons
// cropped to a circle, so everything that matters stays inside a centred circle of radius ~430.
// Builds on assets/source/art.js (lin, rad, uid, sky, rays, sparkle).

const INK3 = "#233066"; // the Ink of the 3D renders' outlines (docs/STYLE_GUIDE.md)
const LABEL_FONT = "Luckiest Guy";

// ------------------------------------------------------------------ background
// Sunburst: a radial gradient in the item's colour, two rings of rays and a dark rim (vignette).
function burst(bg, cx = 512, cy = 470) {
  const rim = rad([[0, "#000000", 0], [0.68, "#000000", 0], [1, "#000000", 0.38]], 0.5, 0.5, 0.72);
  return sky(1024, 1024, bg, cx / 1024, cy / 1024) + rays(cx, cy, 900, 20, "#ffffff", 0.13) +
    rays(cx, cy, 900, 20, "#ffffff", 0.06, 0.22) + `<defs>${rim.def}</defs>` +
    `<rect width="1024" height="1024" fill="${rim.url}" data-layer="rim"/>`;
}

// Soft light behind the hero: a white core fading into the badge colour.
function glow(cx, cy, r, tint = "#ffffff", strength = 0.6) {
  const g = rad([[0, tint, strength], [0.45, tint, strength * 0.45], [1, tint, 0]], 0.5, 0.5, 0.5);
  return `<defs>${g.def}</defs><circle cx="${cx}" cy="${cy}" r="${r}" fill="${g.url}"/>`;
}

// A blurred contact shadow under the hero, so it sits on the badge instead of floating.
function floorShadow(cx, cy, rx, ry, opacity = 0.32) {
  return `<ellipse cx="${cx}" cy="${cy}" rx="${rx}" ry="${ry}" fill="${INK3}" opacity="${opacity}" filter="url(#softGlow)"/>`;
}

// The hero render, centred on (cx, cy), `size` px square (the PNG is square with transparent margins).
function hero(key, cx, cy, size, rot = 0) {
  const x = cx - size / 2, y = cy - size / 2;
  const turn = rot ? ` transform="rotate(${rot} ${cx} ${cy})"` : "";
  return `<image href="store3d/Store_${key}.png" x="${x}" y="${y}" width="${size}" height="${size}"${turn}/>`;
}

function sparkles(spots, color = "#ffffff") {
  let out = "";
  for (const [x, y, r, o] of spots) {
    out += sparkle(x, y, r * 1.35, color, (o === undefined ? 0.95 : o) * 0.35) + sparkle(x, y, r, color, o === undefined ? 0.95 : o);
  }
  return out;
}

// ------------------------------------------------------------------ candy labels
// Chunky 3D text: an Ink extrusion stacked under a candy gradient face with a thick Ink outline and a gloss.
function label3d(x, y, text, size, o = {}) {
  const colors = o.colors || ["#ffffff", "#fff3a6", "#ffc531"];
  const face = lin(colors.map((c, i) => [i / (colors.length - 1), c]));
  const gloss = lin([[0, "#ffffff", 0.85], [0.5, "#ffffff", 0], [1, "#ffffff", 0]]);
  const stroke = o.stroke || size * 0.2;
  const depth = o.depth || size * 0.09;
  const common = `font-family="${LABEL_FONT}" font-size="${size}" text-anchor="middle" letter-spacing="${o.spacing || 1}"`;
  let out = `<defs>${face.def}${gloss.def}</defs><g transform="translate(${x},${y}) rotate(${o.rot || 0})">`;
  for (let d = depth; d > 0; d -= Math.max(1, depth / 6)) {
    out += `<text ${common} y="${d}" fill="${INK3}" stroke="${INK3}" stroke-width="${stroke}" stroke-linejoin="round">${text}</text>`;
  }
  out += `<text ${common} fill="${face.url}" stroke="${INK3}" stroke-width="${stroke}" stroke-linejoin="round" paint-order="stroke">${text}</text>`;
  out += `<text ${common} fill="${gloss.url}" opacity="0.7">${text}</text>`;
  return out + `</g>`;
}

// A curved candy banner (its ends lifted to follow the badge's round bottom), folded tails behind both ends,
// and white text with an Ink outline running along the curve.
function banner(x, y, w, h, text, o = {}) {
  const c1 = o.c1 || "#ff7ac0", c2 = o.c2 || "#c93a8f", c3 = o.c3 || shade(c2, 0.62);
  const sag = o.sag === undefined ? 26 : o.sag;
  const band = lin([[0, c1], [1, c2]]);
  const id = uid("arc");
  const half = w / 2;
  // the band between two parallel arcs: top edge from (-half, -h/2) to (half, -h/2) dipping by `sag`
  const top = `M${-half},${-h / 2} Q0,${-h / 2 + 2 * sag} ${half},${-h / 2}`;
  const bandPath = `${top} L${half},${h / 2} Q0,${h / 2 + 2 * sag} ${-half},${h / 2} Z`;
  const mid = `M${-half + 20},${6} Q0,${6 + 2 * sag} ${half - 20},${6}`;
  const tail = (s) => {
    const x0 = s * (half - 30), x1 = s * (half + 56), yb = h * 0.18;
    return `<path d="M${x0},${-h / 2 + yb} L${x1},${-h / 2 + yb} L${x1 - s * 28},${yb * 0.3 + 10} L${x1},${h / 2 + yb} L${x0},${h / 2 + yb} Z" ` +
      `fill="${c3}" stroke="${INK3}" stroke-width="10" stroke-linejoin="round"/>` +
      `<path d="M${s * (half - 30)},${h / 2 + yb} L${s * half},${h / 2} L${s * half},${h / 2 + yb + 4} Z" fill="${INK3}"/>`;
  };
  const size = o.size || h * 0.7;
  let out = `<defs>${band.def}<path id="${id}" d="${mid}"/></defs><g transform="translate(${x},${y}) rotate(${o.rot || 0})">`;
  out += tail(-1) + tail(1);
  out += `<path d="${bandPath}" transform="translate(0,12)" fill="${INK3}" opacity="0.9"/>`;
  out += `<path d="${bandPath}" fill="${band.url}" stroke="${INK3}" stroke-width="10" stroke-linejoin="round"/>`;
  out += `<path d="M${-half + 18},${-h / 2 + 16} Q0,${-h / 2 + 16 + 2 * sag} ${half - 18},${-h / 2 + 16}" fill="none" ` +
    `stroke="#ffffff" stroke-width="${h * 0.16}" stroke-linecap="round" opacity="0.32"/>`;
  const t = `<textPath href="#${id}" startOffset="50%">${text}</textPath>`;
  const common = `font-family="${LABEL_FONT}" font-size="${size}" text-anchor="middle" letter-spacing="${o.spacing || 2}" dy="${size * 0.36}"`;
  out += `<text ${common} fill="${INK3}" stroke="${INK3}" stroke-width="${size * 0.2}" stroke-linejoin="round" transform="translate(0,7)">${t}</text>`;
  out += `<text ${common} fill="#ffffff" stroke="${INK3}" stroke-width="${size * 0.2}" stroke-linejoin="round" paint-order="stroke">${t}</text>`;
  return out + `</g>`;
}

// A darker step of a #rrggbb colour (k < 1) for the banner's folded tails.
function shade(hex, k) {
  const n = parseInt(hex.slice(1), 16);
  const c = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map((v) => Math.round(v * k));
  return "#" + c.map((v) => v.toString(16).padStart(2, "0")).join("");
}

// Soft aurora curtains behind the Aurora Gryphon (mint and violet bands, blurred).
function auroraBands() {
  const band = (y, amp, color, width, opacity, phase) => {
    let d = "";
    for (let x = -40; x <= 1064; x += 24) {
      const yy = y + Math.sin(x / 150 + phase) * amp + Math.sin(x / 61 + phase * 2) * amp * 0.25;
      d += (x === -40 ? "M" : " L") + x + "," + yy.toFixed(1);
    }
    return `<path d="${d}" fill="none" stroke="${color}" stroke-width="${width}" stroke-linecap="round" opacity="${opacity}" filter="url(#softGlow)"/>`;
  };
  return band(230, 60, "#8dffe0", 90, 0.55, 0.4) + band(310, 70, "#c9a2ff", 70, 0.5, 2.1) + band(170, 40, "#ffffff", 34, 0.35, 1.3);
}
