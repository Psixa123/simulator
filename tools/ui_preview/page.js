// Draws the PlayerGui dump from tools/preview_ui.py: one absolutely positioned div per drawn GuiObject,
// in Roblox paint order (ScreenGui DisplayOrder, then ZIndex / tree order; children over parents).
//
// Every geometry number comes from the Luau layout pass (mock_layout.luau), already in screen pixels:
// X/Y/W/H, an optional 2D matrix M for Rotation, an optional Clip rect (ClipsDescendants, scrolling
// frames). Text lines are already broken and sized there; this file only paints:
//   background colour x UIGradient (colour and transparency keypoints, Rotation, Offset), UICorner,
//   UIStroke on frames (outer ring, colour / transparency / gradient) and on text (outline, emoji
//   included), legacy borders, TextColor3 / TextTransparency / rich text runs, images (ScaleType,
//   ImageColor3 tint, ImageRect, 9-slice), ViewportFrames (pet / egg pictures or a cartoon stand-in),
//   scroll bars, the Roblox top bar and chat window, and the backdrop.

(async function () {
  const params = new URLSearchParams(location.search);
  const dataUrl = params.get("data");
  const page = await (await fetch(dataUrl)).json();
  const screen = page.Screen;
  const opts = page.Options || {};
  const assets = page.Assets || {};
  const petArt = page.PetArt || {};

  const root = document.getElementById("screen");
  root.style.width = screen.W + "px";
  root.style.height = screen.H + "px";
  document.body.style.width = screen.W + "px";
  document.body.style.height = screen.H + "px";

  // ------------------------------------------------------------------ backdrop
  const backdrop = document.getElementById("backdrop");
  if (opts.Background === "none") {
    backdrop.style.background = "repeating-conic-gradient(#d9dee8 0 25%, #f4f6fa 0 50%) 0 0 / 24px 24px";
  } else if (opts.Background === "sky" || !opts.BackgroundUrl) {
    backdrop.style.background = "linear-gradient(#36A6FA 0%, #7CCDFF 40%, #C8EEFF 70%, #E9F7FF 100%)";
  } else {
    backdrop.style.backgroundImage = `url("${opts.BackgroundUrl}")`;
  }

  // ------------------------------------------------------------------ fonts first (text was measured with them)
  const fontLoads = [
    '400 20px "Fredoka One"', '400 20px "Luckiest Guy"', '400 20px "Gotham Preview"', '500 20px "Gotham Preview"',
    '700 20px "Gotham Preview"', '900 20px "Gotham Preview"', '400 20px "Sans Preview"', '700 20px "Sans Preview"',
  ];
  await Promise.all(fontLoads.map((f) => document.fonts.load(f, "AaZz⚡").catch(() => null)));

  // ------------------------------------------------------------------ helpers
  const hexRgb = (hex) => [parseInt(hex.slice(0, 2), 16), parseInt(hex.slice(2, 4), 16), parseInt(hex.slice(4, 6), 16)];
  const rgba = (hex, a = 1) => {
    const [r, g, b] = hexRgb(hex);
    return `rgba(${r},${g},${b},${+a.toFixed(4)})`;
  };
  const mulHex = (a, b) => {
    const x = hexRgb(a), y = hexRgb(b);
    return x.map((v, i) => Math.round((v * y[i]) / 255).toString(16).padStart(2, "0")).join("");
  };
  const px = (v) => `${+v.toFixed(3)}px`;

  // UIGradient -> CSS linear-gradient; colour multiplies `baseHex`, alpha multiplies `baseA`
  function cssGradient(grad, baseHex, baseA) {
    const rot = grad.Rot || 0;
    const r = (rot * Math.PI) / 180;
    const shift = (grad.Offset ? grad.Offset[0] * Math.cos(r) + grad.Offset[1] * Math.sin(r) : 0);
    const stops = grad.Keys.map(([t, hex, a]) => {
      const color = rgba(mulHex(hex, baseHex), a * baseA);
      return `${color} ${((t + shift) * 100).toFixed(3)}%`;
    });
    if (stops.length === 1) stops.push(stops[0]);
    return `linear-gradient(${rot + 90}deg, ${stops.join(", ")})`;
  }

  const EMOJI_RE = /(\p{Extended_Pictographic}(?:️|‍\p{Extended_Pictographic}|[\u{1F3FB}-\u{1F3FF}])*️?|[\u{1F1E6}-\u{1F1FF}]{2})/u;
  const EMOJI_SPLIT = new RegExp(EMOJI_RE.source, "gu");

  function placeholderImage(el, label) {
    el.style.background = "repeating-linear-gradient(45deg, rgba(91,106,158,.18) 0 6px, rgba(255,255,255,.18) 6px 12px)";
    el.style.border = "1px dashed rgba(35,48,102,.5)";
    if (label) el.title = label;
  }

  // ------------------------------------------------------------------ one GuiObject
  const ui = document.getElementById("ui");
  const pending = [];

  function draw(item) {
    let host = ui;
    let transform = `translate(${px(item.X)}, ${px(item.Y)})`;
    if (item.M) {
      const m = item.M;
      transform = `matrix(${m.map((v) => +v.toFixed(6)).join(",")}) ` + transform;
    }
    if (item.Clip) {
      const [x0, y0, x1, y1] = item.Clip;
      if (x1 <= x0 || y1 <= y0) return;
      const clip = document.createElement("div");
      clip.className = "clip";
      clip.style.left = px(x0);
      clip.style.top = px(y0);
      clip.style.width = px(x1 - x0);
      clip.style.height = px(y1 - y0);
      ui.appendChild(clip);
      host = clip;
      transform = `translate(${px(-x0)}, ${px(-y0)}) ` + transform;
    }
    const el = document.createElement("div");
    el.className = "gui";
    el.dataset.path = item.Path;
    el.style.width = px(item.W);
    el.style.height = px(item.H);
    el.style.transform = transform;
    const radius = item.R || 0;
    host.appendChild(el);

    // background (+ UIGradient)
    if (item.Bg && item.BgA > 0) {
      const fill = document.createElement("div");
      fill.className = "fill";
      fill.style.inset = "0";
      fill.style.borderRadius = px(radius);
      fill.style.background = item.Grad ? cssGradient(item.Grad, item.Bg, item.BgA) : rgba(item.Bg, item.BgA);
      el.appendChild(fill);
    }

    // legacy border
    if (item.Border) {
      const b = item.Border;
      const ring = document.createElement("div");
      ring.className = "ring";
      const out = b.Mode === "Outline" ? b.T : b.Mode === "Middle" ? b.T / 2 : 0;
      ring.style.left = ring.style.top = px(-out);
      ring.style.width = px(item.W + 2 * out);
      ring.style.height = px(item.H + 2 * out);
      ring.style.border = `${px(b.T)} solid ${rgba(b.Color, b.A)}`;
      el.appendChild(ring);
    }

    // image
    if (item.Image) drawImage(el, item, radius);
    if (item.View) drawViewport(el, item);

    // UIStroke on the border: a ring outside the box (Outer), centred on its edge or inside it
    if (item.Stroke) {
      const s = item.Stroke;
      const out = s.Pos === "Inner" ? 0 : s.Pos === "Center" ? s.T / 2 : s.T;
      const ring = document.createElement("div");
      ring.className = "ring";
      ring.style.left = ring.style.top = px(-out);
      ring.style.width = px(item.W + 2 * out);
      ring.style.height = px(item.H + 2 * out);
      const outerRadius = radius > 0 ? radius + out : s.Join === "Round" ? out : 0;
      ring.style.borderRadius = px(outerRadius);
      if (s.Grad) {
        ring.style.border = `${px(s.T)} solid transparent`;
        ring.style.background = `${cssGradient(s.Grad, s.Color, s.A)} border-box`;
        ring.style.webkitMask = "linear-gradient(#000 0 0) padding-box exclude, linear-gradient(#000 0 0) border-box";
        ring.style.webkitMaskComposite = "xor";
        ring.style.maskComposite = "exclude";
      } else {
        ring.style.border = `${px(s.T)} solid ${rgba(s.Color, s.A)}`;
      }
      el.appendChild(ring);
    }

    if (item.Text) drawText(el, item);

    if (item.Bars) {
      for (const [bx, by, bw, bh] of item.Bars) {
        const bar = document.createElement("div");
        bar.className = "bar";
        bar.style.left = px(bx);
        bar.style.top = px(by);
        bar.style.width = px(bw);
        bar.style.height = px(bh);
        bar.style.borderRadius = px(Math.min(bw, bh) / 2);
        bar.style.background = rgba(item.BarColor, item.BarA);
        el.appendChild(bar);
      }
    }
    if (item.Video) {
      el.style.background = "#111";
    }
    if (opts.Outline) {
      const box = document.createElement("div");
      box.className = "dbg";
      box.style.inset = "0";
      const tag = document.createElement("span");
      tag.textContent = item.Name;
      box.appendChild(tag);
      el.appendChild(box);
    }
  }

  // ------------------------------------------------------------------ text
  function runSpans(container, text, strokeFilter) {
    // emoji get their own span so the outline can follow their shape (Roblox strokes emoji too)
    if (!strokeFilter || !EMOJI_RE.test(text)) {
      container.appendChild(document.createTextNode(text));
      return;
    }
    for (const piece of text.split(EMOJI_SPLIT)) {
      if (!piece) continue;
      if (EMOJI_RE.test(piece) && piece.match(EMOJI_RE)[0] === piece) {
        const span = document.createElement("span");
        span.textContent = piece;
        span.style.filter = strokeFilter;
        container.appendChild(span);
      } else {
        container.appendChild(document.createTextNode(piece));
      }
    }
  }

  function emojiOutline(t, color) {
    if (t <= 0) return "";
    const steps = 8;
    const parts = [];
    for (let i = 0; i < steps; i++) {
      const a = (i / steps) * Math.PI * 2;
      parts.push(`drop-shadow(${(Math.cos(a) * t).toFixed(2)}px ${(Math.sin(a) * t).toFixed(2)}px 0 ${color})`);
    }
    return parts.join(" ");
  }

  function drawText(el, item) {
    const t = item.Text;
    const [bx, by, bw, bh] = t.Box;
    const family = (f) => `"${f}", "Sans Preview", sans-serif`;
    const fillColor = rgba(t.Color, t.A);
    const stroke = t.Stroke;
    const strokeColor = stroke ? rgba(stroke.Color, stroke.A) : null;
    const strokeWidth = stroke ? (stroke.Legacy ? 1.6 : stroke.T * 2) : 0;
    const emojiFilter = stroke && !stroke.Legacy && stroke.A > 0.05 ? emojiOutline(stroke.T * 0.9, strokeColor) : null;
    // a UIGradient tints the text as well as the background, across the whole object
    const gradient = item.Grad ? cssGradient(item.Grad, t.Color, t.A) : null;

    // mode: "both" = fill over its own outline (paint-order), "outline" = the outline only (under a
    // gradient fill), "fill" = gradient fill without outline
    function layer(mode) {
      const box = document.createElement("div");
      box.className = "txt";
      box.style.left = px(bx);
      box.style.top = px(by);
      box.style.width = px(bw);
      box.style.height = px(bh);
      box.style.justifyContent = t.Y === "Top" ? "flex-start" : t.Y === "Bottom" ? "flex-end" : "center";
      box.style.alignItems = t.X === "Left" ? "flex-start" : t.X === "Right" ? "flex-end" : "center";
      box.style.fontFamily = family(t.Font);
      box.style.fontWeight = t.Weight;
      if (t.Italic) box.style.fontStyle = "italic";
      box.style.fontSize = px(t.Size);
      if (mode === "fill") {
        box.style.backgroundImage = gradient;
        box.style.backgroundSize = `${px(item.W)} ${px(item.H)}`;
        box.style.backgroundPosition = `${px(-bx)} ${px(-by)}`;
        box.style.webkitBackgroundClip = "text";
        box.style.backgroundClip = "text";
      }
      // the block is aligned as a whole, lines keep their own alignment inside it
      const block = document.createElement("div");
      block.style.cssText = `display:flex;flex-direction:column;width:100%;flex:none;height:${px(t.H)};`;
      block.style.alignItems = t.X === "Left" ? "flex-start" : t.X === "Right" ? "flex-end" : "center";
      for (const line of t.Lines) {
        const ln = document.createElement("div");
        ln.className = "ln";
        ln.style.height = px(line.H);
        ln.style.lineHeight = px(line.H);
        ln.style.textAlign = t.X === "Left" ? "left" : t.X === "Right" ? "right" : "center";
        for (const run of line.Runs) {
          const span = document.createElement("span");
          if (run.F) span.style.fontFamily = family(run.F);
          if (run.Wt) span.style.fontWeight = run.Wt;
          if (run.It) span.style.fontStyle = "italic";
          if (run.Sz) span.style.fontSize = px(run.Sz);
          if (run.Sc) span.style.fontSize = px((run.Sz || t.Size) * 0.82);
          const runColor = run.C ? rgba(run.C, run.A ?? t.A) : run.A !== undefined ? rgba(t.Color, run.A) : null;
          if (run.U || run.St) span.style.textDecoration = [run.U ? "underline" : "", run.St ? "line-through" : ""].join(" ").trim();
          if (run.Mk && mode !== "fill") span.style.background = rgba(run.Mk.Color, run.Mk.A);
          const sk = run.Sk || null;
          const sw = sk ? sk.T * 2 : strokeWidth;
          const sc = sk ? rgba(sk.Color, sk.A) : strokeColor;
          const outlined = sw > 0 && sc && mode !== "fill";
          if (mode === "outline") {
            span.style.color = sc || "transparent";
          } else if (mode === "fill") {
            span.style.color = runColor || "transparent";
          } else {
            span.style.color = runColor || fillColor;
          }
          if (outlined) {
            span.style.webkitTextStroke = `${px(sw)} ${sc}`;
            span.style.paintOrder = "stroke fill";
          }
          runSpans(span, run.T, outlined ? (sk ? emojiOutline(sk.T * 0.9, sc) : emojiFilter) : null);
          ln.appendChild(span);
        }
        block.appendChild(ln);
      }
      box.appendChild(block);
      el.appendChild(box);
    }

    if (gradient) {
      if (stroke || t.Lines.some((line) => line.Runs.some((run) => run.Sk))) layer("outline");
      layer("fill");
    } else {
      layer("both");
    }
  }

  // ------------------------------------------------------------------ images
  function loadImage(url) {
    return new Promise((resolve) => {
      const img = new Image();
      img.onload = () => resolve(img);
      img.onerror = () => resolve(null);
      img.src = url;
    });
  }

  function drawImage(el, item, radius) {
    const im = item.Image;
    const url = assets[im.Src];
    const layer = document.createElement("div");
    layer.className = "imgl";
    layer.style.inset = "0";
    layer.style.borderRadius = px(radius);
    layer.style.opacity = im.A;
    el.appendChild(layer);
    if (!url) {
      placeholderImage(layer, im.Src);
      return;
    }
    const tinted = im.Color.toUpperCase() !== "FFFFFF";
    const apply = (target, natural) => {
      target.style.backgroundImage = `url("${url}")`;
      target.style.backgroundRepeat = "no-repeat";
      if (im.Rect && natural) {
        const [ox, oy, sw, sh] = im.Rect;
        const kx = item.W / sw, ky = item.H / sh;
        target.style.backgroundSize = `${px(natural.width * kx)} ${px(natural.height * ky)}`;
        target.style.backgroundPosition = `${px(-ox * kx)} ${px(-oy * ky)}`;
      } else if (im.Scale === "Fit") {
        target.style.backgroundSize = "contain";
        target.style.backgroundPosition = "center";
      } else if (im.Scale === "Crop") {
        target.style.backgroundSize = "cover";
        target.style.backgroundPosition = "center";
      } else if (im.Scale === "Tile" && im.Tile) {
        const [sx, ox, sy, oy] = im.Tile;
        target.style.backgroundSize = `${px(sx * item.W + ox)} ${px(sy * item.H + oy)}`;
        target.style.backgroundRepeat = "repeat";
      } else if (im.Scale === "Slice" && im.Slice && natural) {
        const [x0, y0, x1, y1, k] = im.Slice;
        target.style.backgroundImage = "none";
        target.style.borderStyle = "solid";
        target.style.borderImageSource = `url("${url}")`;
        target.style.borderImageSlice = `${y0} ${natural.width - x1} ${natural.height - y1} ${x0} fill`;
        target.style.borderWidth = `${px(y0 * k)} ${px((natural.width - x1) * k)} ${px((natural.height - y1) * k)} ${px(x0 * k)}`;
      } else {
        target.style.backgroundSize = "100% 100%";
      }
    };
    pending.push(loadImage(url).then((natural) => {
      apply(layer, natural);
      if (item.Grad) {
        // a UIGradient tints the image too (colour multiplies, transparency fades it)
        const wash = document.createElement("div");
        wash.className = "tint";
        wash.style.inset = "0";
        wash.style.background = cssGradient(item.Grad, im.Color, 1);
        wash.style.mixBlendMode = "multiply";
        wash.style.webkitMaskImage = `url("${url}")`;
        wash.style.webkitMaskSize = layer.style.backgroundSize || "100% 100%";
        wash.style.webkitMaskPosition = layer.style.backgroundPosition || "0 0";
        wash.style.webkitMaskRepeat = "no-repeat";
        layer.style.isolation = "isolate";
        layer.appendChild(wash);
      } else if (tinted) {
        const tint = document.createElement("div");
        tint.className = "tint";
        tint.style.inset = "0";
        tint.style.background = rgba(im.Color, 1);
        tint.style.mixBlendMode = "multiply";
        tint.style.webkitMaskImage = `url("${url}")`;
        tint.style.webkitMaskSize = layer.style.backgroundSize || "100% 100%";
        tint.style.webkitMaskPosition = layer.style.backgroundPosition || "0 0";
        tint.style.webkitMaskRepeat = "no-repeat";
        layer.style.isolation = "isolate";
        layer.appendChild(tint);
      }
    }));
  }

  // ------------------------------------------------------------------ viewports (pets and eggs)
  function drawViewport(el, item) {
    const v = item.View;
    const holder = document.createElement("div");
    holder.className = "vp";
    holder.style.inset = "0";
    holder.style.opacity = v.A ?? 1;
    el.appendChild(holder);
    if (v.Kind === "Pet") {
      const art = petArt[`${v.Pet}:${v.Tier || "Normal"}`] || petArt[`${v.Pet}:Normal`];
      if (art) {
        // the camera framed the model so its largest side spans 1/zoom of the view's height
        const side = Math.min(item.H / (v.Zoom || 1.15), item.W);
        const img = document.createElement("img");
        img.src = art.Url;
        img.style.cssText = `position:absolute;left:${px((item.W - side) / 2)};top:${px((item.H - side) / 2)};width:${px(side)};height:${px(side)};object-fit:contain;`;
        holder.style.overflow = "hidden";
        // the picture is the Normal tier: tint it for Golden / Rainbow, black it out for a silhouette
        if (v.Silhouette) {
          img.style.filter = "brightness(0) opacity(0.9)";
        } else if (art.Tier !== v.Tier && v.Tier === "Golden") {
          img.style.filter = "grayscale(1) brightness(1.45) sepia(1) saturate(3.6) hue-rotate(-14deg) brightness(1.04) contrast(1.06)";
        } else if (art.Tier !== v.Tier && v.Tier === "Rainbow") {
          const wash = document.createElement("div");
          wash.style.cssText = "position:absolute;inset:0;mix-blend-mode:color;opacity:.55;";
          wash.style.background = "linear-gradient(135deg,#ff5a6e,#fff05a 33%,#64c8ff 66%,#be78ff)";
          wash.style.cssText += img.style.cssText.replace("object-fit:contain;", "");
          wash.style.webkitMaskImage = `url("${art.Url}")`;
          wash.style.webkitMaskSize = "contain";
          wash.style.webkitMaskPosition = "center";
          wash.style.webkitMaskRepeat = "no-repeat";
          holder.style.isolation = "isolate";
          holder.appendChild(img);
          holder.appendChild(wash);
          pending.push(new Promise((r) => { img.onload = img.onerror = r; }));
          return;
        }
        pending.push(new Promise((r) => { img.onload = img.onerror = r; }));
        holder.appendChild(img);
      } else {
        holder.appendChild(petBlob(v, item));
      }
    } else if (v.Kind === "Egg") {
      holder.appendChild(eggShape(v, item));
    } else if (v.Kind === "Model") {
      const d = Math.min(item.W, item.H) * 0.5;
      const cube = document.createElement("div");
      cube.style.cssText = `position:absolute;left:50%;top:50%;width:${d}px;height:${d}px;transform:translate(-50%,-50%) rotate(12deg);border-radius:${d * 0.18}px;background:linear-gradient(#cfd8ec,#9aa8c8);border:2px solid #233066;`;
      holder.appendChild(cube);
    }
  }

  // Cartoon stand-in for a pet without a rendered picture: body colour, accent belly, eyes, ink outline
  function petBlob(v, item) {
    const d = Math.min(item.W, item.H) * 0.72;
    const wrap = document.createElement("div");
    wrap.style.cssText = `position:absolute;left:50%;top:52%;width:${d}px;height:${d * 0.9}px;transform:translate(-50%,-50%);`;
    const silhouette = !!v.Silhouette;
    let body = "#" + (v.Body || "dddddd");
    let accent = "#" + (v.Accent || "ffffff");
    if (silhouette) body = accent = "#14162a";
    else if (v.Tier === "Golden") { body = "#ffca3a"; accent = "#ffa023"; }
    const ink = silhouette ? "#14162a" : "#233066";
    const blob = document.createElement("div");
    blob.style.cssText = `position:absolute;inset:0;border-radius:48% 48% 44% 44% / 56% 56% 44% 44%;border:${Math.max(2, d * 0.035)}px solid ${ink};` +
      `background:radial-gradient(circle at 34% 28%, rgba(255,255,255,.75) 0 ${d * 0.07}px, transparent ${d * 0.08}px), radial-gradient(ellipse at 50% 88%, ${accent} 0 ${d * 0.22}px, transparent ${d * 0.23}px), ${body};`;
    if (v.Tier === "Rainbow" && !silhouette) {
      blob.style.background = `radial-gradient(circle at 34% 28%, rgba(255,255,255,.75) 0 ${d * 0.07}px, transparent ${d * 0.08}px), linear-gradient(135deg,#ffb3c0,#fff7b0 33%,#b8e6ff 66%,#dcc4ff)`;
    }
    wrap.appendChild(blob);
    if (!silhouette) {
      for (const side of [-1, 1]) {
        const eye = document.createElement("div");
        const ew = d * 0.11, eh = d * 0.16;
        eye.style.cssText = `position:absolute;left:${d / 2 + side * d * 0.15 - ew / 2}px;top:${d * 0.36}px;width:${ew}px;height:${eh}px;border-radius:50%;` +
          `background:radial-gradient(circle at 35% 30%, #fff 0 ${ew * 0.22}px, #1c1a26 ${ew * 0.24}px);`;
        wrap.appendChild(eye);
        const blush = document.createElement("div");
        blush.style.cssText = `position:absolute;left:${d / 2 + side * d * 0.27 - d * 0.06}px;top:${d * 0.55}px;width:${d * 0.12}px;height:${d * 0.06}px;border-radius:50%;background:rgba(255,140,170,.55);`;
        wrap.appendChild(blush);
      }
    }
    return wrap;
  }

  function eggShape(v, item) {
    const h = Math.min(item.W, item.H) * 0.78;
    const w = h * 0.78;
    const egg = document.createElement("div");
    const body = "#" + (v.Body || "eeeeee"), accent = "#" + (v.Accent || "ffffff");
    egg.style.cssText = `position:absolute;left:50%;top:50%;width:${w}px;height:${h}px;transform:translate(-50%,-50%);` +
      `border-radius:50% 50% 50% 50% / 60% 60% 40% 40%;border:${Math.max(2, h * 0.025)}px solid #233066;` +
      `background:radial-gradient(circle at 32% 26%, rgba(255,255,255,.8) 0 ${h * 0.06}px, transparent ${h * 0.07}px),` +
      `radial-gradient(circle at 66% 40%, ${accent} 0 ${h * 0.08}px, transparent ${h * 0.085}px),` +
      `radial-gradient(circle at 36% 62%, ${accent} 0 ${h * 0.1}px, transparent ${h * 0.105}px),` +
      `radial-gradient(circle at 70% 76%, ${accent} 0 ${h * 0.06}px, transparent ${h * 0.065}px), ${body};`;
    return egg;
  }

  // ------------------------------------------------------------------ paint everything
  for (const item of page.Items) {
    try {
      draw(item);
    } catch (err) {
      console.error(item.Path, err);
    }
  }

  // ------------------------------------------------------------------ Roblox core UI (drawn over the game's guis)
  const core = document.getElementById("core");
  if (opts.TopBar !== false) {
    const left = document.createElement("div");
    left.className = "core";
    left.style.left = "12px";
    left.style.top = "12px";
    left.style.height = "44px";
    left.innerHTML = `<b><svg width="22" height="22" viewBox="0 0 22 22"><rect x="3" y="4" width="16" height="3" rx="1.5" fill="#fff"/><rect x="3" y="9.5" width="16" height="3" rx="1.5" fill="#fff"/><rect x="3" y="15" width="16" height="3" rx="1.5" fill="#fff"/></svg></b>` +
      `<b><svg width="22" height="22" viewBox="0 0 22 22"><path d="M3 5 a3 3 0 0 1 3-3 h10 a3 3 0 0 1 3 3 v7 a3 3 0 0 1-3 3 h-6 l-4 4 v-4 a3 3 0 0 1-3-3z" fill="#fff"/></svg></b>`;
    core.appendChild(left);
    const right = document.createElement("div");
    right.className = "core";
    right.style.right = "12px";
    right.style.top = "12px";
    right.style.height = "44px";
    right.innerHTML = `<b><svg width="22" height="22" viewBox="0 0 22 22"><circle cx="4" cy="11" r="2.2" fill="#fff"/><circle cx="11" cy="11" r="2.2" fill="#fff"/><circle cx="18" cy="11" r="2.2" fill="#fff"/></svg></b>`;
    core.appendChild(right);
  }
  if (screen.Chat && opts.ChatWindow !== false) {
    const [cx, cy, cw, ch] = screen.Chat;
    const chat = document.createElement("div");
    chat.className = "chat";
    chat.style.left = px(cx);
    chat.style.top = px(cy);
    chat.style.width = px(cw);
    chat.style.height = px(ch);
    chat.innerHTML = `<div class="msg"><b style="color:#ffd640">[Server]</b> Welcome to Storm Catcher Simulator!</div>` +
      `<div class="msg"><b style="color:#7cd0ff">Puffball42:</b> anyone doing the mega storm?</div>` +
      `<div class="bar">To chat click here or press "/" key</div>`;
    core.appendChild(chat);
  }

  // Roblox's player list (desktop, the game has leaderstats): top right, under the top bar
  const player = page.Player;
  if (player && !screen.Touch && opts.PlayerList !== false && opts.TopBar !== false) {
    const list = document.createElement("div");
    list.className = "plist";
    const rows = [[player.Name, player.Volts, String(player.Shifts), true], ["Puffball42", "860K", "1"], ["ZapZap_77", "3.1M", "2"]];
    list.innerHTML = `<div class="ph"><span>People</span><span>Volts</span><span>Shifts</span></div>` +
      rows.map(([n, v, sh, me]) => `<div class="pr${me ? " me" : ""}"><span>${n}</span><span>${v}</span><span>${sh}</span></div>`).join("");
    list.style.top = px(screen.InsetTop + 4);
    core.appendChild(list);
  }
  // touch screens: the jump button (Roblox's TouchGui sizes and places it by the screen's short side)
  if (screen.Touch && opts.TouchControls !== false) {
    const small = Math.min(screen.W, screen.H) <= 500;
    const size = small ? 70 : 120;
    const jump = document.createElement("div");
    jump.className = "jump";
    jump.style.left = px(screen.W - (small ? 95 : 170));
    jump.style.top = px(screen.H - (small ? 90 : 210));
    jump.style.width = jump.style.height = px(size);
    jump.innerHTML = `<svg viewBox="0 0 40 40" width="${size * 0.5}" height="${size * 0.5}"><path d="M8 25 L20 13 L32 25" fill="none" stroke="rgba(255,255,255,.9)" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
    core.appendChild(jump);
  }

  await Promise.all(pending);
  document.body.dataset.ready = "1";
})();
