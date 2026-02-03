#!/bin/bash
# LSP setup hook for Claude Code
# Ensures LSP configuration exists for error analysis
# Supports: C++, Rust, Python
# Also pre-warms LSP servers for faster error analysis

# Read JSON input from stdin
input=$(cat)

# Extract cwd from JSON input
cwd=$(echo "$input" | jq -r '.cwd // "."' 2>/dev/null)
cd "$cwd" 2>/dev/null || exit 0

status=()
LSP_CACHE_DIR="$HOME/.cache/claude-lsp"
mkdir -p "$LSP_CACHE_DIR"

# --- C++ / CUDA / HIP ---
cpp_files=$(find . -maxdepth 3 \( -name "*.cpp" -o -name "*.hpp" -o -name "*.cu" -o -name "*.hip" -o -name "*.c" -o -name "*.h" \) 2>/dev/null | head -1)
if [[ -n "$cpp_files" ]]; then
    if [[ -f "compile_commands.json" ]]; then
        status+=("C++: compile_commands.json exists")
    else
        # Try to find and symlink from common build directories
        found=0
        for build_dir in build build-debug cmake-build-debug cmake-build-release out; do
            if [[ -f "${build_dir}/compile_commands.json" ]]; then
                ln -sf "${build_dir}/compile_commands.json" compile_commands.json
                status+=("C++: symlinked compile_commands.json from ${build_dir}/")
                found=1
                break
            fi
        done
        if [[ $found -eq 0 ]]; then
            status+=("C++: compile_commands.json MISSING")
        fi
    fi
fi

# --- Rust ---
if [[ -f "Cargo.toml" ]]; then
    if command -v rust-analyzer &>/dev/null; then
        # Start rust-analyzer in background to pre-warm index
        project_hash=$(echo "$cwd" | md5sum | cut -c1-8)
        pidfile="$LSP_CACHE_DIR/rust-analyzer-${project_hash}.pid"

        # Check if already running
        if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
            status+=("Rust: rust-analyzer running (pid $(cat "$pidfile"))")
        else
            # Start rust-analyzer in background
            (
                cd "$cwd"
                echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":null,"rootUri":"file://'"$cwd"'","capabilities":{}}}' | \
                rust-analyzer 2>/dev/null &
                echo $! > "$pidfile"
            ) &
            status+=("Rust: rust-analyzer starting (indexing)")
        fi
    else
        status+=("Rust: rust-analyzer NOT INSTALLED")
    fi
fi

# --- Python ---
py_files=$(find . -maxdepth 2 -name "*.py" 2>/dev/null | head -1)
if [[ -n "$py_files" ]]; then
    if [[ -f "pyrightconfig.json" ]] || [[ -f "pyproject.toml" ]]; then
        status+=("Python: config exists")
    elif command -v pyright &>/dev/null; then
        status+=("Python: pyright available (no config)")
    elif command -v pylsp &>/dev/null; then
        status+=("Python: pylsp available")
    else
        status+=("Python: no LSP configured")
    fi
fi

# Output status
if [[ ${#status[@]} -gt 0 ]]; then
    echo "LSP: $(IFS=', '; echo "${status[*]}")"
fi
