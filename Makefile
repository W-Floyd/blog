THEME_MOD := github.com/W-Floyd/hugo-coder-iconify
THEME_BRANCH := main

.PHONY: bump-theme

## Bump the hugo-coder theme module to the latest commit on its default branch, then commit.
bump-theme:
	go get $(THEME_MOD)@$(THEME_BRANCH)
	hugo mod tidy
	@ver=$$(grep -oE '$(THEME_MOD) v[^ ]+' go.mod | head -1 | awk '{print $$2}'); \
	git commit --only go.mod go.sum -m "build: bump hugo-coder theme to $$ver"; \
	echo "Bumped theme to $$ver"
