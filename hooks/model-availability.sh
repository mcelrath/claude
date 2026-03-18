#!/bin/bash
# SessionStart hook: check which local LLM endpoints are available
# Reads providers from models.yaml, pings each, reports status

MODELS_YAML="$HOME/Projects/ai/claude/models.yaml"
[[ -f "$MODELS_YAML" ]] || exit 0

AVAILABLE=""
UNAVAILABLE=""

# Extract local endpoints from models.yaml and ping them
while IFS= read -r line; do
    name=$(echo "$line" | cut -d'|' -f1)
    endpoint=$(echo "$line" | cut -d'|' -f2)
    if curl -s --max-time 2 "$endpoint/models" >/dev/null 2>&1; then
        model_info=$(curl -s --max-time 2 "$endpoint/models" 2>/dev/null | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    ids=[m['id'] for m in d.get('data',[])]
    if len(ids)<=5: print(', '.join(ids))
    else: print(f'{len(ids)} models (e.g. {ids[0]}, {ids[1]})')
except: print('?')
" 2>/dev/null)
        AVAILABLE="${AVAILABLE}  ${name}: ${model_info}\n"
    else
        UNAVAILABLE="${UNAVAILABLE}  ${name}\n"
    fi
done < <(python3 -c "
import yaml, sys
with open('$MODELS_YAML') as f:
    d = yaml.safe_load(f)
for name, p in d.get('providers', {}).items():
    if p.get('type') == 'local' and p.get('endpoint'):
        print(f\"{name}|{p['endpoint']}\")
" 2>/dev/null)

if [[ -n "$AVAILABLE" ]]; then
    echo "LOCAL MODELS:"
    echo -e "$AVAILABLE"
fi
