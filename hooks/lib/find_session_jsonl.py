#!/usr/bin/env python3
"""Find the JSONL file for a given session ID, searching all projects."""
import sys
from pathlib import Path


def find_session_jsonl(session_id: str) -> str | None:
    """Search all project directories for this session's JSONL."""
    projects_dir = Path.home() / ".claude" / "projects"
    if not projects_dir.exists():
        return None

    for jsonl in projects_dir.rglob(f"{session_id}.jsonl"):
        if "subagents" not in str(jsonl):
            return str(jsonl)
    return None


def get_most_recent_for_project(project_path: str) -> str | None:
    """Fallback: get most recent JSONL in a project directory."""
    project_dir = Path(project_path)
    if not project_dir.exists():
        return None

    jsonls = [
        (f.stat().st_mtime, f)
        for f in project_dir.glob("*.jsonl")
        if "subagents" not in str(f)
    ]
    if jsonls:
        jsonls.sort(reverse=True)
        return str(jsonls[0][1])
    return None


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("")
        sys.exit(0)

    mode = sys.argv[1]

    if mode == "find" and len(sys.argv) >= 3:
        session_id = sys.argv[2]
        result = find_session_jsonl(session_id)
        print(result or "")
    elif mode == "recent" and len(sys.argv) >= 3:
        project_path = sys.argv[2]
        result = get_most_recent_for_project(project_path)
        print(result or "")
    else:
        print("")
