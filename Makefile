THEME_DIR := themes/hugo-coder
THEME_MOD := github.com/W-Floyd/hugo-coder-iconify
THEME_BRANCH := main

# KaTeX assets to vendor. The version is auto-derived so the stylesheet always
# matches the engine `transform.ToMath` renders against (mismatched class names
# cause silent styling breakage). Chain: the Dockerfile pins the Hugo build
# image, and that Hugo release bakes a specific KaTeX into its bundled renderer
# (internal/warpc/js/renderkatex.bundle.js). We read both rather than trusting
# whatever `hugo` happens to be installed locally. Override to pin manually:
#   make vendor KATEX_VERSION=0.16.22
HUGO_VERSION := $(shell grep -oE 'gohugoio/hugo:v[0-9]+\.[0-9]+\.[0-9]+' Dockerfile | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)
KATEX_VERSION ?=
KATEX_CSS := assets/katex/katex.css
KATEX_FONTS := static/katex/fonts

.PHONY: bump-theme vendor

## Bump the hugo-coder theme submodule and matching Go module to the latest commit on its default branch, then commit.
bump-theme:
	git -C $(THEME_DIR) fetch origin $(THEME_BRANCH)
	git -C $(THEME_DIR) checkout origin/$(THEME_BRANCH)
	go get $(THEME_MOD)@$$(git -C $(THEME_DIR) rev-parse HEAD)
	hugo mod tidy
	git add $(THEME_DIR) go.mod go.sum
	git commit -m "build: bump hugo-coder theme to $$(git -C $(THEME_DIR) rev-parse --short HEAD)"
	@echo "Bumped theme to $$(git -C $(THEME_DIR) log -1 --oneline)"

## Self-host KaTeX (woff2-only, font-display:swap) + fonts, version matched to the Dockerfile's Hugo. Override with KATEX_VERSION=x.y.z
vendor:
	@ver="$(KATEX_VERSION)"; \
	if [ -z "$$ver" ]; then \
		hv="$(HUGO_VERSION)"; \
		[ -n "$$hv" ] || { echo "could not read Hugo version from Dockerfile"; exit 1; }; \
		ver=$$(curl -fsSL "https://raw.githubusercontent.com/gohugoio/hugo/$$hv/internal/warpc/js/renderkatex.bundle.js" \
			| grep -oE '"[0-9]+\.[0-9]+\.[0-9]+"' | tr -d '"' | head -1); \
		[ -n "$$ver" ] || { echo "could not derive KaTeX version from Hugo $$hv"; exit 1; }; \
		echo "Derived KaTeX $$ver from Hugo $$hv (Dockerfile)"; \
	fi; \
	cdn="https://cdn.jsdelivr.net/npm/katex@$$ver/dist"; \
	rm -rf $(KATEX_FONTS); \
	mkdir -p $(dir $(KATEX_CSS)) $(KATEX_FONTS); \
	curl -fsSL "$$cdn/katex.min.css" \
		| perl -0pe 's/(url\(fonts\/[^)]+\.woff2\) format\("woff2"\)),url\([^)]+\.woff\) format\("woff"\),url\([^)]+\.ttf\) format\("truetype"\)/$$1/g; s/url\(fonts\//url(\/katex\/fonts\//g; s/font-display:[a-z]+;?//g; s/\@font-face\{/\@font-face{font-display:swap;/g;' \
		> $(KATEX_CSS); \
	grep -oE 'KaTeX_[A-Za-z0-9_-]+\.woff2' $(KATEX_CSS) | sort -u | while read f; do \
		curl -fsSL "$$cdn/fonts/$$f" -o "$(KATEX_FONTS)/$$f" || exit 1; \
	done; \
	echo "Vendored KaTeX $$ver: $(KATEX_CSS) + $$(ls $(KATEX_FONTS) | wc -l | tr -d ' ') fonts"
