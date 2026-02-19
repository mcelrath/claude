#!/usr/bin/env python3
"""Summarize a Claude Code session JSONL for handoff using local LLM.

Reads actual user+assistant conversation text (not compressed metadata)
so the LLM can name specific math objects, functions, theorems, files.

Usage: summarize_session.py <jsonl_path> <plan_file> <local_llm_url>
Output: JSON on stdout
"""
import sys
import json
import re
import urllib.request

FALLBACK = '{"summary":"LLM unavailable","current_task":"unknown","next_steps":["kb_list for context","check handoff files_edited section"],"blockers":[]}'

SYSTEM_PROMPT = "Summarize this Claude Code session for handoff. Output ONLY valid JSON."

USER_SUFFIX = '''\n\nOutput JSON with as much detail as needed — do not truncate findings or next steps:
{
  "summary": "paragraph: the arc of this session — what problem was being solved, what approach was taken, what was discovered or changed",
  "findings": ["each significant discovery, decision, or result from this session — be specific, name math objects/theorems/functions"],
  "current_task": "the specific file, function, theorem, or object being actively worked on at session end",
  "next_steps": ["each concrete next action with specific file/function/theorem names — as many as needed"],
  "blockers": ["each unresolved issue or open question, or empty list"]
}'''

SKIP_PREFIXES = (
    '<local-command', '<system', '<command-',
    '<task-notification', '/clear', '/compact'
)


def extract_conversation(jsonl_path: str, max_turns: int = 15) -> list[tuple[str, str]]:
    """Extract last N user+assistant text turns from JSONL."""
    turns = []
    try:
        with open(jsonl_path) as f:
            for line in f:
                if not line.strip():
                    continue
                try:
                    obj = json.loads(line)
                    msg_type = obj.get('type')
                    if msg_type == 'user':
                        content = obj.get('message', {}).get('content', '')
                        if isinstance(content, str) and len(content.strip()) > 10:
                            if not any(content.startswith(p) for p in SKIP_PREFIXES):
                                turns.append(('USER', content[:400]))
                    elif msg_type == 'assistant':
                        for c in obj.get('message', {}).get('content', []):
                            if isinstance(c, dict) and c.get('type') == 'text':
                                text = c.get('text', '').strip()
                                if len(text) > 20:
                                    turns.append(('ASSISTANT', text[:800]))
                except Exception:
                    pass
    except Exception:
        pass
    return turns[-max_turns:]


def call_local_llm(context: str, url: str, model: str) -> str | None:
    payload = json.dumps({
        "model": model,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": context + USER_SUFFIX},
        ],
        "max_tokens": 1200,
        "temperature": 0.3,
    }).encode()
    try:
        req = urllib.request.Request(
            url, data=payload, headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(req, timeout=60) as resp:
            r = json.loads(resp.read())
            msg = r.get('choices', [{}])[0].get('message', {})
            return msg.get('content', '') or msg.get('reasoning_content', '')
    except Exception:
        return None


def get_model(url: str) -> str:
    """Ask local LLM server which model is loaded."""
    try:
        models_url = url.replace('/v1/chat/completions', '/v1/models')
        with urllib.request.urlopen(models_url, timeout=5) as resp:
            data = json.loads(resp.read())
            models = data.get('data', [])
            if models:
                return models[0]['id']
    except Exception:
        pass
    return 'GLM-4.7-Flash-Q4_K_M.gguf'


def main():
    if len(sys.argv) < 4:
        print(FALLBACK)
        return

    jsonl_path, plan_file, llm_url = sys.argv[1], sys.argv[2], sys.argv[3]

    turns = extract_conversation(jsonl_path)
    if not turns:
        print(FALLBACK)
        return

    parts = [f"{role}: {text}" for role, text in turns]
    context = f"Plan: {plan_file}\n\nConversation (last {len(turns)} turns):\n" + "\n\n".join(parts)

    model = get_model(llm_url)
    result = call_local_llm(context, llm_url, model)

    if result:
        result = re.sub(r'^```json\s*', '', result.strip())
        result = re.sub(r'\s*```$', '', result.strip())
        try:
            json.loads(result)
            print(result)
            return
        except Exception:
            pass

    print(FALLBACK)


if __name__ == '__main__':
    main()
