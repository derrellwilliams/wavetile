#!/usr/bin/env bash
# Fetches Phosphor icons (https://phosphoricons.com) into the DesignSystem asset catalog
# as 24pt template vectors. Add a name to ICONS (as shown on phosphoricons.com) and re-run.
# Use "name:weight" for a one-off weight (e.g. "heart:fill" → asset "heart-fill").
#
#   scripts/fetch-icons.sh            # bold weight (default)
#   WEIGHT=fill scripts/fetch-icons.sh
set -euo pipefail

WEIGHT="${WEIGHT:-bold}"
ICONS=(
  house stack box-arrow-down magnifying-glass user-circle
  playlist microphone-stage vinyl-record music-note guitar
  waveform warning lock-open lock copy check
  play pause skip-forward skip-back
  gear-six sign-out palette hard-drives globe x
  shuffle sort-ascending caret-right
  repeat repeat-once queue caret-down speaker-hifi dots-three list-plus arrow-bend-down-right
  check-circle cloud-slash trash download-simple
  heart heart:fill squares-four plus pencil-simple user
  microphone arrow-counter-clockwise arrow-clockwise moon list-bullets bookmark-simple bookmark-simple:fill
  rss upload-simple gauge export trend-up clock-counter-clockwise eye-slash hand-waving
)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CATALOG="$ROOT/Packages/WavetileKit/Sources/DesignSystem/Resources/Icons.xcassets"
mkdir -p "$CATALOG"
printf '{ "info" : { "author" : "xcode", "version" : 1 } }\n' > "$CATALOG/Contents.json"

for entry in "${ICONS[@]}"; do
  name="${entry%%:*}"
  weight="$WEIGHT"
  asset="$name"
  if [[ "$entry" == *:* ]]; then
    weight="${entry##*:}"
    asset="$name-$weight"
  fi
  base="https://raw.githubusercontent.com/phosphor-icons/core/main/assets/$weight"
  file="$name-$weight.svg"
  [[ "$weight" == "regular" ]] && file="$name.svg"
  set_dir="$CATALOG/$asset.imageset"
  mkdir -p "$set_dir"
  # 24pt intrinsic size (tab bars and toolbars use it as-is); keep the 256 viewBox for crisp scaling.
  curl -fsSL "$base/$file" | sed -E -e 's/<svg /<svg width="24" height="24" /' -e 's/currentColor/#000000/g' > "$set_dir/$asset.svg"
  cat > "$set_dir/Contents.json" <<JSON
{
  "images" : [ { "filename" : "$asset.svg", "idiom" : "universal" } ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "preserves-vector-representation" : true, "template-rendering-intent" : "template" }
}
JSON
  echo "✓ $asset"
done
