#!/usr/bin/env bash
set -euo pipefail

# Generates a macOS AppIcon.appiconset from a single square source PNG.
#
# Usage (from repo root):
#   Scripts/generate_macos_appicon.sh App/Resources/AppSourceIcon.png
#
# Usage (from App/):
#   ../Scripts/generate_macos_appicon.sh Resources/AppSourceIcon.png

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <source.png>" >&2
  exit 2
fi

src="$1"
if [[ ! -f "$src" ]]; then
  echo "Source file not found: $src" >&2
  exit 2
fi

if ! command -v sips >/dev/null 2>&1; then
  echo "Missing 'sips' (should be available on macOS)." >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

appicon_dir="$repo_root/App/Resources/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$appicon_dir"

# Clean up any previous accidental duplicates like "icon_32 1.png".
rm -f "$appicon_dir"/*\ 1.png || true

# Filenames expected by App/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json
for size in 16 32 64 128 256 512 1024; do
  out="$appicon_dir/icon_${size}.png"
  rm -f "$out" || true
  # sips will preserve aspect ratio; for square input this is exact.
  sips -s format png -z "$size" "$size" "$src" --out "$out" >/dev/null
  echo "Wrote $out"
done

echo "Done. Next: regenerate the Xcode project with: (cd App && xcodegen)"
