# Shared health gate for kb-infra servers feeding agents (cached 60s):
#   ash:8081 (embeddings), tardis:9510 (LLM). Sets ASH_STOP_LINE naming which.
# Usage: source; `if ash_down; then echo "$ASH_STOP_LINE" >&2; fi`
_KBINFRA_CACHE=/tmp/.kbinfra_health_cache_sh
ash_down() {
  local down=""
  if [ -f "$_KBINFRA_CACHE" ] && [ $(( $(date +%s) - $(stat -c %Y "$_KBINFRA_CACHE" 2>/dev/null || echo 0) )) -lt 60 ]; then
    down="$(cat "$_KBINFRA_CACHE")"
  else
    curl -s -m2 -o /dev/null -w '%{http_code}' http://ash:8081/ 2>/dev/null | grep -q 200 || down="ash:8081(embeddings) "
    curl -s -m2 -o /dev/null -w '%{http_code}' http://tardis:9510/ 2>/dev/null | grep -q 200 || down="${down}tardis:9510(LLM)"
    echo "${down:-UP}" > "$_KBINFRA_CACHE"
  fi
  [ "$down" = "UP" ] && return 1
  [ -z "$down" ] && return 1
  ASH_STOP_LINE="🛑 KB-INFRA DOWN ($down) — kb-search + surfacing + summaries are BLIND/SILENT. STOP retrieval-dependent compute/derivation; an empty kb-search now means BLIND not 'nothing found'. Tell the user 'kb-infra down — holding'; mechanical-only until recovered."
  return 0
}
