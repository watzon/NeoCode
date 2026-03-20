#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

python3 - <<'PY' "${ROOT_DIR}/NeoCode.xcodeproj/project.pbxproj"
from pathlib import Path
import re, sys
text = Path(sys.argv[1]).read_text()
match = re.search(r'MARKETING_VERSION = ([^;]+);', text)
if not match:
    raise SystemExit('Could not determine MARKETING_VERSION')
print(match.group(1).strip())
PY
