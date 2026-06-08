#!/usr/bin/env bash
# SessionStart pre-warm for rust-analyzer (the LSP plugin).
#
# Why: rust-analyzer runs `cargo check` internally on project load to get
# build-script output + diagnostics before it builds its symbol index. On a cold
# target/ that includes running build.rs (for braidinfer, the hipcc kernel compile
# — minutes), so the first findReferences/goToDefinition can return "not indexed"
# for a long time. Warming `cargo check` in the background makes RA's internal
# check incremental, so the index is ready (or nearly so) by the time it's needed.
#
# Scope: no-op unless the project root has a Cargo.toml. Background + quiet; never
# blocks the session. A per-root lock prevents piling up redundant cargo checks.
#
# NOTE: this warms RA's PREREQUISITES only. The in-memory index is still built on
# the first LSP-tool call. The reliable-use procedure (warm-probe + retry + exact
# line/col) in ~/.claude/CLAUDE.md is the actual guarantee; this hook just shrinks
# the cold window.
set -euo pipefail

root="${CLAUDE_PROJECT_DIR:-$PWD}"
[ -f "$root/Cargo.toml" ] || exit 0
command -v cargo >/dev/null 2>&1 || exit 0

lock="/tmp/ra-prewarm-$(printf '%s' "$root" | md5sum | cut -c1-12).lock"
if [ -e "$lock" ] && kill -0 "$(cat "$lock" 2>/dev/null || echo 0)" 2>/dev/null; then
    exit 0  # a prewarm is already running for this root
fi

(
    echo "$$" > "$lock"
    cd "$root" && cargo check --workspace --quiet >/dev/null 2>&1 || true
    rm -f "$lock"
) >/dev/null 2>&1 &

exit 0
