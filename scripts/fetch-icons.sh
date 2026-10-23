#!/usr/bin/env bash
# Fetches Phosphor icons (https://phosphoricons.com) into the DesignSystem asset catalog
# as 24pt template vectors. Add a name to ICONS (as shown on phosphoricons.com) and re-run.
#
#   scripts/fetch-icons.sh            # bold weight (default)
#   WEIGHT=fill scripts/fetch-icons.sh
set -euo pipefail

WEIGHT="${WEIGHT:-bold}"
ICONS=(
  house stack arrow-circle-down magnifying-glass user-circle
  playlist microphone-stage vinyl-record music-note guitar
  waveform warning lock-open lock copy check
  play pause skip-forward skip-back
  gear-six sign-out palette hard-drives globe x
)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CATALOG="$ROOT/Packages/WavetileKit/Sources/DesignSystem/Resources/Icons.xcassets"
BASE="https://raw.githubusercontent.com/phosphor-icons/core/main/assets/$WEIGHT"
mkdir -p "$CATALOG"
printf '{ "info" : { "author" : "xcode", "version" : 1 } }\n' > "$CATALOG/Contents.json"

for name in "${ICONS[@]}"; do
  file="$name-$WEIGHT.svg"
  [[ "$WEIGHT" == "regular" ]] && file="$name.svg"
  set_dir="$CATALOG/$name.imageset"
  mkdir -p "$set_dir"
  # 24pt intrinsic size (tab bars and toolbars use it as-is); keep the 256 viewBox for crisp scaling.
  curl -fsSL "$BASE/$file" | sed -E -e 's/<svg /<svg width="24" height="24" /' -e 's/currentColor/#000000/g' > "$set_dir/$name.svg"
  cat > "$set_dir/Contents.json" <<JSON
{
  "images" : [ { "filename" : "$name.svg", "idiom" : "universal" } ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "preserves-vector-representation" : true, "template-rendering-intent" : "template" }
}
JSON
  echo "✓ $name"
done
