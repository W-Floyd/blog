// How far each look pulls from the photo toward the relit shading: 0 none, 1 full.
const RELIGHT_STRENGTH = { dark: .5, light: .6 };
// Without hover (touch screens) the light orbits the face instead of following the
// cursor: turns per second, and distance from the centre in avatar radii.
const ORBIT_HZ = 1, ORBIT_RADIUS = 1;
// Light already in the photo, divided out before relighting so a light from the other
// side isn't cancelled by it. Fitted from the photo against its normal map (face only,
// same key model as the shader): direction as the relight's L, the share of fill, and
// the mean shading over the face so brightness holds. AMOUNT 0 keeps it, 1 removes it.
const BAKED = { x: -.8, y: -.8, fill: .22, mean: .69, amount: .4 };

// Returns a toggle(event, restored) for the given .relight box. docked: the copy parked
// in the corner of other pages, whose bubbles open rightward, greet only from "page",
// and skip the side keys.
window.avatarRelight = (box, { docked = false } = {}) => {
  // Relights the avatar from the cursor using its normal map, whose ladder matches the
  // photo's, so the width the browser picked serves both. Loaded on the first tap by
  // layouts/_partials/home/avatar.html, which hands over that event.
  const NORMALS = "media/avatar-normals-";
  const img = box.querySelector("img"), cv = box.querySelector("canvas");
  let gl, uL, uAmb, uWarm, uStr, ready, live = false, on = false;

  const vs = `attribute vec2 p; varying vec2 uv;
    void main() { uv = p * vec2(.5, -.5) + .5; gl_Position = vec4(p, 0., 1.); }`;
  // Wrapped Lambert key over an ambient, blended toward the unlit photo by str so the
  // shadow side never goes dead.
  // GLSL ES wants float literals: 1 must be written 1.0.
  const f = (v) => Number(v).toFixed(4);
  const fs = `precision mediump float;
    varying vec2 uv; uniform sampler2D col, nrm; uniform vec3 L, amb, warm; uniform float str;
    float wrap(float d) { return .35 * max(d, 0.) + .65 * clamp((d + .6) / 1.6, 0., 1.); }
    void main() {
      vec4 c = texture2D(col, uv);
      vec3 t = texture2D(nrm, uv).rgb;
      // Map is black outside its own mask (z would be -1): fall back to facing the camera
      // there, which covers the matte's soft fringe.
      vec3 n = normalize(mix(vec3(0., 0., 1.), t * 2. - 1., smoothstep(.3, .6, t.b)));
      vec3 shade = amb + (1. - amb) * warm * wrap(dot(n, L));
      float baked = (${f(BAKED.fill)} + ${f(1 - BAKED.fill)} * wrap(dot(n, normalize(vec3(${f(BAKED.x)}, ${f(BAKED.y)}, 1.2))))) / ${f(BAKED.mean)};
      vec3 lin = pow(c.rgb, vec3(2.2)) / mix(1., baked, ${f(BAKED.amount)}) * mix(vec3(1.), shade, str);
      gl_FragColor = vec4(pow(clamp(lin, 0., 1.), vec3(1. / 2.2)) * c.a, c.a);
    }`;

  // Dark: a dim, cool room. Light: bright ambient, so the key models the face without
  // darkening it against a white page.
  const html = document.documentElement, darkMQ = matchMedia("(prefers-color-scheme: dark)");
  const cs = document.body.classList;
  const isDark = () => cs.contains("colorscheme-dark") || (cs.contains("colorscheme-auto") && darkMQ.matches);
  const scheme = () => {
    const [a, w, s] = isDark()
      ? [[.12, .13, .16], [1, .94, .86], RELIGHT_STRENGTH.dark]
      : [[.6, .6, .62], [1, .97, .93], RELIGHT_STRENGTH.light];
    gl.uniform3fv(uAmb, a);
    gl.uniform3fv(uWarm, w);
    gl.uniform1f(uStr, s);
    kick();
  };

  const init = () => {
    gl = cv.getContext("webgl", { premultipliedAlpha: true });
    if (!gl) return false;
    const prog = gl.createProgram();
    for (const [type, src] of [[gl.VERTEX_SHADER, vs], [gl.FRAGMENT_SHADER, fs]]) {
      const s = gl.createShader(type);
      gl.shaderSource(s, src);
      gl.compileShader(s);
      gl.attachShader(prog, s);
    }
    gl.bindAttribLocation(prog, 0, "p");
    gl.linkProgram(prog);
    if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) return false;
    gl.useProgram(prog);
    gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
    const u = (n) => gl.getUniformLocation(prog, n);
    gl.uniform1i(u("col"), 0);
    gl.uniform1i(u("nrm"), 1);
    [uL, uAmb, uWarm, uStr] = ["L", "amb", "warm", "str"].map(u);
    return true;
  };

  const load = (src) => { const i = new Image(); i.src = src; return i.decode().then(() => i); };
  const tex = [];
  const texture = (unit, image) => {
    gl.activeTexture(gl.TEXTURE0 + unit);
    gl.bindTexture(gl.TEXTURE_2D, (tex[unit] = tex[unit] || gl.createTexture()));
    gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
    // Normals are vectors, not colour: no profile conversion.
    gl.pixelStorei(gl.UNPACK_COLORSPACE_CONVERSION_WEBGL, unit ? gl.NONE : gl.BROWSER_DEFAULT_WEBGL);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, image);
    for (const [k, v] of [[gl.TEXTURE_MIN_FILTER, gl.LINEAR], [gl.TEXTURE_MAG_FILTER, gl.LINEAR],
                          [gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE], [gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE]])
      gl.texParameteri(gl.TEXTURE_2D, k, v);
  };

  // Light position: x right, y down, in avatar radii from its centre; z keeps it in front,
  // so a far cursor grazes, never backlights. Keyboard activation starts it camera-left.
  const home = [-0.9, -0.5];
  let cur = home.slice(), goal = home.slice(), raf = 0;
  const calm = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const touch = matchMedia("(hover: none)").matches;
  const draw = () => {
    cancelAnimationFrame(raf);
    raf = 0;
    const orbit = touch && !calm && on;
    if (orbit) {
      const a = performance.now() / 1000 * 2 * Math.PI * ORBIT_HZ;
      cur = goal = [ORBIT_RADIUS * Math.cos(a), ORBIT_RADIUS * Math.sin(a)];
    }
    const k = calm ? 1 : 0.15;
    cur = cur.map((v, i) => v + (goal[i] - v) * k);
    const l = [cur[0], cur[1], 1.2], m = Math.hypot(...l);
    gl.uniform3f(uL, l[0] / m, l[1] / m, l[2] / m);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    if (orbit || Math.hypot(goal[0] - cur[0], goal[1] - cur[1]) > 1e-3) raf = requestAnimationFrame(draw);
  };
  const kick = () => { if (on && live && !raf) raf = requestAnimationFrame(draw); };
  const size = () => {
    if (!live) return;
    const r = cv.getBoundingClientRect(), dpr = devicePixelRatio || 1;
    cv.width = Math.round(r.width * dpr);
    cv.height = Math.round(r.height * dpr);
    gl.viewport(0, 0, cv.width, cv.height);
    if (on) draw();
  };
  let lean = 0, pos = [0, 0];
  const aim = (e) => {
    const r = cv.getBoundingClientRect(), h = r.width / 2;
    const x = (e.clientX - r.left - h) / h, y = (e.clientY - r.top - h) / h;
    // Squash distance so the whole page steers the light without pinning it sideways.
    const d = Math.hypot(x, y), s = d > 1 ? (1 + Math.log(d)) / d : 1;
    lean = d > 1 ? x : 0;
    pos = [x, y];
    spin(x, y);
    goal = [x * s, y * s];
    shake(x, y);
    settle();
  };

  // Follows the rung the browser picks for the hidden <img>, so zoom or a DPR change
  // sharpens the relit view as it would the photo.
  let shown;
  const fetchPair = () => {
    const src = img.currentSrc || img.src;
    const nsrc = src.replace(/media\/avatar-((?:hq-)?\d+)\.avif$/, NORMALS + "$1.avif");
    if (nsrc === src) return Promise.reject();
    if (src === shown) return Promise.resolve();
    return Promise.all([load(src), load(nsrc)]).then(([c, n]) => {
      if ((img.currentSrc || img.src) !== src) return;
      shown = src;
      texture(0, c);
      texture(1, n);
      kick();
    });
  };

  const prepare = () => {
    if (ready) return ready;
    if (!init()) return (ready = Promise.reject());
    return (ready = fetchPair().then(() => {
      live = true;
      img.addEventListener("load", () => fetchPair().catch(() => {}));
      addEventListener("resize", size);
      addEventListener("pointermove", (e) => { if (on && !touch) { aim(e); hover(e); hoverEl(e); fresh = false; kick(); } });
      addEventListener("click", click);
      addEventListener("contextmenu", menu);
      addEventListener("copy", copied);
      // Opening a context menu also fires pointerleave, so leaves just after one are
      // ignored, and a real one waits in case the cursor only brushed the edge.
      let menuAt = -1e9, away = 0;
      addEventListener("contextmenu", () => { menuAt = performance.now(); }, true);
      html.addEventListener("pointerleave", () => {
        if (touch || performance.now() - menuAt < 1000) return;
        goal = home.slice();
        kick();
        away = setTimeout(() => drift("leave", "leave"), 500);
      });
      html.addEventListener("pointerenter", () => clearTimeout(away));
      // Browser zoom changes devicePixelRatio; pinch zoom changes the visual viewport's
      // scale. Compared against the level when the gesture began.
      const vv = window.visualViewport, level = () => devicePixelRatio * (vv ? vv.scale : 1);
      let zoomFrom = level(), zoomWait = 0;
      const zoomed = () => {
        clearTimeout(zoomWait);
        zoomWait = setTimeout(() => {
          const z = level(), r = z / zoomFrom;
          zoomFrom = z;
          if (Math.abs(r - 1) > .05) react(r > 1 ? "zoom:in" : "zoom:out", "zoom");
        }, 300);
      };
      addEventListener("resize", zoomed);
      vv && vv.addEventListener("resize", zoomed);
      let dark = isDark();
      const rescheme = (e) => {
        scheme();
        if (dark !== isDark()) react((dark = isDark()) ? "dark" : "light");
        else if (e && e.type === "themeChanged") {
          const mode = ["auto", "light", "dark"].find((m) => cs.contains("colorscheme-" + m));
          react("flip:" + mode, "flip");
        }
      };
      document.addEventListener("themeChanged", rescheme);
      darkMQ.addEventListener("change", rescheme);
      scheme();
    }));
  };

  // Speech bubbles while lit, from the JSON at data-lines: line arrays keyed by what
  // prompts them (a bare array is idle lines). The first key with lines wins.
  //   idle            on a timer, between other lines
  //   on              first line after switching on; falls back to idle
  //   back            first line when a reload restores the mode; falls back to idle
  //   page            first line on other pages, where the avatar is docked; none if empty
  //   left/right/above/below/front
  //                   light settled on that side of the face, as the viewer sees it
  //   hover:<region>  cursor over a region of the photo, from "regions"
  //   link:<path>, link
  //                   a link to another page of this site clicked. The avatar follows,
  //                   so the line greets the next page. link:/posts/ is that page only,
  //                   link:/posts/* anything under it. Other sites, feeds and mail get none
  //   rss             feed menu opened
  //   click           a stray click on nothing interactive; backs off like drift
  //   menu:<href>, menu:<host>, menu
  //                   context menu opened on a link, the closest the page gets to the
  //                   browser's own Copy Link, which fires nothing
  //   over:<element>  cursor over a page element, from "elements"
  //   over:<href>, over:<host>, over:rss, over
  //                   cursor over any other link
  //   copy:link, copy text copied; copy:link if the selection is or holds a link or URL
  //   shake           cursor waggled side to side
  //   spin            cursor circled the avatar within a second
  //   leave           cursor left the page
  //   zoom:in, zoom:out, zoom
  //                   page zoomed (browser zoom or pinch), once the gesture settles
  //   dark/light      colour scheme switched
  //   flip:<mode>, flip
  //                   theme toggled to auto/light/dark with no visible change
  // Any key with a :dark or :light suffix is tried first in that colour scheme.
  // "regions" maps names to [x0, y0, x1, y1] as fractions of the photo, "elements" names to
  // CSS selectors; first match wins in both.
  // A line is a string, or {"text", "hold", "show"}: seconds nothing else may replace it,
  // and seconds on screen (default 4 plus 0.07 a character).
  // Each key is shuffled without replacement, so no line repeats until its key runs dry.
  let pool, bags = {}, bubble, timer = 0, prompt, holdUntil = 0;
  let regions = [], elements = [];
  const first = (keys) => {
    const m = isDark() ? ":dark" : ":light";
    return pool && keys.flatMap((k) => [k + m, k]).find((k) => pool[k] && pool[k].length);
  };
  const pick = (...keys) => {
    const k = first(keys);
    if (!k) return;
    if (!bags[k] || !bags[k].length) bags[k] = pool[k].slice().sort(() => Math.random() - .5);
    return bags[k].pop();
  };
  const show = (line) => {
    const text = line.text;
    if (!bubble) {
      bubble = document.createElement("span");
      bubble.className = "bubble";
      bubble.setAttribute("aria-hidden", "true");
      box.append(bubble);
    }
    clearTimeout(timer);
    prompt = null;
    // Re-pop when one line cuts off another.
    bubble.classList.remove("show");
    void bubble.offsetWidth;
    bubble.textContent = text;
    // On the cursor's side, top right when over the avatar or there's no cursor; picked
    // per line so a showing bubble never jumps.
    bubble.classList.toggle("flip", !docked && lean < 0);
    bubble.classList.add("show");
    const t = line.show > 0 ? line.show * 1000 : 4000 + 70 * text.length;
    holdUntil = performance.now() + (line.hold > 0 ? line.hold * 1000 : 0);
    timer = setTimeout(() => {
      bubble.classList.remove("show");
      timer = setTimeout(idle, 4000 + Math.random() * 5000);
    }, t);
    return t;
  };
  const idle = () => { const l = on && pick("idle"); if (l) show(l); };
  // Reactions replace whatever is showing.
  const react = (...keys) => {
    const l = on && timer && performance.now() >= holdUntil && pick(...keys);
    return l && show(l);
  };
  // Passive reactions (cursor drift rather than a deliberate click) rest their group for
  // 8s, and the key said backs off from 20s, doubling every time.
  const rest = {}, said = {};
  const drift = (group, ...keys) => {
    const t = performance.now(), key = first(keys);
    group = group || key;
    if (!key || t < (rest[group] || 0) || t < (rest[key] || 0) || !react(key)) return;
    rest[group] = Math.max(rest[group] || 0, t + 8000);
    said[key] = (said[key] || 0) + 1;
    rest[key] = t + 20000 * 2 ** (said[key] - 1);
    return true;
  };
  let linesP;
  const chat = (greet) => {
    // An empty greeting still starts the idle round.
    linesP = linesP || fetch(box.dataset.lines).then((r) => r.json()).then((j) => {
      const o = Array.isArray(j) ? { idle: j } : j && typeof j === "object" ? j : {};
      regions = Object.entries(o.regions || {}).filter(([, r]) => Array.isArray(r) && r.length === 4);
      elements = Object.entries(o.elements || {}).filter(([, q]) => {
        try { return typeof q === "string" && (document.querySelector(q), true); } catch { return false; }
      });
      delete o.regions;
      delete o.elements;
      for (const k in o) o[k] = Array.isArray(o[k]) ? o[k]
        .map((l) => (typeof l === "string" ? { text: l } : l))
        .filter((l) => l && typeof l.text === "string" && l.text) : [];
      return o;
    }, () => ({}));
    linesP.then((o) => {
      pool = o;
      if (on && !timer) timer = setTimeout(() => {
        const l = handedOver() || pick(...greet);
        if (l) show(l);
        else timer = setTimeout(idle, 4000 + Math.random() * 5000);
      }, 500);
    });
  };
  const hush = () => {
    clearTimeout(timer);
    timer = 0;
    holdUntil = 0;
    bubble && bubble.classList.remove("show");
  };

  // Where the cursor is when the mode starts is taken as given: only the greeting speaks
  // until the first move after switching on has been recorded.
  let fresh = true;
  // Which side the light has settled on, once it stays there a moment. A photo region or
  // page element under the cursor outranks it.
  let side, dwell = 0;
  // Sides need the cursor 2 radii out; between that and the face counts as neither.
  const settle = () => {
    // Docked in a corner, every cursor is up and to the left: sides mean nothing.
    if (docked) return;
    const [x, y] = pos, d = Math.hypot(x, y), s = d < .35 ? "front" : d < 2 ? undefined
      : Math.abs(x) > Math.abs(y) ? (x < 0 ? "left" : "right") : (y < 0 ? "above" : "below");
    if (s === side) return;
    side = s;
    clearTimeout(dwell);
    if (s && !fresh) dwell = setTimeout(() => region || element || drift("side", s), 300);
  };
  // A spin is a full turn around the centre one way within a second, outside the middle
  // of the face. Small backward wobbles subtract; a real reversal or a pause starts over.
  let ang = null, turn = 0, trail = [];
  const spin = (x, y) => {
    const now = performance.now(), far = Math.hypot(x, y) > .6;
    if (!far || (trail.length && now - trail[trail.length - 1][0] > 300)) { ang = null; turn = 0; trail = []; }
    if (!far) return;
    const a = Math.atan2(y, x);
    if (ang !== null) {
      let d = a - ang;
      d -= 2 * Math.PI * Math.round(d / (2 * Math.PI));
      if (turn && Math.sign(d) !== Math.sign(turn) && Math.abs(d) > .3) { turn = 0; trail = []; }
      turn += d;
    }
    ang = a;
    trail.push([now, turn]);
    while (now - trail[0][0] > 1000) trail.shift();
    if (Math.abs(turn - trail[0][1]) >= 2 * Math.PI) { turn = 0; trail = []; drift("spin", "spin"); }
  };
  // A shake is four horizontal reversals of at least half a radius within a second, with
  // under half as much vertical span, which rules out circling (two reversals a turn).
  let sx = 0, dir = 0, flips = [], path = [];
  const shake = (x, y) => {
    const now = performance.now();
    path.push([now, x, y]);
    while (now - path[0][0] > 1000) path.shift();
    if (dir >= 0 && x < sx - .5) { if (dir) flips.push(now); dir = -1; sx = x; }
    else if (dir <= 0 && x > sx + .5) { if (dir) flips.push(now); dir = 1; sx = x; }
    else if (dir * (x - sx) > 0) sx = x;
    flips = flips.filter((t) => now - t < 1000);
    if (flips.length < 4) return;
    const span = (i) => Math.max(...path.map((p) => p[i])) - Math.min(...path.map((p) => p[i]));
    if (span(2) < span(1) / 2) { flips = []; drift("shake", "shake"); }
  };

  // Region of the photo under the cursor, once it rests there a moment.
  let region, linger = 0;
  const hover = (e) => {
    const r = cv.getBoundingClientRect();
    const x = (e.clientX - r.left) / r.width, y = (e.clientY - r.top) / r.height;
    const hit = regions.find(([, [x0, y0, x1, y1]]) => x >= x0 && x <= x1 && y >= y0 && y <= y1);
    const n = hit && hit[0];
    if (n === region) return;
    region = n;
    clearTimeout(linger);
    if (n && !fresh) linger = setTimeout(() => drift("hover:" + n, "hover:" + n), 250);
  };
  // Keys for hovering or right-clicking a link, most specific first.
  const linkKeys = (pre, a) => {
    const url = new URL(a.href, location.href);
    return [pre + a.getAttribute("href"), pre + (url.protocol === "mailto:" ? "mailto" : url.hostname),
      ...(a.type === "application/rss+xml" ? [pre + "rss"] : []), pre.slice(0, -1)];
  };
  // A line picked for the page a local link leads to, handed over in sessionStorage and
  // shown there as the greeting. Clicks are never held up for it.
  const HANDOFF = "avatarline";
  const handOff = (e, a) => {
    const url = new URL(a.href, location.href);
    if (url.origin !== location.origin || a.type === "application/rss+xml" || a.hasAttribute("download") ||
        url.pathname === location.pathname || e.button || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey ||
        (a.target && a.target !== "_self") || /\.(?!html?$)[^/.]+$/.test(url.pathname)) return;
    const parts = url.pathname.split("/").filter(Boolean);
    const under = parts.slice(0, -1).map((_, i) => "link:/" + parts.slice(0, parts.length - 1 - i).join("/") + "/*");
    const l = pick("link:" + (parts.length ? "/" + parts.join("/") + "/" : "/"), ...under, "link");
    try { if (l) sessionStorage.setItem(HANDOFF, JSON.stringify({ l, at: Date.now() })); } catch {}
  };
  const handedOver = () => {
    try {
      const h = JSON.parse(sessionStorage.getItem(HANDOFF));
      sessionStorage.removeItem(HANDOFF);
      // Stale if the next page took too long, or the visitor came back some other way.
      return h && Date.now() - h.at < 10000 && h.l;
    } catch {}
  };
  // Page element or link under the cursor, likewise.
  let element, loiter = 0;
  const hoverEl = (e) => {
    const t = e.target;
    if (!t.closest || box.contains(t)) return;
    const hit = elements.find(([, q]) => t.closest(q)), a = !hit && t.closest("a[href]");
    const id = hit ? hit[0] : a;
    if (id === element) return;
    element = id;
    clearTimeout(loiter);
    // Remembered so clicking what the line is about dismisses it.
    const el = hit ? t.closest(hit[1]) : a;
    if (el && !fresh) loiter = setTimeout(() => {
      if (drift(null, ...(hit ? ["over:" + hit[0]] : linkKeys("over:", a)))) prompt = el;
    }, 250);
  };
  const click = (e) => {
    if (!on || !timer || box.contains(e.target)) return;
    if (prompt && prompt.contains(e.target)) {
      prompt = null;
      clearTimeout(timer);
      bubble.classList.remove("show");
      timer = setTimeout(idle, 4000 + Math.random() * 5000);
    }
    const a = e.target.closest && e.target.closest("a[href]");
    if (!a) {
      // Fires before the toggle, so a closed <details> is opening.
      const feed = e.target.closest && e.target.closest(".feed-menu > summary");
      if (feed && !feed.parentNode.open) return react("rss");
      // Only stray clicks, and spaced out like drift.
      if (!e.target.closest("button, summary, label, input, select, textarea, [role=button], [tabindex]"))
        drift(null, "click");
      return;
    }
    handOff(e, a);
  };

  const menu = (e) => {
    const a = e.target.closest && e.target.closest("a[href]");
    if (a && !box.contains(a)) react(...linkKeys("menu:", a));
  };
  const copied = () => {
    const sel = getSelection(), text = String(sel).trim();
    const link = /^(https?:\/\/|mailto:|www\.)\S+$/.test(text) || (sel.rangeCount &&
      [sel.anchorNode, sel.focusNode].some((n) => n && (n.nodeType === 1 ? n : n.parentElement)?.closest("a[href]")) ||
      sel.getRangeAt(0).cloneContents().querySelector("a[href]"));
    react(...(link ? ["copy:link"] : []), "copy");
  };

  // Persisted so a reload keeps the mode; layouts/_partials/home/avatar.html restores it.
  const keep = (v) => { try { v ? localStorage.setItem("avatarrelight", "on") : localStorage.removeItem("avatarrelight"); } catch {} };
  const toggle = (e, restored) => {
    on = !on;
    keep(on);
    box.setAttribute("aria-pressed", on);
    // Photo shows again at once; the canvas fades out over it.
    if (!on) { box.classList.remove("lit", "solid"); hush(); return; }
    fresh = true;
    side = region = element = undefined;
    [dwell, linger, loiter].forEach(clearTimeout);
    if (!touch && e && e.clientX !== undefined && e.detail) { aim(e); cur = goal.slice(); }
    else cur = goal = home.slice();
    prepare().then(() => {
      if (!on) return;
      size();
      box.classList.add("lit");
      chat(docked ? ["page"] : restored ? ["back", "idle"] : ["on", "idle"]);
      // Hide the photo only once the canvas has faded in over it, or the fade shows a gap.
      setTimeout(() => on && box.classList.add("solid"), 450);
    }, () => { on = false; keep(false); box.setAttribute("aria-pressed", false); });
  };
  return toggle;
};
