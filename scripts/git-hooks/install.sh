#!/bin/sh
#
# Install this repo's git hooks into .git/hooks.
#
# Run from anywhere inside the repo:  ./scripts/git-hooks/install.sh
#
# Hooks live in scripts/git-hooks/ (version-controlled) and are copied into
# .git/hooks/ (which git does not track). Re-run after pulling hook updates.

set -e

# Directory this script lives in (the tracked hooks source).
src_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# Resolve the repo's actual hooks path (honours core.hooksPath if set).
hooks_dir=$(git rev-parse --git-path hooks)

mkdir -p "$hooks_dir"

for hook in "$src_dir"/*; do
	name=$(basename "$hook")
	# Only install actual hooks: skip the installer and docs.
	case "$name" in
	install.sh | *.md) continue ;;
	esac
	cp "$hook" "$hooks_dir/$name"
	chmod +x "$hooks_dir/$name"
	printf "installed %s -> %s\n" "$name" "$hooks_dir/$name"
done
