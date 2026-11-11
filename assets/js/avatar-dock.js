{{- /* Imported by the theme's lazyScripts (config.toml) when the mode is stored as on;
  run through ExecuteAsTemplate once for the site, with the site as context. */ -}}
{{- $src := partial "avatar/sources.html" . -}}
{{- $lines := resources.Get "data/avatar-lines.json" | minify | fingerprint -}}
{{- $js := resources.Get "js/avatar-relight.js" | minify | fingerprint -}}
// The avatar parked on pages other than home while its relight mode is on, poking up
// from the bottom left. Tapping it turns the mode off; only the home avatar turns it back
// on. Other visitors fetch none of this.
(() => {
  // The home page has the full avatar.
  if (document.querySelector(".about .avatar")) return;
  const S = {{ dict "css" (partial "avatar/style.html" .) "src" $src.src "srcset" $src.srcset "hq" $src.hqSrcset "lines" $lines.RelPermalink "js" $js.RelPermalink | jsonify }};
  document.head.insertAdjacentHTML("beforeend", S.css);
  const dock = document.createElement("div");
  // Starts below the edge and rises in.
  dock.className = "avatar avatar-dock gone";
  // px in sizes: rem there is the browser's 16px, not the theme's 10px root. Keep in step
  // with the dock's width in layouts/_partials/avatar/style.html.
  dock.innerHTML = '<span class="relight" role="button" tabindex="0" aria-label="Put the avatar away">' +
    '<img alt="" sizes="min(240px, 40vw)"><canvas aria-hidden="true"></canvas></span>';
  const box = dock.firstChild, img = box.querySelector("img");
  box.dataset.lines = S.lines;
  let low = false;
  try { low = localStorage.getItem("imagequality") === "low"; } catch {}
  img.srcset = low ? S.srcset : S.hq;
  img.src = S.src;
  document.body.append(dock);
  requestAnimationFrame(() => requestAnimationFrame(() => dock.classList.remove("gone")));
  const s = document.createElement("script");
  s.src = S.js;
  s.onload = () => {
    const toggle = avatarRelight(box, { docked: true });
    toggle(null, true);
    const off = () => {
      toggle();
      dock.classList.add("gone");
      setTimeout(() => dock.remove(), 400);
    };
    box.addEventListener("click", off);
    box.addEventListener("keydown", (e) => {
      if (e.key === "Enter" || e.key === " ") { e.preventDefault(); off(); }
    });
  };
  document.head.append(s);
})();
