// Drawing helpers for the game page art (icon.html and thumbnail1..3.html in assets/source).
// Titles, candy ribbons, lightning bolts and sparkles in the "Sky Lab" style (docs/STYLE_GUIDE.md), as SVG
// elements that pages place on their #stage with Brand.place(). Call `await Brand.ready()` first: titles
// are measured, so the fonts must be loaded.

const Brand = (() => {
  const INK = "#233066";
  const SVG_NS = "http://www.w3.org/2000/svg";
  let counter = 0;
  const uid = (prefix) => `${prefix}${++counter}`;

  // Colour sets for titles and ribbons (top -> bottom), from the style guide palette
  const FILLS = {
    bolt: [[0, "#fff8b8"], [0.45, "#ffe15a"], [1, "#ffa21f"]],
    cloud: [[0, "#ffffff"], [0.55, "#f1f7ff"], [1, "#bfe0ff"]],
    sky: [[0, "#8fe0ff"], [0.5, "#5cc8ff"], [1, "#2f86f2"]],
    storm: [[0, "#d6c6ff"], [0.5, "#a98bff"], [1, "#6b4be6"]],
    leaf: [[0, "#b8f7a2"], [0.5, "#7be36a"], [1, "#33b24a"]],
    coral: [[0, "#ffb3ba"], [0.5, "#ff7a85"], [1, "#e43a58"]],
    sunset: [[0, "#ffd9a6"], [0.5, "#ffb15c"], [1, "#f2702a"]],
    rainbow: [[0, "#ff6b81"], [0.2, "#ffb347"], [0.4, "#ffe95a"], [0.6, "#6ee88a"], [0.8, "#54c8ff"], [1, "#b48bff"]],
  };

  async function ready() {
    await Promise.all([
      document.fonts.load('100px "Luckiest Guy"', "STORM"),
      document.fonts.load('100px "Fredoka One"', "STORM"),
    ]);
  }

  function gradient(stops, horizontal = false) {
    const id = uid("g");
    const body = stops.map(([offset, color, opacity = 1]) =>
      `<stop offset="${offset}" stop-color="${color}" stop-opacity="${opacity}"/>`).join("");
    const direction = horizontal ? 'x2="1" y2="0"' : 'x2="0" y2="1"';
    return { id, def: `<linearGradient id="${id}" x1="0" y1="0" ${direction}>${body}</linearGradient>` };
  }

  // Width/height of a line of text in a font, measured in a hidden SVG
  function measure(text, font, size, spacing) {
    const probe = document.createElementNS(SVG_NS, "svg");
    probe.setAttribute("style", "position:absolute;left:-9999px;top:0");
    probe.innerHTML = `<text font-family="${font}" font-size="${size}" letter-spacing="${spacing}">${text}</text>`;
    document.body.appendChild(probe);
    const box = probe.querySelector("text").getBBox();
    probe.remove();
    return box;
  }

  function svgElement(width, height, inner) {
    const wrapper = document.createElement("div");
    wrapper.innerHTML = `<svg xmlns="${SVG_NS}" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" overflow="visible">${inner}</svg>`;
    const svg = wrapper.firstChild;
    svg.classList.add("layer");
    return svg;
  }

  // A big title line: gradient fill, thick Ink outline, a solid Ink extrusion underneath, a white gloss on
  // the upper half and a soft shadow. opts: size (font px), fill (FILLS key or stops), stroke, depth,
  // spacing (letter spacing px), font, maxWidth (shrinks the line to fit), gloss (0..1), horizontal (the fill
  // runs left -> right, e.g. FILLS.rainbow)
  function title(text, opts = {}) {
    const font = opts.font || "Luckiest Guy";
    let size = opts.size || 160;
    const spacing = opts.spacing ?? size * 0.02;
    let box = measure(text, font, size, spacing);
    if (opts.maxWidth && box.width > opts.maxWidth) {
      size *= opts.maxWidth / box.width;
      box = measure(text, font, size, spacing);
    }
    const stroke = opts.stroke ?? size * 0.17;
    const depth = opts.depth ?? size * 0.09;
    const pad = stroke + 8;
    const width = Math.ceil(box.width + pad * 2);
    const height = Math.ceil(box.height + pad * 2 + depth);
    const baseline = pad - box.y;
    const fill = gradient(typeof opts.fill === "string" ? FILLS[opts.fill] : (opts.fill || FILLS.bolt), opts.horizontal);
    const gloss = gradient([[0, "#ffffff"], [0.5, "#ffffff"], [0.5001, "#ffffff", 0], [1, "#ffffff", 0]]);
    const shadowId = uid("shadow");
    const line = (attributes, dy = 0) => `<text x="${width / 2}" y="${baseline + dy}" text-anchor="middle"
      font-family="${font}" font-size="${size}" letter-spacing="${spacing}" ${attributes}>${text}</text>`;
    const outline = `fill="${INK}" stroke="${INK}" stroke-width="${stroke}" stroke-linejoin="round" stroke-linecap="round"`;
    const inner = `
      <defs>
        ${fill.def}${gloss.def}
        <filter id="${shadowId}" x="-10%" y="-20%" width="120%" height="160%">
          <feDropShadow dx="0" dy="${depth * 0.6}" stdDeviation="${size * 0.06}" flood-color="#0c1240" flood-opacity="0.45"/>
        </filter>
      </defs>
      <g filter="url(#${shadowId})">${line(outline, depth)}</g>
      ${line(outline)}
      ${line(`fill="url(#${fill.id})"`)}
      ${line(`fill="url(#${gloss.id})" opacity="${opts.gloss ?? 0.35}"`)}`;
    return svgElement(width, height, inner);
  }

  // Candy ribbon: a pill with a gradient face, a darker lip, a shine, an Ink outline and white text with a
  // dark stroke. opts: size (font px), colors (FILLS key), padX, font, textFill, lip
  function ribbon(text, opts = {}) {
    const font = opts.font || "Luckiest Guy";
    const size = opts.size || 64;
    const spacing = opts.spacing ?? size * 0.04;
    const box = measure(text, font, size, spacing);
    const padX = opts.padX ?? size * 0.75;
    const bodyHeight = opts.height ?? size * 1.5;
    const lip = opts.lip ?? size * 0.13;
    const outline = opts.outline ?? Math.max(5, size * 0.1);
    const width = Math.ceil(box.width + padX * 2);
    const radius = bodyHeight / 2;
    const stops = typeof opts.colors === "string" ? FILLS[opts.colors] : (opts.colors || FILLS.sky);
    const face = gradient(stops);
    const lipColor = opts.lipColor || stops[stops.length - 1][1];
    const textStroke = opts.textStroke || INK;
    const m = outline;
    const totalW = width + m * 2;
    const totalH = Math.ceil(bodyHeight + lip + m * 2 + size * 0.15);
    const baseline = m + bodyHeight / 2 - box.y - box.height / 2 - size * 0.02;
    const inner = `
      <defs>${face.def}</defs>
      <rect x="${m}" y="${m + lip + size * 0.1}" width="${width}" height="${bodyHeight}" rx="${radius}" fill="#0c1240" opacity="0.3"/>
      <rect x="${m}" y="${m + lip}" width="${width}" height="${bodyHeight}" rx="${radius}" fill="${lipColor}" stroke="${INK}" stroke-width="${outline}"/>
      <rect x="${m}" y="${m}" width="${width}" height="${bodyHeight}" rx="${radius}" fill="url(#${face.id})" stroke="${INK}" stroke-width="${outline}"/>
      <rect x="${m + radius * 0.55}" y="${m + bodyHeight * 0.1}" width="${width - radius * 1.1}" height="${bodyHeight * 0.3}" rx="${bodyHeight * 0.15}" fill="#ffffff" opacity="0.35"/>
      <text x="${m + width / 2}" y="${baseline}" text-anchor="middle" font-family="${font}" font-size="${size}" letter-spacing="${spacing}"
        fill="${opts.textFill || "#ffffff"}" stroke="${textStroke}" stroke-width="${size * 0.16}" stroke-linejoin="round" paint-order="stroke">${text}</text>`;
    return svgElement(totalW, totalH, inner);
  }

  // Chunky lightning bolt (Bolt gradient, Ink outline, white highlight), about `height` px tall
  function bolt(height = 300, opts = {}) {
    const scale = height / 100;
    const outline = opts.outline ?? 5;
    const face = gradient(opts.colors || [[0, "#fff6a0"], [0.5, "#ffe15a"], [1, "#ffa21f"]]);
    const shape = "M 34 0 L 70 0 L 52 36 L 76 36 L 22 100 L 36 52 L 12 52 Z";
    const width = 76 * scale + outline * 2 * scale + 4;
    const totalH = height + outline * 2 * scale + 4;
    const inner = `
      <defs>${face.def}</defs>
      <g transform="translate(${outline * scale + 2} ${outline * scale + 2}) scale(${scale})">
        <path d="${shape}" fill="#0c1240" opacity="0.25" transform="translate(3 5)"/>
        <path d="${shape}" fill="url(#${face.id})" stroke="${INK}" stroke-width="${outline}" stroke-linejoin="round"/>
        <path d="M 38 5 L 60 5 L 46 30" fill="none" stroke="#ffffff" stroke-width="4" stroke-linecap="round" stroke-linejoin="round" opacity="0.8"/>
      </g>`;
    const svg = svgElement(width, totalH, inner);
    if (opts.glow) {
      svg.style.filter = `drop-shadow(0 0 ${height * 0.08}px ${opts.glow}) drop-shadow(0 0 ${height * 0.2}px ${opts.glow})`;
    }
    return svg;
  }

  // Four-point sparkle star, `size` px across
  function sparkle(size = 60, color = "#ffffff", opts = {}) {
    const r = 50;
    const k = r * 0.18;
    const shape = `M 0 ${-r} Q ${k} ${-k} ${r} 0 Q ${k} ${k} 0 ${r} Q ${-k} ${k} ${-r} 0 Q ${-k} ${-k} 0 ${-r} Z`;
    const inner = `<g transform="translate(${size / 2} ${size / 2}) scale(${size / 100})"><path d="${shape}" fill="${color}"/></g>`;
    const svg = svgElement(size, size, inner);
    svg.style.filter = `drop-shadow(0 0 ${size * 0.15}px ${opts.glow || "rgba(255,255,255,0.9)"})`;
    return svg;
  }

  // A bank of cartoon clouds: puffs [[x, y, r], ...] (y measured from the top of a width x height box) on a
  // solid base that runs from the puffs' feet to the bottom. Ink outline, a vertical gradient and a white
  // shine on every puff. opts: top / bottom colours, outline width, base (y where the solid base starts; keep it
  // above where neighbouring puffs cross, or the gap between them and the base becomes an Ink-filled hole)
  function cloudBank(width, height, puffs, opts = {}) {
    const outline = opts.outline ?? 9;
    const base = opts.base ?? Math.max(...puffs.map(([, y]) => y));
    const top = Math.min(...puffs.map(([, y, r]) => y - r));
    const face = uid("cloud");
    const shape = (grow) => puffs.map(([x, y, r]) => `<circle cx="${x}" cy="${y}" r="${r + grow}"/>`).join("") +
      `<rect x="${-outline}" y="${base - grow}" width="${width + outline * 2}" height="${height - base + outline + grow}"/>`;
    const shines = puffs.map(([x, y, r]) =>
      `<ellipse cx="${x - r * 0.3}" cy="${y - r * 0.45}" rx="${r * 0.32}" ry="${r * 0.16}" transform="rotate(-25 ${x - r * 0.3} ${y - r * 0.45})"/>`).join("");
    const inner = `
      <defs>
        <linearGradient id="${face}" gradientUnits="userSpaceOnUse" x1="0" y1="${top}" x2="0" y2="${height}">
          <stop offset="0" stop-color="${opts.top || "#ffffff"}"/>
          <stop offset="1" stop-color="${opts.bottom || "#cfe2ff"}"/>
        </linearGradient>
      </defs>
      <g fill="${INK}">${shape(outline)}</g>
      <g fill="url(#${face})">${shape(0)}</g>
      <g fill="#ffffff" opacity="0.85">${shines}</g>`;
    return svgElement(width, height, inner);
  }

  // Puts an element on the stage. at: [x, y]; anchor: [ax, ay] as fractions of the element's own size
  // (default centred); rotate (deg), scale, z, opacity
  function place(stage, element, at, opts = {}) {
    const [ax, ay] = opts.anchor || [0.5, 0.5];
    element.classList.add("layer");
    element.style.left = `${at[0]}px`;
    element.style.top = `${at[1]}px`;
    const transforms = [`translate(${-ax * 100}%, ${-ay * 100}%)`];
    if (opts.rotate) transforms.push(`rotate(${opts.rotate}deg)`);
    if (opts.scale) transforms.push(`scale(${opts.scale})`);
    if (opts.flip) transforms.push("scaleX(-1)");
    element.style.transform = transforms.join(" ");
    element.style.transformOrigin = `${ax * 100}% ${ay * 100}%`;
    if (opts.z !== undefined) element.style.zIndex = opts.z;
    if (opts.opacity !== undefined) element.style.opacity = opts.opacity;
    stage.appendChild(element);
    return element;
  }

  // A render (pet, weather, egg) as an <img class="sprite">: `width` px wide, or `height` px tall, or `fit`:
  // as big as fits in a fit x fit box (so tall and wide pets look the same size)
  function sprite(src, opts = {}) {
    const image = document.createElement("img");
    // decode while painting: headless Chrome's screenshot must never catch a render that isn't decoded yet
    image.decoding = "sync";
    image.src = src;
    image.className = "sprite";
    if (opts.width) image.style.width = `${opts.width}px`;
    if (opts.height) image.style.height = `${opts.height}px`;
    if (opts.fit) {
      image.style.maxWidth = `${opts.fit}px`;
      image.style.maxHeight = `${opts.fit}px`;
    }
    return image;
  }

  // A Rainbow-tier pet: in the world its colours keep cycling through the rainbow (PetController), which a
  // still shows as a rainbow sheen over the render: a <canvas> with the render, a rainbow gradient blended in
  // "hue" mode (dark eyes and outlines stay dark), cut back to the render's shape. Same size opts as
  // sprite(); async because it needs the loaded render.
  async function rainbowSprite(src, opts = {}) {
    const image = await loadImage(src);
    const w = image.naturalWidth;
    const h = image.naturalHeight;
    let scale = 1;
    if (opts.width) scale = opts.width / w;
    else if (opts.height) scale = opts.height / h;
    else if (opts.fit) scale = Math.min(opts.fit / w, opts.fit / h);
    const canvas = document.createElement("canvas");
    canvas.width = w;
    canvas.height = h;
    canvas.style.width = `${Math.round(w * scale)}px`;
    canvas.style.height = `${Math.round(h * scale)}px`;
    canvas.className = "sprite";
    const context = canvas.getContext("2d");
    context.drawImage(image, 0, 0);
    const sheen = context.createLinearGradient(0, 0, w, h);
    const colors = ["#ff5a6e", "#ffb347", "#ffe95a", "#6ee88a", "#54c8ff", "#a77bff", "#ff7ad9"];
    colors.forEach((color, index) => sheen.addColorStop(index / (colors.length - 1), color));
    context.globalCompositeOperation = "hue";
    context.fillStyle = sheen;
    context.fillRect(0, 0, w, h);
    context.globalCompositeOperation = "destination-in";
    context.drawImage(image, 0, 0);
    return canvas;
  }

  // Adds a coloured glow around an element (on top of its own filter), e.g. for Neon weather orbs
  function glow(element, color, radius = 30) {
    const own = element.style.filter || getComputedStyle(element).filter;
    element.style.filter = `drop-shadow(0 0 ${radius * 0.4}px ${color}) drop-shadow(0 0 ${radius}px ${color}) ${own === "none" ? "" : own}`;
    return element;
  }

  // Loads an image for drawing on a canvas. Waits for its load event rather than image.decode(): headless
  // Chrome's virtual time (render_art.py's --virtual-time-budget) waits for loads, but not for decode()'s
  // off-thread work, so a page awaiting decode() could be screenshot half built.
  function loadImage(src) {
    const image = new Image();
    return new Promise((resolve, reject) => {
      image.onload = () => resolve(image);
      image.onerror = () => reject(new Error(`can't load ${src}`));
      image.src = src;
    });
  }

  // Resolves once every <img> on the page has loaded (so the screenshot never catches a missing render)
  function imagesLoaded() {
    const pending = [...document.images].filter((image) => !image.complete);
    return Promise.all(pending.map((image) => new Promise((resolve) => {
      image.onload = image.onerror = resolve;
    })));
  }

  return { INK, FILLS, ready, title, ribbon, bolt, sparkle, cloudBank, place, sprite, rainbowSprite, glow, loadImage, imagesLoaded };
})();
