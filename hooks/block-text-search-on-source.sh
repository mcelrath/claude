#!/bin/bash
# PreToolUse hook for Bash. Blocks text-search tools (grep, rg, etc.) on
# source-code-file CONTENT. Redirects to loogle for .lean, ast-grep for general
# source code, and purpose-built tools for xml/sql/csv/log/rst/tex.
#
# PIPELINE-AWARE (2026-05-29, user-directed): the decision is delegated to
# _grep_pipeline_analyzer.py, which blocks only when a text-search stage reads
# source-file CONTENT —
#   (a) grep PAT file.py            (direct source-file argument)
#   (b) cat file.py | grep PAT      (piped from a file-reader on a source file)
#   plus find … -exec grep,  … | xargs grep  on source files.
# It ALLOWS text-search piped from any non-file-reader command:
#   bd show … | grep …   git log … | grep …   ls … | grep …   echo … | grep …
# This removes the old "extension appears anywhere in the command" false
# positives (command-output greps, `cd dir; bd … | grep`, .ext strings in
# heredoc/message bodies) WITHOUT weakening the anti-shallow-read intent.
#
# NO BYPASS — per PLAN-hook-grep-replacement.md and user direction. If the
# hook fires and the agent can't accomplish its task with ast-grep/loogle/
# purpose-built tool, the agent MUST surface to the user.
#
# Allowed (text-search IS the right tool): .txt .ini .cfg .conf .lock and any
# file under .lake/ build/ dist/ node_modules/ target/ .venv/ .cache/ .git/

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)
[ "$TOOL_NAME" != "Bash" ] && exit 0

CMD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)
[ -z "$CMD" ] && exit 0

# Pipeline-aware verdict: source-file extension to block, or "ALLOW".
DETECTED_EXT=$(python3 "$HOME/.claude/hooks/_grep_pipeline_analyzer.py" "$CMD" 2>/dev/null)
[ -z "$DETECTED_EXT" ] && exit 0          # analyzer error → fail-open
[ "$DETECTED_EXT" = "ALLOW" ] && exit 0

# Categorize the detected extension for the right message.
SOURCE_BUILTIN_EXTS=(c cc cpp cxx h hpp hh hxx ipp tpp cu cuh hip py pyi rs js mjs cjs jsx ts tsx go java kt kts swift scala rb sh bash zsh lua php dart ex exs hs html htm css scss json yaml yml)
SOURCE_CUSTOM_EXTS=(md markdown toml)
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
# log intentionally omitted: grep IS the right tool for unstructured log files
# (user-directed 2026-05-30); the analyzer no longer flags .log.
PURPOSE_BUILT_TOOL[rst]="pandoc"
PURPOSE_BUILT_TOOL[tex]="pandoc"
PURPOSE_BUILT_TOOL[latex]="pandoc"

DETECTED_CAT=""
if [ "$DETECTED_EXT" = "lean" ]; then
    DETECTED_CAT="LEAN"
fi
if [ -z "$DETECTED_CAT" ]; then
    for ext in "${SOURCE_BUILTIN_EXTS[@]}" "${SOURCE_CUSTOM_EXTS[@]}"; do
        if [ "$ext" = "$DETECTED_EXT" ]; then
            DETECTED_CAT="SOURCE"
            break
        fi
    done
fi
if [ -z "$DETECTED_CAT" ] && [ -n "${PURPOSE_BUILT_TOOL[$DETECTED_EXT]}" ]; then
    DETECTED_CAT="PURPOSE_BUILT"
fi
[ -z "$DETECTED_CAT" ] && exit 0          # unknown extension → fail-open

# Emit the appropriate block message and exit 2.

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

loogle indexes BUILT oleans by qualified-name/type. For things loogle can't do
— locate a decl in an UNBUILT/sorry file, find USAGES, find IMPORTERS, or locate
when you don't know the qualified name — use `lean-search` (source-level locator,
prints file:line then you Read the file):
  lean-search NAME            # where NAME is DEFINED
  lean-search -u NAME         # usages of NAME
  lean-search -i MODULE       # who imports MODULE

If neither loogle nor lean-search expresses your search, surface to the user —
DO NOT fall back to grep/rg/find/awk on .lean.

Server status:  systemctl --user status loogle-server
Server start:   systemctl --user start loogle-server
Server logs:    journalctl --user -u loogle-server -n 50
EOF
    exit 2
fi

if [ "$DETECTED_CAT" = "SOURCE" ]; then
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
BLOCKED: text-search over .${DETECTED_EXT} file CONTENT (grep PAT file, or
cat file | grep) is not allowed. Source-code searches must use ast-grep, which
parses the AST and finds STRUCTURAL patterns (not text). (Grep of COMMAND
OUTPUT — e.g. \`bd show … | grep\` — is allowed; this fired because a source
file is being read into the search.)

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
Or just Read the file in full.

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
BLOCKED: text-search over .${DETECTED_EXT} file CONTENT is not allowed. Use the
format's purpose-built tool (AST-aware where possible, more precise than
text-search). (Grep of COMMAND OUTPUT is allowed; this fired because a source
file is being read into the search.)

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
