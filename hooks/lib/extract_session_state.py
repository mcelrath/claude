#!/usr/bin/env python3
"""Extract session state from Claude JSONL transcript."""
import json
import sys
import re
from pathlib import Path


def extract_state(jsonl_path: str, max_messages: int = 50) -> dict:
    """Extract messages, tasks, and KB IDs from session transcript."""
    messages = []
    task_map = {}  # id -> task dict
    user_queries = []  # All real user queries (will take last 3)
    kb_queried = set()  # KB IDs from kb_search results
    kb_superseded = set()  # KB IDs that were superseded via kb_correct
    kb_added = []  # KB entries added this session [{content, tags, project}]
    kb_all = set()  # All KB IDs mentioned (fallback)
    files_read = set()  # Files examined via Read
    files_edited = set()  # Files modified via Edit/Write

    skip_prefixes = ('<local-command', '<system', '<command-', '<task-notification', '/clear', '/compact')

    with open(jsonl_path) as f:
        for line in f:
            if not line.strip():
                continue
            # Track all KB IDs mentioned (fallback)
            kb_all.update(re.findall(r'kb-\d{8}-\d{6}-[a-f0-9]{6}', line))
            try:
                obj = json.loads(line)
                msg_type = obj.get('type')

                if msg_type == 'assistant':
                    for c in obj.get('message', {}).get('content', []):
                        if isinstance(c, dict):
                            if c.get('type') == 'text':
                                messages.append({
                                    'role': 'assistant',
                                    'text': c.get('text', '')[:2000]
                                })
                            elif c.get('type') == 'tool_use':
                                name = c.get('name', '')
                                inp = c.get('input', {})
                                # Track TaskCreate/TaskUpdate for task state
                                if name == 'TaskCreate':
                                    tid = inp.get('taskId') or f"t{len(task_map)}"
                                    task_map[tid] = {
                                        'id': tid,
                                        'subject': inp.get('subject', ''),
                                        'description': inp.get('description', ''),
                                        'status': 'pending'
                                    }
                                elif name == 'TaskUpdate':
                                    tid = inp.get('taskId', '')
                                    if tid in task_map:
                                        if 'status' in inp:
                                            task_map[tid]['status'] = inp['status']
                                        if 'subject' in inp:
                                            task_map[tid]['subject'] = inp['subject']
                                # Track kb_correct to identify superseded entries
                                elif name == 'mcp__knowledge-base__kb_correct':
                                    supersedes_id = inp.get('supersedes_id', '')
                                    if supersedes_id:
                                        kb_superseded.add(supersedes_id)
                                # Track kb_add to capture new findings
                                elif name == 'mcp__knowledge-base__kb_add':
                                    kb_added.append({
                                        'content': inp.get('content', '')[:500],
                                        'tags': inp.get('tags', ''),
                                        'project': inp.get('project', ''),
                                        'finding_type': inp.get('finding_type', '')
                                    })
                                # Track file operations
                                elif name == 'Read':
                                    fp = inp.get('file_path', '')
                                    if fp and not fp.startswith('/tmp/'):
                                        files_read.add(fp)
                                elif name in ('Edit', 'Write'):
                                    fp = inp.get('file_path', '')
                                    if fp and not fp.startswith('/tmp/'):
                                        files_edited.add(fp)
                                messages.append({
                                    'role': 'tool',
                                    'name': name,
                                    'input': str(inp)[:500]
                                })

                elif msg_type == 'user':
                    content = obj.get('message', {}).get('content', [])
                    if isinstance(content, str):
                        messages.append({'role': 'user', 'text': content[:1000]})
                        # Track all real user queries
                        if len(content.strip()) > 5:
                            if not any(content.startswith(p) for p in skip_prefixes):
                                user_queries.append(content[:300])
                    elif isinstance(content, list):
                        for item in content:
                            if isinstance(item, dict) and item.get('type') == 'tool_result':
                                result_content = str(item.get('content', ''))
                                messages.append({
                                    'role': 'tool_result',
                                    'content': result_content[:500]
                                })
                                # Extract KB IDs from kb_search results
                                kb_queried.update(re.findall(r'kb-\d{8}-\d{6}-[a-f0-9]{6}', result_content))
            except Exception:
                pass

    # Task reconciliation: infer completion from evidence
    def infer_task_completion(task: dict, files_edited: set, kb_added: list) -> str:
        """Infer task status from evidence if agent didn't update it."""
        if task.get('status') != 'pending':
            return task.get('status', 'pending')

        desc = (task.get('subject', '') + ' ' + task.get('description', '')).lower()

        # Check if files related to task were edited
        for f in files_edited:
            fname = Path(f).name.lower()
            # Match file patterns in task description
            if any(kw in desc for kw in [fname, Path(f).stem.lower()]):
                return 'inferred_completed'

        # Check if KB findings suggest completion
        completion_indicators = ['proven', 'verified', 'completed', 'success', 'implemented']
        for kb in kb_added:
            kb_content = kb.get('content', '').lower()
            # Check if KB finding relates to task and indicates completion
            task_words = set(desc.split()) - {'the', 'a', 'an', 'to', 'for', 'in', 'of'}
            kb_words = set(kb_content.split())
            overlap = len(task_words & kb_words)
            if overlap >= 3:  # Significant overlap
                if any(ind in kb_content for ind in completion_indicators):
                    return 'inferred_completed'
                if kb.get('finding_type') == 'success':
                    return 'inferred_completed'

        return 'pending'

    # Apply reconciliation to tasks
    for tid, task in task_map.items():
        task['status'] = infer_task_completion(task, files_edited, kb_added)

    # Filter: keep pending, in_progress, inferred_completed (for review)
    # Exclude only explicitly completed/deleted
    active_tasks = [t for t in task_map.values()
                    if t.get('status') not in ('completed', 'deleted')]

    # KB IDs: prefer queried ones, fall back to all mentioned, exclude superseded
    kb_ids = kb_queried if kb_queried else kb_all
    kb_ids = kb_ids - kb_superseded

    return {
        'messages': messages[-max_messages:],
        'tasks': active_tasks,
        'kb_ids': sorted(kb_ids),
        'kb_superseded': sorted(kb_superseded),
        'kb_added': kb_added[-3:],  # Last 3 entries added
        'files_read': sorted(files_read),
        'files_edited': sorted(files_edited),
        'first_request': user_queries[0] if user_queries else '',
        'last_queries': user_queries[-3:] if user_queries else [],
        'reconciliation_applied': True  # Flag that inference was applied
    }


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('{}')
        sys.exit(0)
    try:
        print(json.dumps(extract_state(sys.argv[1])))
    except Exception:
        print('{}')
        sys.exit(0)
