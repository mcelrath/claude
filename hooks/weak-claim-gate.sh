#!/bin/bash
# PreToolUse Edit/Write/Bash: warn on numerical-match claims without random/null control.
exec python3 -c '
import sys, json, re
try: d = json.load(sys.stdin)
except: sys.exit(0)
if d.get("tool_name") not in ("Edit","Write","Bash"): sys.exit(0)
ti = d.get("tool_input", {})
content = ti.get("new_string") or ti.get("content") or ti.get("command") or ""
if not content: sys.exit(0)
claim = re.compile(r"within\s+\d+\s*(%|percent)|matches.*zeros|correctly identifies\s+\d+\s+of\s+\d+|\d+\s*/\s*\d+\s+(match|agree|correspond)|ratio\s*=\s*[\d.]+|(consistent|agrees)\s+with\s+.{0,40}\d", re.I)
ctrl = re.compile(r"random|\bnull\b|baseline|control|p\s*[<=]\s*0\.|Z[-_]?score|vs\s+random|placebo", re.I)
lines = content.splitlines()
for i, line in enumerate(lines):
    if claim.search(line):
        window = lines[max(0,i-5):i+6]
        if not any(ctrl.search(l) for l in window):
            sys.stderr.write(f"WEAK-CLAIM WARNING (line {i+1}): {line.strip()[:120]}\n  Add control (random baseline, p-value, Z-score) within +-5 lines.\n")
            break
sys.exit(0)
'
