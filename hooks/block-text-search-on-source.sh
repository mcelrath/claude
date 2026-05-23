#!/bin/bash
# PreToolUse hook for Bash. Blocks text-search tools (grep, rg, etc.) on
# source-code files. Redirects to loogle for .lean, ast-grep for general
# source code, and purpose-built tools for xml/sql/csv/log/rst/tex.
#
# NO BYPASS — per PLAN-hook-grep-replacement.md and user direction. If the
# hook fires and the agent can't accomplish its task with ast-grep/loogle/
# purpose-built tool, the agent MUST surface to the user.
#
# Detection covers:
#   grep / rg / egrep / fgrep (any flags)
#   find ... -exec grep / find ... -exec rg
#   fd ... -x grep / fd ... -x rg
#   find/fd ... | xargs grep / xargs rg
#   awk '/PAT/' (search-print form)
#   sed -n '/PAT/p' (search-print form)
#   cat <file> | grep ... (pipe form, when <file> has a blocked extension)
#
# Allowed (text-search IS the right tool):
#   .txt .ini .cfg .conf .lock
#   any file under .lake/ build/ dist/ node_modules/ target/ .venv/ .cache/

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)
[ "$TOOL_NAME" != "Bash" ] && exit 0

CMD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)

# (0) Exempt CLI tools where text-search words and file extensions appear in
# message BODIES, not as actual file-search invocations. Anchored to the
# LEADING command (before any `;`, `&&`, `||`, `|`). Same pattern as
# block-markdown-via-bash.sh.
LEADING=$(echo "$CMD" | awk -F'[;&|]' '{print $1}' | sed -E 's/^[[:space:]]*//')
if [[ "$LEADING" =~ ^(bridge|~/\.agent-bridge/bridge|/home/mcelrath/\.agent-bridge/bridge)[[:space:]]+(send|announce|recv|tail|peek|watch)([[:space:]]|$) ]] \
   || [[ "$LEADING" =~ ^(kb|~/\.local/bin/kb|/home/mcelrath/\.local/bin/kb)[[:space:]]+(add|correct|update|get|search|list|stats|reembed|delete|check|bulk-tag|bulk-consolidate|flush-pending)([[:space:]]|$) ]] \
   || [[ "$LEADING" =~ ^bd[[:space:]]+(create|update|remember|show|close|note|memories|recall|search|dep|prime|stats|doctor)([[:space:]]|$) ]] \
   || [[ "$LEADING" =~ ^(loogle|~/\.local/bin/loogle|/home/mcelrath/\.local/bin/loogle)([[:space:]]|$) ]] \
   || [[ "$LEADING" =~ ^ast-grep([[:space:]]|$) ]] \
   || [[ "$LEADING" =~ ^sg([[:space:]]|$) ]]; then
    exit 0
fi

# (1) Detect a text-search tool invocation in the command.
USES_TEXT_SEARCH=0

# grep/rg/egrep/fgrep as primary or piped command
if [[ "$CMD" =~ (^|[[:space:]]|[\;\&\|])(grep|rg|ripgrep|egrep|fgrep)([[:space:]]|$) ]]; then
    USES_TEXT_SEARCH=1
fi
# find ... -exec grep ... / find ... -exec rg ...
if [[ "$CMD" =~ -exec[[:space:]]+(grep|rg|egrep|fgrep)([[:space:]]|$) ]]; then
    USES_TEXT_SEARCH=1
fi
# pipe to xargs grep / xargs rg
if [[ "$CMD" =~ xargs([[:space:]]+-[a-zA-Z0-9-]+)*[[:space:]]+(grep|rg|egrep|fgrep)([[:space:]]|$) ]]; then
    USES_TEXT_SEARCH=1
fi
# fd ... -x grep
if [[ "$CMD" =~ (^|[[:space:]]|[\;\&\|])fd([[:space:]]+[^\;\&\|]*)?[[:space:]]+-x[[:space:]]+(grep|rg|egrep|fgrep)([[:space:]]|$) ]]; then
    USES_TEXT_SEARCH=1
fi
# awk '/PAT/' (regex search-print form)
if [[ "$CMD" =~ (^|[[:space:]]|[\;\&\|])awk([[:space:]]+-[a-zA-Z][^[:space:]]*)*[[:space:]]+\'[^\']*/[^/]+/[^\']*\' ]]; then
    USES_TEXT_SEARCH=1
fi
# sed -n '/PAT/p' (search-print form)
if [[ "$CMD" =~ (^|[[:space:]]|[\;\&\|])sed([[:space:]]+-[a-zA-Z][^[:space:]]*)*[[:space:]]+\'[^\']*/[^/]+/p\' ]]; then
    USES_TEXT_SEARCH=1
fi

[ "$USES_TEXT_SEARCH" = "0" ] && exit 0

# (2) Exempt build/cache directory targets.
# If the command exclusively targets paths under known build/cache dirs, allow.
# This is a heuristic: we check if every extension-bearing token in the command
# lives under a build/cache dir.
if [[ "$CMD" =~ (\.lake/|/build/|/dist/|/node_modules/|/target/|/\.venv/|/\.cache/|/\.git/) ]] \
   && ! [[ "$CMD" =~ \.lean([[:space:]\>\|\;\&\)\}\"]|$) ]] \
   && ! [[ "$CMD" =~ /(lib|sections|proofs|tests|scripts)/ ]]; then
    # Build/cache-dir only — allow.
    exit 0
fi

# (3) Scan the command for a blocked file extension.
# Returns the FIRST blocked extension found. Search categories in priority order:
# .lean first (most specific), then source extensions, then purpose-built-tool extensions.

# Source extensions (ast-grep BUILT-IN)
SOURCE_BUILTIN_EXTS=(c cc cpp cxx h hpp hh hxx ipp tpp cu cuh hip py pyi rs js mjs cjs jsx ts tsx go java kt kts swift scala rb sh bash zsh lua php dart ex exs hs html htm css scss json yaml yml)
# Source extensions (ast-grep via sgconfig.yml custom langs)
SOURCE_CUSTOM_EXTS=(md markdown toml)
# Purpose-built tool extensions
declare -A PURPOSE_BUILT_TOOL
PURPOSE_BUILT_TOOL[xml]="xmlstarlet"
PURPOSE_BUILT_TOOL[xsd]="xmlstarlet"
PURPOSE_BUILT_TOOL[xsl]="xmlstarlet"
PURPOSE_BUILT_TOOL[xslt]="xmlstarlet"
PURPOSE_BUILT_TOOL[plist]="xmlstarlet"
PURPOSE_BUILT_TOOL[svg]="xmlstarlet"
PURPOSE_BUILT_TOOL[sql]="sqlfluff"
PURPOSE_BUILT_TOOL[csv]="miller"
PURPOSE_BUILT_TOOL[tsv]="miller"
PURPOSE_BUILT_TOOL[log]="lnav"
PURPOSE_BUILT_TOOL[rst]="pandoc"
PURPOSE_BUILT_TOOL[tex]="pandoc"
PURPOSE_BUILT_TOOL[latex]="pandoc"

# Helper: check if extension appears as a FILE TOKEN in the command, not as
# prose mentioning the extension. Requires a path-character (letter, digit,
# /, _, -, ~, $) IMMEDIATELY before the dot; this distinguishes
# "foo.py" (path: matches) from ".py files" (prose: skips). Glob form
# "*.py" is also allowed.
ext_present() {
    local ext="$1"
    # Pattern: (path-char | '*') . ext (boundary)
    # Boundary chars: whitespace, redirect/pipe/semicolon, closing bracket,
    # quote, end-of-string. NOT a letter/digit/underscore (which would mean
    # ext is a prefix of a longer name like .pyc, .lean2).
    [[ "$CMD" =~ ([A-Za-z0-9_/~$.+\-]|\*)\.${ext}([[:space:]\>\|\;\&\)\}\"\']|$) ]]
}

DETECTED_EXT=""
DETECTED_CAT=""

# Priority 1: .lean → loogle
if ext_present "lean"; then
    DETECTED_EXT="lean"
    DETECTED_CAT="LEAN"
fi

# Priority 2: source extensions (ast-grep)
if [ -z "$DETECTED_EXT" ]; then
    for ext in "${SOURCE_BUILTIN_EXTS[@]}" "${SOURCE_CUSTOM_EXTS[@]}"; do
        if ext_present "$ext"; then
            DETECTED_EXT="$ext"
            DETECTED_CAT="SOURCE"
            break
        fi
    done
fi

# Priority 3: purpose-built tool extensions
if [ -z "$DETECTED_EXT" ]; then
    for ext in "${!PURPOSE_BUILT_TOOL[@]}"; do
        if ext_present "$ext"; then
            DETECTED_EXT="$ext"
            DETECTED_CAT="PURPOSE_BUILT"
            break
        fi
    done
fi

[ -z "$DETECTED_EXT" ] && exit 0

# (4) Emit the appropriate block message and exit 2.

if [ "$DETECTED_CAT" = "LEAN" ]; then
    cat >&2 <<'EOF'
BLOCKED: text-search tools (grep/rg/etc) are not allowed on .lean files.
Lean lemmas are searched by TYPE SIGNATURE, not by text — this catches
attribute prefixes (`protected lemma`, `@[simp] lemma`) and cross-directory
splits that anchor-regex / file-locality grep cannot.

Use loogle instead (~/.local/bin/loogle, backed by systemd user unit
loogle-server.service on port 8088):

  loogle 'Matrix.PosDef.add'                       # by exact name
  loogle 'Matrix.PosDef ?A → 0 < Matrix.det ?A'   # by type signature
  loogle 'Real.summable_one_div_nat_*'             # by name pattern

The wrapper is sub-100ms per query once the server is warm (1.5 min warmup
at boot, cached across all Claude sessions on this host).

If loogle cannot express your search, surface to the user — DO NOT fall
back to grep/rg/find/awk. The instruction surface and/or loogle setup
needs to be improved instead.

Server status:  systemctl --user status loogle-server
Server start:   systemctl --user start loogle-server
Server logs:    journalctl --user -u loogle-server -n 50
EOF
    exit 2
fi

if [ "$DETECTED_CAT" = "SOURCE" ]; then
    # Map extension → ast-grep --lang value
    LANG=""
    case "$DETECTED_EXT" in
        c|h)                              LANG="c" ;;
        cpp|cc|cxx|hpp|hh|hxx|ipp|tpp|cu|cuh|hip)  LANG="cpp" ;;
        py|pyi)                           LANG="python" ;;
        rs)                               LANG="rust" ;;
        js|mjs|cjs)                       LANG="javascript" ;;
        ts)                               LANG="typescript" ;;
        jsx)                              LANG="jsx" ;;
        tsx)                              LANG="tsx" ;;
        go)                               LANG="go" ;;
        java)                             LANG="java" ;;
        kt|kts)                           LANG="kotlin" ;;
        swift)                            LANG="swift" ;;
        scala)                            LANG="scala" ;;
        rb)                               LANG="ruby" ;;
        sh|bash|zsh)                      LANG="bash" ;;
        lua)                              LANG="lua" ;;
        php)                              LANG="php" ;;
        dart)                             LANG="dart" ;;
        ex|exs)                           LANG="elixir" ;;
        hs)                               LANG="haskell" ;;
        html|htm)                         LANG="html" ;;
        css|scss)                         LANG="css" ;;
        json)                             LANG="json" ;;
        yaml|yml)                         LANG="yaml" ;;
        md|markdown)                      LANG="markdown    (via ~/.config/ast-grep/sgconfig.yml; needs -c flag)" ;;
        toml)                             LANG="toml        (via ~/.config/ast-grep/sgconfig.yml; needs -c flag)" ;;
        *)                                LANG="$DETECTED_EXT" ;;
    esac

    cat >&2 <<EOF
BLOCKED: text-search tools (grep/rg/etc) are not allowed on .${DETECTED_EXT}
files. Source-code searches must use ast-grep, which parses the AST and
finds STRUCTURAL patterns (not text).

For .${DETECTED_EXT}: ast-grep --lang ${LANG}

Examples:
  ast-grep --lang python --pattern 'def \$NAME(\$\$\$): \$\$\$'
  ast-grep --lang cpp    --pattern '\$T \$F(\$\$\$) { \$\$\$ }'
  ast-grep --lang rust   --pattern 'fn \$F(\$\$\$) -> \$RET { \$\$\$ }'
  ast-grep --lang html   --pattern '<a href=\$URL>\$\$\$</a>'

Custom-language formats (markdown, toml) need the config flag:
  ast-grep -c ~/.config/ast-grep/sgconfig.yml --lang markdown ...

Pattern syntax: \$NAME = one identifier/expression; \$\$\$ = list (zero or more);
\$_ = match-and-discard. See \`ast-grep --help\` or https://ast-grep.github.io/.

If ast-grep cannot express your search, surface to the user — DO NOT fall
back to grep/rg/find/awk. The instruction surface and/or tooling needs
improvement.
EOF
    exit 2
fi

if [ "$DETECTED_CAT" = "PURPOSE_BUILT" ]; then
    TOOL="${PURPOSE_BUILT_TOOL[$DETECTED_EXT]}"
    case "$TOOL" in
        xmlstarlet)
            EXAMPLE="  xmlstarlet sel -t -v \"//tag[@attr='X']/text()\" file.${DETECTED_EXT}
  xmlstarlet sel -t -m \"//tag\" -v \".\" -n file.${DETECTED_EXT}
  xmllint --xpath \"//tag/text()\" file.${DETECTED_EXT}"
            ;;
        sqlfluff)
            EXAMPLE="  sqlfluff parse file.sql                  # parse to AST
  sqlfluff lint file.sql                   # lint rules
  python -c \"import sqlparse; ...\"        # programmatic"
            ;;
        miller)
            EXAMPLE="  mlr --csv cat file.csv
  mlr --csv filter '\$column > 100' file.csv
  mlr --csv put '\$new_col = \$a + \$b' file.csv"
            ;;
        lnav)
            EXAMPLE="  lnav file.log                            # interactive viewer
  lnav -n -c ';SELECT * FROM logs WHERE log_level = \"error\"' file.log
  journalctl --grep PATTERN                # systemd logs"
            ;;
        pandoc)
            EXAMPLE="  pandoc -t json file.${DETECTED_EXT} | jq '.blocks[]'
  pandoc -t json file.${DETECTED_EXT} | jq 'recurse | objects | select(.t == \"Header\")'"
            ;;
    esac

    cat >&2 <<EOF
BLOCKED: text-search tools (grep/rg/etc) are not allowed on .${DETECTED_EXT}
files. Use the format's purpose-built tool (AST-aware where possible, more
precise than text-search):

For .${DETECTED_EXT}: ${TOOL}

Examples:
${EXAMPLE}

If the purpose-built tool cannot express your search, surface to the user.
DO NOT fall back to grep/rg/find/awk. The instruction surface and/or
tooling needs improvement.
EOF
    exit 2
fi

# Unreachable, but be safe
exit 0
