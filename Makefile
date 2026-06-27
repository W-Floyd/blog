THEME_DIR := themes/hugo-coder
THEME_MOD := github.com/W-Floyd/hugo-coder-iconify
THEME_BRANCH := main

.PHONY: bump-theme

## Bump the hugo-coder theme submodule and matching Go module to the latest commit on its default branch, then commit.
bump-theme:
	git -C $(THEME_DIR) fetch origin $(THEME_BRANCH)
	git -C $(THEME_DIR) checkout origin/$(THEME_BRANCH)
	go get $(THEME_MOD)@$$(git -C $(THEME_DIR) rev-parse HEAD)
	hugo mod tidy
	git add $(THEME_DIR) go.mod go.sum
	git commit -m "build: bump hugo-coder theme to $$(git -C $(THEME_DIR) rev-parse --short HEAD)"
	@echo "Bumped theme to $$(git -C $(THEME_DIR) log -1 --oneline)"
