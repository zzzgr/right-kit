#!/usr/bin/env bash
# Regenerate RightKit.xcodeproj from project.yml.
#
# The project file is gitignored — project.yml is the source of truth. Run this after
# editing it, and any time Xcode starts behaving strangely.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v xcodegen >/dev/null; then
  echo "error: xcodegen not found — brew install xcodegen" >&2
  exit 1
fi

xcodegen generate

# XcodeGen emits empty package hooks even with no SPM dependencies; the Xcode GUI
# occasionally trips over them ("Missing package product").
python3 - <<'PY'
import re
from pathlib import Path

path = Path("RightKit.xcodeproj/project.pbxproj")
text = path.read_text()
for key in ("packageProductDependencies", "packageReferences"):
    text = re.sub(rf"\n\t+{key} = \(\n\t+\);\n", "\n", text)
path.write_text(text)
PY

echo "Generated RightKit.xcodeproj — open with: open RightKit.xcodeproj"
