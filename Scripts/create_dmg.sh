#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage:
  Scripts/create_dmg.sh --app-path <path/to/App.app> [options]

Options:
  --app-path <path>         Path to the built .app bundle (required)
  --output <path>           Output DMG path (default: PodcastTransfer.dmg)
  --background <path>       Background image path (default: docs/marketing/dmg.png)
  --volname <name>          DMG volume name (default: Podcast Transfer)
  --window-size <w> <h>     DMG window size in pixels (default: 660 440)
  --app-icon-pos <x> <y>    App icon position (default: 140 210)
	--apps-icon-pos <x> <y>   Applications drop-link position (default: 520 210)
EOF
}

app_path=""
output_path="PodcastTransfer.dmg"
background_path="docs/marketing/dmg.png"
volname="Podcast Transfer"
window_w="660"
window_h="440"
app_x="140"
app_y="210"
apps_x="520"
apps_y="210"

while [[ $# -gt 0 ]]; do
	case "$1" in
		--app-path)
			app_path="${2:-}"
			shift 2
			;;
		--output)
			output_path="${2:-}"
			shift 2
			;;
		--background)
			background_path="${2:-}"
			shift 2
			;;
		--volname)
			volname="${2:-}"
			shift 2
			;;
		--window-size)
			window_w="${2:-}"
			window_h="${3:-}"
			shift 3
			;;
		--app-icon-pos)
			app_x="${2:-}"
			app_y="${3:-}"
			shift 3
			;;
		--apps-icon-pos)
			apps_x="${2:-}"
			apps_y="${3:-}"
			shift 3
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			echo "Unknown argument: $1" >&2
			usage >&2
			exit 2
			;;
	esac
done

if [[ -z "$app_path" ]]; then
	echo "--app-path is required" >&2
	usage >&2
	exit 2
fi

if [[ ! -d "$app_path" ]]; then
	echo "App bundle not found at: $app_path" >&2
	exit 1
fi

if ! command -v create-dmg >/dev/null 2>&1; then
	echo "create-dmg is required. Install with: brew install create-dmg" >&2
	exit 1
fi

if ! command -v sips >/dev/null 2>&1; then
	echo "sips is required (it should be available on macOS)." >&2
	exit 1
fi

if [[ ! -f "$background_path" ]]; then
	echo "DMG background not found at: $background_path" >&2
	exit 1
fi

bg_width=$(sips -g pixelWidth "$background_path" | awk -F': ' '/pixelWidth/ { print $2 }')
bg_height=$(sips -g pixelHeight "$background_path" | awk -F': ' '/pixelHeight/ { print $2 }')

if [[ "$bg_width" != "$window_w" || "$bg_height" != "$window_h" ]]; then
	echo "DMG background must be ${window_w}x${window_h} to match --window-size; got ${bg_width}x${bg_height}." >&2
	exit 1
fi

stage_dir=$(mktemp -d)
cleanup() { rm -rf "$stage_dir"; }
trap cleanup EXIT

app_basename=$(basename "$app_path")
ditto "$app_path" "$stage_dir/$app_basename"

rm -f "$output_path"
create-dmg \
	--volname "$volname" \
	--background "$background_path" \
	--window-pos 200 120 \
	--window-size "$window_w" "$window_h" \
	--icon-size 128 \
	--icon "$app_basename" "$app_x" "$app_y" \
	--app-drop-link "$apps_x" "$apps_y" \
	"$output_path" \
	"$stage_dir"

echo "Created $output_path"
