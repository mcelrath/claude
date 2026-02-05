#!/usr/bin/env python3
"""Systematic context gathering for compiler errors.

This module provides functions to extract relevant source context for compiler
error analysis. It uses multiple strategies:
1. Regex parsing of error messages for locations, identifiers, template args
2. ripgrep for finding definitions (language-agnostic)
3. ast-grep for structural extraction when available
4. Source file reading around error locations

Usage:
    from llm_gather_context import gather_context
    context = gather_context(error_text, project_dir)
"""

import subprocess
import re
import argparse
import sys
import json
import threading
from pathlib import Path
from dataclasses import dataclass, field
from typing import Any


@dataclass
class ErrorLocation:
    """A location in source code extracted from an error message."""
    file: Path
    line: int
    col: int = 1


@dataclass
class TemplateInstantiation:
    """Template instantiation extracted from error message."""
    template_name: str
    args: list[str]
    raw: str


@dataclass
class GatheredContext:
    """Collected context for error analysis."""
    locations: list[ErrorLocation] = field(default_factory=list)
    identifiers: list[str] = field(default_factory=list)
    definitions: dict[str, str] = field(default_factory=dict)
    unresolved_refs: list[str] = field(default_factory=list)
    template_instantiations: list[TemplateInstantiation] = field(default_factory=list)
    source_snippets: dict[str, str] = field(default_factory=dict)


# File extensions and their ast-grep language identifiers
LANG_MAP = {
    '.hpp': 'cpp', '.cpp': 'cpp', '.h': 'cpp', '.c': 'c',
    '.cu': 'cpp', '.cuh': 'cpp', '.hip': 'cpp',
    '.rs': 'rust',
    '.go': 'go',
    '.py': 'python',
    '.ts': 'typescript', '.tsx': 'tsx',
    '.js': 'javascript', '.jsx': 'javascript',
}


def detect_language(path: Path) -> str:
    """Detect programming language from file extension."""
    return LANG_MAP.get(path.suffix.lower(), 'cpp')


class LSPClient:
    """Generic LSP client via JSON-RPC over stdio.

    Supports multiple language servers:
    - clangd (C/C++)
    - rust-analyzer (Rust)
    - pyright (Python)
    """

    # Language server configurations
    SERVERS = {
        'cpp': {
            'command': ['clangd', '--background-index'],
            'check_file': 'compile_commands.json',
        },
        'c': {
            'command': ['clangd', '--background-index'],
            'check_file': 'compile_commands.json',
        },
        'rust': {
            'command': ['rust-analyzer'],
            'check_file': 'Cargo.toml',
        },
        'python': {
            'command': ['pyright-langserver', '--stdio'],
            'check_file': None,  # Works without config
        },
    }

    def __init__(self, project_dir: Path, lang: str = 'cpp'):
        self.project_dir = project_dir.resolve()
        self.lang = lang
        self.process: subprocess.Popen | None = None
        self.request_id = 0
        self._lock = threading.Lock()
        self._initialized = False

        # Get server config
        self.server_config = self.SERVERS.get(lang, self.SERVERS['cpp'])

    def _send_message(self, msg: dict) -> None:
        """Send a JSON-RPC message to clangd."""
        if not self.process or not self.process.stdin:
            return
        content = json.dumps(msg)
        header = f"Content-Length: {len(content)}\r\n\r\n"
        self.process.stdin.write(header.encode() + content.encode())
        self.process.stdin.flush()

    def _read_message(self, timeout: float = 10.0) -> dict | None:
        """Read a JSON-RPC message from clangd."""
        if not self.process or not self.process.stdout:
            return None

        try:
            # Read header
            headers = {}
            while True:
                line = self.process.stdout.readline().decode('utf-8')
                if line == '\r\n' or line == '\n':
                    break
                if ':' in line:
                    key, value = line.split(':', 1)
                    headers[key.strip()] = value.strip()

            content_length = int(headers.get('Content-Length', 0))
            if content_length == 0:
                return None

            content = self.process.stdout.read(content_length).decode('utf-8')
            return json.loads(content)
        except Exception:
            return None

    def _next_id(self) -> int:
        with self._lock:
            self.request_id += 1
            return self.request_id

    def start(self) -> bool:
        """Start language server and initialize the LSP connection."""
        # Check if required file exists
        check_file = self.server_config.get('check_file')
        if check_file and not (self.project_dir / check_file).exists():
            print(f"Warning: {check_file} not found in {self.project_dir}", file=sys.stderr)
            return False

        try:
            cmd = self.server_config['command'].copy()
            # Add compile_commands dir for clangd
            if self.lang in ('cpp', 'c') and (self.project_dir / 'compile_commands.json').exists():
                cmd.append(f"--compile-commands-dir={self.project_dir}")

            self.process = subprocess.Popen(
                cmd,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                cwd=self.project_dir
            )
        except FileNotFoundError:
            server_name = self.server_config['command'][0]
            print(f"Warning: {server_name} not found in PATH", file=sys.stderr)
            return False

        # Send initialize request
        init_request = {
            "jsonrpc": "2.0",
            "id": self._next_id(),
            "method": "initialize",
            "params": {
                "processId": None,
                "rootUri": f"file://{self.project_dir}",
                "capabilities": {},
                "workspaceFolders": [{"uri": f"file://{self.project_dir}", "name": "workspace"}]
            }
        }
        self._send_message(init_request)

        # Wait for initialize response
        response = self._read_message()
        if not response or "result" not in response:
            self.stop()
            return False

        # Send initialized notification
        self._send_message({"jsonrpc": "2.0", "method": "initialized", "params": {}})
        self._initialized = True
        return True

    def stop(self) -> None:
        """Shutdown clangd gracefully."""
        if self.process:
            if self._initialized:
                # Send shutdown request
                self._send_message({
                    "jsonrpc": "2.0",
                    "id": self._next_id(),
                    "method": "shutdown",
                    "params": None
                })
                self._read_message(timeout=2.0)
                self._send_message({"jsonrpc": "2.0", "method": "exit", "params": None})
            self.process.terminate()
            try:
                self.process.wait(timeout=2.0)
            except subprocess.TimeoutExpired:
                self.process.kill()
            self.process = None
            self._initialized = False

    def _open_file(self, filepath: Path) -> None:
        """Notify clangd that a file is open."""
        uri = f"file://{filepath.resolve()}"
        try:
            content = filepath.read_text()
        except Exception:
            return

        self._send_message({
            "jsonrpc": "2.0",
            "method": "textDocument/didOpen",
            "params": {
                "textDocument": {
                    "uri": uri,
                    "languageId": detect_language(filepath),
                    "version": 1,
                    "text": content
                }
            }
        })

    def get_definition(self, filepath: Path, line: int, col: int) -> list[dict]:
        """Get definition location(s) for symbol at position.

        Args:
            filepath: Source file path
            line: 1-based line number
            col: 1-based column number

        Returns:
            List of location dicts with 'uri', 'range' keys
        """
        if not self._initialized:
            return []

        self._open_file(filepath)
        uri = f"file://{filepath.resolve()}"

        request = {
            "jsonrpc": "2.0",
            "id": self._next_id(),
            "method": "textDocument/definition",
            "params": {
                "textDocument": {"uri": uri},
                "position": {"line": line - 1, "character": col - 1}  # LSP is 0-based
            }
        }
        self._send_message(request)

        # Read responses until we get our result (skip notifications)
        for _ in range(20):
            response = self._read_message()
            if response and response.get("id") == request["id"]:
                result = response.get("result", [])
                if isinstance(result, dict):
                    return [result]
                return result or []
        return []

    def get_hover(self, filepath: Path, line: int, col: int) -> str | None:
        """Get hover information for symbol at position.

        Returns:
            Hover content as string, or None
        """
        if not self._initialized:
            return None

        self._open_file(filepath)
        uri = f"file://{filepath.resolve()}"

        request = {
            "jsonrpc": "2.0",
            "id": self._next_id(),
            "method": "textDocument/hover",
            "params": {
                "textDocument": {"uri": uri},
                "position": {"line": line - 1, "character": col - 1}
            }
        }
        self._send_message(request)

        for _ in range(20):
            response = self._read_message()
            if response and response.get("id") == request["id"]:
                result = response.get("result")
                if result and "contents" in result:
                    contents = result["contents"]
                    if isinstance(contents, str):
                        return contents
                    if isinstance(contents, dict):
                        return contents.get("value", "")
                    if isinstance(contents, list):
                        return "\n".join(
                            c.get("value", c) if isinstance(c, dict) else c
                            for c in contents
                        )
                return None
        return None

    def __enter__(self):
        self.start()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.stop()
        return False


# Backwards compatibility alias
ClangdClient = LSPClient

# Global LSP client instances (reused across calls, keyed by lang)
_lsp_clients: dict[str, LSPClient] = {}


def get_lsp_client(project_dir: Path, lang: str = 'cpp') -> LSPClient | None:
    """Get or create an LSP client for the project and language."""
    global _lsp_clients
    key = f"{project_dir}:{lang}"
    if key not in _lsp_clients:
        client = LSPClient(project_dir, lang)
        if client.start():
            _lsp_clients[key] = client
        else:
            return None
    return _lsp_clients.get(key)


def get_clangd_client(project_dir: Path) -> LSPClient | None:
    """Backwards-compatible alias for get_lsp_client with C++."""
    return get_lsp_client(project_dir, 'cpp')


def parse_error_locations(error_text: str) -> list[ErrorLocation]:
    """Extract file:line:col patterns from error message.

    Handles patterns like:
    - /path/file.hpp:123:45: error: message
    - file.cpp:42: undefined reference
    """
    pattern = r'([^\s:]+\.(?:hpp|cpp|h|c|cu|cuh|hip|rs|go|py|ts|tsx|js|jsx)):(\d+)(?::(\d+))?'
    matches = re.findall(pattern, error_text)

    locations = []
    for match in matches:
        filepath, line, col = match[0], int(match[1]), int(match[2]) if match[2] else 1
        locations.append(ErrorLocation(Path(filepath), line, col))

    return locations


def parse_error_identifiers(error_text: str) -> list[str]:
    """Extract quoted identifiers from error message.

    Looks for identifiers in:
    - Single quotes: 'identifier'
    - Double quotes: "identifier"
    - Backticks: `identifier`
    """
    # Match quoted identifiers
    pattern = r"['\"`]([a-zA-Z_][a-zA-Z0-9_:]*)['\"`]"
    identifiers = set(re.findall(pattern, error_text))

    # Also extract identifiers from common error patterns
    # e.g., "use of undeclared identifier 'foo'"
    undeclared = re.findall(r"undeclared identifier\s*['\"`]?(\w+)", error_text)
    identifiers.update(undeclared)

    # "static assertion failed due to requirement '2 <= k0_loops'"
    # Extract variable names from expressions
    expr_pattern = r"requirement\s*['\"`]([^'\"]+)['\"`]"
    for match in re.findall(expr_pattern, error_text):
        # Extract identifiers from the expression
        expr_ids = re.findall(r'\b([a-zA-Z_][a-zA-Z0-9_]*)\b', match)
        # Filter out keywords and numbers
        keywords = {'if', 'else', 'for', 'while', 'return', 'true', 'false', 'nullptr', 'const', 'static'}
        identifiers.update(id for id in expr_ids if id not in keywords and not id.isdigit())

    return list(identifiers)


def parse_template_instantiations(error_text: str) -> list[TemplateInstantiation]:
    """Extract template instantiations from error messages.

    Parses patterns like:
    - TileFmhaShape<ck_tile::sequence<32, 64, 32, 512, 32, 64>, ...>
    - vector<int>
    - FmhaFwdKernel<BlockFmhaPipelineQRKSVS<...>>
    """
    instantiations = []

    # Match TemplateName<args> patterns - handle nested brackets
    # Simple regex for top-level templates
    pattern = r'\b([A-Z][a-zA-Z0-9_]*)<([^<>]+(?:<[^<>]*>)?[^<>]*)>'
    for match in re.finditer(pattern, error_text):
        name = match.group(1)
        args_str = match.group(2)
        # Split args by comma, but respect nested templates
        args = [a.strip() for a in args_str.split(',')]
        instantiations.append(TemplateInstantiation(
            template_name=name,
            args=args,
            raw=match.group(0)
        ))

    # Also extract sequence<...> patterns which contain numeric values
    seq_pattern = r'sequence<([0-9,\s]+)>'
    for match in re.finditer(seq_pattern, error_text):
        values = [v.strip() for v in match.group(1).split(',')]
        instantiations.append(TemplateInstantiation(
            template_name="sequence",
            args=values,
            raw=match.group(0)
        ))

    return instantiations


def read_source_snippet(filepath: Path, line: int, context_lines: int = 10) -> str:
    """Read source code around a specific line.

    Returns lines [line - context_lines, line + context_lines] with line numbers.
    """
    if not filepath.exists():
        return ""

    try:
        lines = filepath.read_text().splitlines()
        start = max(0, line - context_lines - 1)
        end = min(len(lines), line + context_lines)

        result = []
        for i in range(start, end):
            marker = ">>>" if i == line - 1 else "   "
            result.append(f"{marker} {i+1:4d}: {lines[i]}")
        return "\n".join(result)
    except Exception:
        return ""


def lsp_get_definition(filepath: Path, line: int, col: int, project_dir: Path, lang: str = 'cpp') -> str | None:
    """Use LSP to get definition at a location.

    Returns the source code at the definition location.
    """
    client = get_lsp_client(project_dir, lang)
    if not client:
        return None

    try:
        locations = client.get_definition(filepath, line, col)
        if not locations:
            return None

        # Get the first definition location
        loc = locations[0]
        uri = loc.get("uri", "")
        if not uri.startswith("file://"):
            return None

        def_path = Path(uri[7:])  # Remove file:// prefix
        if not def_path.exists():
            return None

        # Get the range
        range_info = loc.get("range", {})
        start = range_info.get("start", {})
        def_line = start.get("line", 0) + 1  # LSP is 0-based

        # Read snippet around definition
        return read_source_snippet(def_path, def_line, context_lines=15)
    except Exception:
        return None


def lsp_get_hover(filepath: Path, line: int, col: int, project_dir: Path, lang: str = 'cpp') -> str | None:
    """Use LSP to get hover info (type, documentation) at a location."""
    client = get_lsp_client(project_dir, lang)
    if not client:
        return None

    try:
        return client.get_hover(filepath, line, col)
    except Exception:
        return None


# Backwards-compatible aliases
def clangd_get_definition(filepath: Path, line: int, col: int, project_dir: Path) -> str | None:
    return lsp_get_definition(filepath, line, col, project_dir, 'cpp')

def clangd_get_hover(filepath: Path, line: int, col: int, project_dir: Path) -> str | None:
    return lsp_get_hover(filepath, line, col, project_dir, 'cpp')


def grep_find_definition(identifier: str, directory: Path, extensions: list[str] = None) -> str:
    """Use ripgrep to find definitions of an identifier.

    This is a language-agnostic fallback when ast-grep patterns don't match.
    Searches for common definition patterns:
    - constexpr/const declarations
    - struct/class definitions
    - function definitions
    - variable assignments
    """
    if extensions is None:
        extensions = ['hpp', 'cpp', 'h', 'c', 'cu', 'cuh', 'hip', 'rs', 'go', 'py', 'ts', 'js']

    glob_pattern = ','.join(f'*.{ext}' for ext in extensions)

    # Patterns that likely indicate a definition (not just usage)
    definition_patterns = [
        f"(static\\s+)?constexpr.*\\b{identifier}\\s*=",
        f"(static\\s+)?const.*\\b{identifier}\\s*=",
        f"\\b(struct|class|enum)\\s+{identifier}\\b",
        f"\\bdef\\s+{identifier}\\s*\\(",  # Python
        f"\\bfunc\\s+{identifier}\\s*\\(",  # Go
        f"\\bfn\\s+{identifier}\\s*[<(]",   # Rust
        f"\\bfunction\\s+{identifier}\\s*\\(",  # JS
        f"\\b{identifier}\\s*=\\s*function",    # JS
    ]

    combined_pattern = "|".join(f"({p})" for p in definition_patterns)

    try:
        result = subprocess.run(
            ["rg", "-n", "--glob", f"{{{glob_pattern}}}", "-e", combined_pattern, str(directory)],
            capture_output=True, text=True, timeout=30
        )
        if result.stdout.strip():
            # Limit to first 20 matches
            lines = result.stdout.strip().split('\n')[:20]
            return "\n".join(lines)
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass

    return ""


def ast_grep_extract(pattern: str, directory: Path, lang: str = "cpp") -> str:
    """Run ast-grep with given pattern and return matched code.

    Args:
        pattern: ast-grep pattern with metavariables ($NAME, $$$BODY, etc.)
        directory: Directory to search
        lang: Language identifier (cpp, rust, go, python, etc.)

    Returns:
        Matched code text, or empty string if no match
    """
    try:
        result = subprocess.run(
            ["ast-grep", "run", "-l", lang, "-p", pattern, str(directory)],
            capture_output=True, text=True, timeout=30
        )
        return result.stdout
    except subprocess.TimeoutExpired:
        return ""
    except FileNotFoundError:
        print("Warning: ast-grep not found", file=sys.stderr)
        return ""


def extract_struct_definition(name: str, directory: Path, lang: str = "cpp") -> str:
    """Extract complete struct/class definition by name.

    Tries multiple patterns to handle templates, classes, and structs.
    """
    patterns = [
        f"template <$$$PARAMS> struct {name} {{ $$$BODY }}",
        f"struct {name} {{ $$$BODY }}",
        f"template <$$$PARAMS> class {name} {{ $$$BODY }}",
        f"class {name} {{ $$$BODY }}",
    ]

    for pattern in patterns:
        result = ast_grep_extract(pattern, directory, lang)
        if result.strip():
            return result
    return ""


def extract_function_definition(name: str, directory: Path, lang: str = "cpp") -> str:
    """Extract complete function definition by name."""
    patterns = [
        f"$RET {name}($$$ARGS) {{ $$$BODY }}",
        f"template <$$$TPARAMS> $RET {name}($$$ARGS) {{ $$$BODY }}",
    ]

    for pattern in patterns:
        result = ast_grep_extract(pattern, directory, lang)
        if result.strip():
            return result
    return ""


def extract_constexpr_definition(identifier: str, directory: Path, lang: str = "cpp") -> str:
    """Find constexpr definitions for an identifier."""
    patterns = [
        f"static constexpr $TYPE {identifier} = $EXPR",
        f"constexpr $TYPE {identifier} = $EXPR",
        f"const $TYPE {identifier} = $EXPR",
    ]

    for pattern in patterns:
        result = ast_grep_extract(pattern, directory, lang)
        if result.strip():
            return result
    return ""


def extract_referenced_identifiers(code: str) -> list[str]:
    """Extract identifiers referenced in code for recursive gathering."""
    # Find identifiers that look like constants (kFoo, K_FOO, etc.)
    pattern = r'\b(k[A-Z][a-zA-Z0-9_]*|K_[A-Z0-9_]+)\b'
    identifiers = set(re.findall(pattern, code))

    # Also find identifiers in expressions like "foo / bar"
    expr_pattern = r'\b([a-zA-Z_][a-zA-Z0-9_]*)\s*[/+\-*%<>=]\s*([a-zA-Z_][a-zA-Z0-9_]*)\b'
    for match in re.findall(expr_pattern, code):
        identifiers.update(match)

    return list(identifiers)


def extract_scope_references(code: str) -> list[tuple[str, str]]:
    """Extract Foo::bar patterns from code.

    Returns list of (scope, member) tuples, e.g., ('BlockFmhaShape', 'kK0').
    """
    pattern = r'\b([A-Z][a-zA-Z0-9_]*)::(k?[a-zA-Z_][a-zA-Z0-9_]*)\b'
    return list(set(re.findall(pattern, code)))


def find_unresolved_references(ctx: 'GatheredContext') -> list[str]:
    """Find Foo::bar references where Foo has no definition in context.

    This detects cases like:
        kK0 = BlockFmhaShape::kK0
    where we have the constexpr but not the BlockFmhaShape struct definition.

    Returns list of unresolved scope names (e.g., ['BlockFmhaShape']).
    """
    # Collect all code from definitions
    all_code = "\n".join(ctx.definitions.values())

    # Find all Foo::bar patterns
    scope_refs = extract_scope_references(all_code)

    # Check which scopes have definitions
    defined_structs = set()
    for key in ctx.definitions:
        if key.startswith("struct_"):
            defined_structs.add(key[7:])  # Remove "struct_" prefix

    # Find unresolved scopes
    unresolved = set()
    for scope, member in scope_refs:
        if scope not in defined_structs:
            unresolved.add(scope)

    return sorted(unresolved)


def gather_context(error_text: str, project_dir: Path, lang: str = "cpp",
                   max_depth: int = 2, use_clangd: bool = True,
                   use_ast_grep: bool = False) -> GatheredContext:
    """Gather all relevant context for error analysis.

    Uses multiple strategies:
    1. Parse error for locations, identifiers, template instantiations
    2. Use clangd LSP for hover info and go-to-definition at error locations
    3. Read source snippets around error locations
    4. Optionally use ast-grep for structural extraction (slow on large codebases)
    5. Fall back to ripgrep for definition finding

    Args:
        error_text: The compiler error message
        project_dir: Root directory to search for source files
        lang: Primary language to use for ast-grep patterns
        max_depth: Maximum depth for following references
        use_clangd: Whether to use clangd for LSP-based lookups
        use_ast_grep: Whether to use ast-grep (disabled by default - slow)

    Returns:
        GatheredContext with locations, identifiers, definitions, and more
    """
    ctx = GatheredContext()

    # Parse error for locations, identifiers, and template instantiations
    ctx.locations = parse_error_locations(error_text)
    ctx.identifiers = parse_error_identifiers(error_text)
    ctx.template_instantiations = parse_template_instantiations(error_text)

    # Read source snippets around error locations and use clangd for hover info
    for loc in ctx.locations:
        # Try both absolute and relative to project_dir
        filepath = loc.file if loc.file.is_absolute() else project_dir / loc.file

        # If file doesn't exist, try to find it via glob search
        if not filepath.exists():
            matches = list(project_dir.glob(f"**/{loc.file.name}"))
            if matches:
                filepath = matches[0]  # Use first match

        if filepath.exists():
            snippet = read_source_snippet(filepath, loc.line)
            if snippet:
                ctx.source_snippets[f"{filepath}:{loc.line}"] = snippet

            # Use LSP for hover info at error location (shows type info)
            if use_clangd:
                # Detect language from file extension
                file_lang = detect_language(filepath)

                hover = lsp_get_hover(filepath, loc.line, loc.col, project_dir, file_lang)
                if hover:
                    ctx.definitions[f"hover_{filepath.name}:{loc.line}:{loc.col}"] = hover

                # Also scan the error line for identifiers and get hover for each
                try:
                    line_content = filepath.read_text().splitlines()[loc.line - 1]
                    for ident in ctx.identifiers:
                        pos = line_content.find(ident)
                        if pos >= 0:
                            ident_hover = lsp_get_hover(filepath, loc.line, pos + 1, project_dir, file_lang)
                            if ident_hover:
                                ctx.definitions[f"hover_{ident}"] = ident_hover
                except Exception:
                    pass

                # Try to get definition at error location
                definition = lsp_get_definition(filepath, loc.line, loc.col, project_dir, file_lang)
                if definition:
                    ctx.definitions[f"lsp_def_{filepath.name}:{loc.line}:{loc.col}"] = definition

    # Track processed identifiers to avoid duplicates
    processed = set()
    to_process = list(ctx.identifiers)
    depth = 0

    # Only do identifier resolution if ast-grep is enabled (slow on large codebases)
    # When clangd is available, hover info usually provides sufficient context
    if use_ast_grep:
        while to_process and depth < max_depth:
            current_batch = to_process
            to_process = []

            for ident in current_batch:
                # Skip common keywords and short identifiers
                if len(ident) < 2 or ident in processed:
                    continue
                processed.add(ident)

                # Strategy 1: Try ast-grep for struct/class definition
                struct_def = extract_struct_definition(ident, project_dir, lang)
                if struct_def:
                    ctx.definitions[f"struct_{ident}"] = struct_def
                    to_process.extend(extract_referenced_identifiers(struct_def))
                    continue

                # Strategy 2: Try ast-grep for constexpr definition
                constexpr_def = extract_constexpr_definition(ident, project_dir, lang)
                if constexpr_def:
                    ctx.definitions[f"constexpr_{ident}"] = constexpr_def
                    to_process.extend(extract_referenced_identifiers(constexpr_def))
                    continue

                # Strategy 3: Try ast-grep for function definition
                func_def = extract_function_definition(ident, project_dir, lang)
                if func_def:
                    ctx.definitions[f"func_{ident}"] = func_def
                    continue

                # Strategy 4: Fall back to grep-based search
                grep_def = grep_find_definition(ident, project_dir)
                if grep_def:
                    ctx.definitions[f"grep_{ident}"] = grep_def
                    to_process.extend(extract_referenced_identifiers(grep_def))

            depth += 1

    # Find unresolved references (e.g., BlockFmhaShape::kK0 without BlockFmhaShape definition)
    ctx.unresolved_refs = find_unresolved_references(ctx)

    return ctx


def format_context(ctx: GatheredContext) -> str:
    """Format gathered context as text for LLM."""
    parts = []

    if ctx.identifiers:
        parts.append(f"Identifiers extracted: {', '.join(ctx.identifiers)}")

    if ctx.unresolved_refs:
        parts.append(f"UNRESOLVED REFERENCES: {', '.join(ctx.unresolved_refs)}")

    # Include template instantiations with their concrete values
    if ctx.template_instantiations:
        ti_lines = ["TEMPLATE INSTANTIATIONS (from error message):"]
        for ti in ctx.template_instantiations:
            ti_lines.append(f"  {ti.template_name}<{', '.join(ti.args)}>")
        parts.append("\n".join(ti_lines))

    # Include source snippets around error locations
    for location, snippet in ctx.source_snippets.items():
        parts.append(f"=== SOURCE at {location} ===\n{snippet}")

    # Include definitions found
    for name, code in ctx.definitions.items():
        parts.append(f"=== {name} ===\n{code}")

    return "\n\n".join(parts)


def cleanup_clangd():
    """Cleanup clangd client on exit."""
    global _clangd_client
    if _clangd_client:
        _clangd_client.stop()
        _clangd_client = None


def main():
    """CLI entry point for context gathering."""
    import atexit
    atexit.register(cleanup_clangd)

    parser = argparse.ArgumentParser(
        description="Gather source context for compiler error analysis"
    )
    parser.add_argument(
        "error_input",
        help="Error message or file containing error"
    )
    parser.add_argument(
        "project_dir",
        nargs="?",
        default=".",
        help="Project directory to search (default: current)"
    )
    parser.add_argument(
        "-l", "--lang",
        default="cpp",
        help="Primary language (cpp, rust, go, python)"
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Show verbose output"
    )
    parser.add_argument(
        "--no-clangd",
        action="store_true",
        help="Disable clangd LSP integration"
    )
    parser.add_argument(
        "--ast-grep",
        action="store_true",
        help="Enable ast-grep for deep definition search (slow on large codebases)"
    )

    args = parser.parse_args()

    # Read error from file or use as string
    error_input = Path(args.error_input)
    if error_input.exists():
        error_text = error_input.read_text()
    else:
        error_text = args.error_input

    project_dir = Path(args.project_dir).resolve()

    if args.verbose:
        print(f"Project: {project_dir}", file=sys.stderr)
        print(f"Language: {args.lang}", file=sys.stderr)
        print(f"Clangd: {'disabled' if args.no_clangd else 'enabled'}", file=sys.stderr)
        print(f"ast-grep: {'enabled' if args.ast_grep else 'disabled'}", file=sys.stderr)

    # Gather and format context
    ctx = gather_context(error_text, project_dir, args.lang,
                        use_clangd=not args.no_clangd,
                        use_ast_grep=args.ast_grep)

    if args.verbose:
        print(f"Found {len(ctx.identifiers)} identifiers", file=sys.stderr)
        print(f"Found {len(ctx.definitions)} definitions", file=sys.stderr)

    print(format_context(ctx))


if __name__ == "__main__":
    main()
