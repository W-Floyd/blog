// How far each look pulls from the photo toward the relit shading: 0 none, 1 full.
const RELIGHT_STRENGTH = { dark: .7, light: .6 };

// Returns a toggle(event) for the given .relight box.
window.avatarRelight = (box) => {
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
  const fs = `precision mediump float;
    varying vec2 uv; uniform sampler2D col, nrm; uniform vec3 L, amb, warm; uniform float str;
    void main() {
      vec4 c = texture2D(col, uv);
      vec3 t = texture2D(nrm, uv).rgb;
      // Map is black outside its own mask (z would be -1): fall back to facing the camera
      // there, which covers the matte's soft fringe.
      vec3 n = normalize(mix(vec3(0., 0., 1.), t * 2. - 1., smoothstep(.3, .6, t.b)));
      float d = dot(n, L);
      float key = .35 * max(d, 0.) + .65 * clamp((d + .6) / 1.6, 0., 1.);
      vec3 shade = amb + (1. - amb) * warm * key;
      vec3 lin = pow(c.rgb, vec3(2.2)) * mix(vec3(1.), shade, str);
      gl_FragColor = vec4(pow(clamp(lin, 0., 1.), vec3(1. / 2.2)) * c.a, c.a);
    }`;

  // Dark: a dim, cool room. Light: bright ambient, so the key models the face without
  // darkening it against a white page.
  const html = document.documentElement, darkMQ = matchMedia("(prefers-color-scheme: dark)");
  const isDark = () => html.classList.contains("colorscheme-dark") ||
    (html.classList.contains("colorscheme-auto") && darkMQ.matches);
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
  const draw = () => {
    cancelAnimationFrame(raf);
    raf = 0;
    const k = calm ? 1 : 0.15;
    cur = cur.map((v, i) => v + (goal[i] - v) * k);
    const l = [cur[0], cur[1], 1.2], m = Math.hypot(...l);
    gl.uniform3f(uL, l[0] / m, l[1] / m, l[2] / m);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    if (Math.hypot(goal[0] - cur[0], goal[1] - cur[1]) > 1e-3) raf = requestAnimationFrame(draw);
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
  const aim = (e) => {
    const r = cv.getBoundingClientRect(), h = r.width / 2;
    const x = (e.clientX - r.left - h) / h, y = (e.clientY - r.top - h) / h;
    // Squash distance so the whole page steers the light without pinning it sideways.
    const d = Math.hypot(x, y), s = d > 1 ? (1 + Math.log(d)) / d : 1;
    goal = [x * s, y * s];
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
      addEventListener("pointermove", (e) => { if (on) { aim(e); kick(); } });
      html.addEventListener("pointerleave", () => { goal = home.slice(); kick(); });
      // The theme toggle swaps classes on <html>.
      new MutationObserver(scheme).observe(html, { attributes: true, attributeFilter: ["class"] });
      darkMQ.addEventListener("change", scheme);
      scheme();
    }));
  };

  const toggle = (e) => {
    on = !on;
    box.setAttribute("aria-pressed", on);
    // Photo shows again at once; the canvas fades out over it.
    if (!on) { box.classList.remove("lit", "solid"); return; }
    if (e && e.clientX !== undefined && e.detail) { aim(e); cur = goal.slice(); }
    else cur = goal = home.slice();
    prepare().then(() => {
      if (!on) return;
      size();
      box.classList.add("lit");
      // Hide the photo only once the canvas has faded in over it, or the fade shows a gap.
      setTimeout(() => on && box.classList.add("solid"), 450);
    }, () => { on = false; box.setAttribute("aria-pressed", false); });
  };
  return toggle;
};
