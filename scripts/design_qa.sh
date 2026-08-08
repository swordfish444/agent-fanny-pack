#!/bin/zsh
# Renders the popover from real SwiftUI and scores it against the approved design.
#
#   ./scripts/design_qa.sh            # score, write diff heatmap, fail under threshold
#
# The reference is docs/design-reference.png, cropped from the approved mockup to the
# popover card exactly. The candidate is produced by the app's own --render-screenshot
# path, so QA exercises shipping code rather than a parallel drawing routine.

set -euo pipefail

script_dir="${0:A:h}"
repo_dir="${script_dir:h}"
reference="$repo_dir/docs/design-reference.png"
candidate="$repo_dir/dist/design-candidate.png"
diff_out="$repo_dir/dist/design-diff.png"

test -f "$reference" || { print -u2 "missing reference: $reference"; exit 2 }

mkdir -p "$repo_dir/dist"
swift build --package-path "$repo_dir" -c release --product AgentFannyPack >/dev/null
"$repo_dir/.build/release/AgentFannyPack" --render-screenshot "$candidate" >/dev/null

"${QA_BIN:-swift $repo_dir/tools/DesignQA.swift}" compare "$reference" "$candidate" --diff "$diff_out"
