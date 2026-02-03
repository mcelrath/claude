#!/usr/bin/env python3
"""Gather context about active sessions, plans, and agents for recovery."""
import json
import os
from datetime import datetime
from pathlib import Path


def get_recent_sessions(projects_dir: Path, limit: int = 5) -> list[dict]:
    """Get most recent sessions across all projects."""
    sessions = []
    for jsonl in projects_dir.rglob("*.jsonl"):
        if "subagents" in str(jsonl) or jsonl.stem.startswith("agent-"):
            continue
        try:
            stat = jsonl.stat()
            project = jsonl.parent.name.replace("-home-mcelrath-", "").replace("-", "/")
            sessions.append({
                "id": jsonl.stem[:8],
                "full_id": jsonl.stem,
                "project": project[:20],
                "modified": datetime.fromtimestamp(stat.st_mtime).strftime("%H:%M"),
                "size_kb": stat.st_size // 1024,
                "path": str(jsonl)
            })
        except Exception:
            pass
    sessions.sort(key=lambda x: x["modified"], reverse=True)
    return sessions[:limit]


def get_active_plans(plans_dir: Path, limit: int = 5) -> list[dict]:
    """Get recently modified plan files (exclude agent outputs)."""
    plans = []
    for md in plans_dir.glob("*.md"):
        if "-agent-" in md.stem:
            continue
        try:
            stat = md.stat()
            name = md.stem
            if len(name) > 30:
                name = name[:27] + "..."
            plans.append({
                "name": name,
                "modified": datetime.fromtimestamp(stat.st_mtime).strftime("%H:%M"),
                "path": str(md)
            })
        except Exception:
            pass
    plans.sort(key=lambda x: x["modified"], reverse=True)
    return plans[:limit]


def get_session_plans(sessions_dir: Path) -> dict[str, str]:
    """Get current_plan for each session."""
    result = {}
    for d in sessions_dir.iterdir():
        if d.is_dir():
            cp = d / "current_plan"
            if cp.exists():
                try:
                    plan_path = cp.read_text().strip()
                    plan_name = Path(plan_path).stem
                    result[d.name[:8]] = plan_name[:25]
                except Exception:
                    pass
    return result


def get_running_agents() -> list[dict]:
    """Check for running background agents."""
    agents = []
    tasks_dir = Path("/tmp/claude-1000")
    if not tasks_dir.exists():
        return agents
    for output in tasks_dir.rglob("*.output"):
        try:
            stat = output.stat()
            age_min = (datetime.now().timestamp() - stat.st_mtime) / 60
            if age_min < 30:
                agents.append({
                    "id": output.stem[:7],
                    "age": f"{int(age_min)}m ago",
                    "path": str(output)
                })
        except Exception:
            pass
    return agents[:5]


def main():
    home = Path.home()
    projects_dir = home / ".claude" / "projects"
    plans_dir = home / ".claude" / "plans"
    sessions_dir = home / ".claude" / "sessions"

    sessions = get_recent_sessions(projects_dir)
    plans = get_active_plans(plans_dir)
    session_plans = get_session_plans(sessions_dir)
    agents = get_running_agents()

    for s in sessions:
        s["plan"] = session_plans.get(s["id"], "-")

    result = {
        "sessions": sessions,
        "plans": plans,
        "agents": agents
    }
    print(json.dumps(result))


if __name__ == "__main__":
    main()
