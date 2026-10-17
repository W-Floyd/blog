# git hooks

Version-controlled git hooks for this repo. `.git/hooks/` itself isn't tracked
by git, so these live here and are copied in by the installer.

## Install

```sh
./scripts/git-hooks/install.sh
```

Re-run after pulling changes to any hook. The installer only copies the hooks
listed here and leaves existing hooks (e.g. Git LFS's) in place.

## Hooks

### `pre-commit`

Blocks a commit if any staged image (`jpg`, `jpeg`, `png`, `webp`, `avif`,
`tif`/`tiff`) carries extra metadata profiles — `exif`, `iptc`, `xmp`, or
Photoshop `8bim` — which can leak camera details, GPS location, and timestamps.
ICC colour profiles are allowed.

Requires ImageMagick (`identify` or `magick` on `PATH`). Strip metadata with:

```sh
magick mogrify -strip path/to/image
git add path/to/image
```

Bypass for one commit with `git commit --no-verify`.
