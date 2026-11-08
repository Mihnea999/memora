#!/usr/bin/env python3
"""Claude Code's permission prompts, answered in the Memora AI window.

Claude Code runs this as an MCP server (stdio) and calls its `approve` tool
whenever it wants to do something not allowed by default (run a command, change
a file, ...): `claude -p --permission-prompt-tool mcp__memora__approve`. Each
call goes over a Unix socket ($MEMORA_AI_PERMIT) to the agent of the window,
which asks the person and answers {"behavior": "allow"|"deny", ...}.

Only the standard library: a minimal MCP (JSON-RPC 2.0, one message per line).
"""
import json
import os
import socket
import sys

TOOL = {
    "name": "approve",
    "description": "Ask the person at the computer whether a tool may run.",
    "inputSchema": {
        "type": "object",
        "properties": {
            "tool_name": {"type": "string"},
            "input": {"type": "object"},
            "tool_use_id": {"type": "string"},
        },
        "required": ["tool_name", "input"],
    },
}


def ask(args):
    path = os.environ.get("MEMORA_AI_PERMIT", "")
    if not path:
        return {"behavior": "deny", "message": "Memora AI is not running."}
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.connect(path)
            s.sendall((json.dumps(args) + "\n").encode())
            data = b""
            while not data.endswith(b"\n"):
                chunk = s.recv(65536)
                if not chunk:
                    break
                data += chunk
        return json.loads(data or b"{}") or {"behavior": "deny", "message": "No answer."}
    except (OSError, ValueError) as e:
        return {"behavior": "deny", "message": f"Could not ask the person ({e})."}


def reply(id_, result=None, error=None):
    m = {"jsonrpc": "2.0", "id": id_}
    if error:
        m["error"] = error
    else:
        m["result"] = result
    sys.stdout.write(json.dumps(m) + "\n")
    sys.stdout.flush()


def main():
    for line in sys.stdin:
        try:
            m = json.loads(line)
        except ValueError:
            continue
        method, id_ = m.get("method"), m.get("id")
        if id_ is None:          # a notification (initialized, cancelled): nothing to answer
            continue
        if method == "initialize":
            reply(id_, {"protocolVersion": (m.get("params") or {}).get("protocolVersion", "2025-06-18"),
                        "capabilities": {"tools": {}},
                        "serverInfo": {"name": "memora", "version": "1.0"}})
        elif method == "tools/list":
            reply(id_, {"tools": [TOOL]})
        elif method == "tools/call":
            p = m.get("params") or {}
            if p.get("name") != "approve":
                reply(id_, error={"code": -32602, "message": "unknown tool"})
                continue
            answer = ask(p.get("arguments") or {})
            reply(id_, {"content": [{"type": "text", "text": json.dumps(answer)}]})
        elif method == "ping":
            reply(id_, {})
        else:
            reply(id_, error={"code": -32601, "message": "method not found"})


if __name__ == "__main__":
    main()
