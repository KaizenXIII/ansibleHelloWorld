#!/usr/bin/env python3
"""
PR / Code Review Agent — Learning Example
==========================================
This script shows how to build an AI agent using the Anthropic API with tool use.

KEY CONCEPTS DEMONSTRATED:
  1. Tool definitions  — teach the model what functions it can call
  2. Agentic loop      — keep calling the API until the model stops using tools
  3. Tool execution    — run the requested tool and feed results back

HOW IT WORKS:
  User question
       │
       ▼
  Claude API ──► stop_reason == "end_turn"  ──► print final answer
       │
       │  stop_reason == "tool_use"
       ▼
  Execute tool(s) locally
       │
       ▼
  Claude API  (repeat)
"""

import os
import subprocess
from pathlib import Path

import anthropic

# ---------------------------------------------------------------------------
# 1. Tool definitions
#    These are JSON schemas that describe what the model can "call".
#    The model never runs these itself — YOUR code does, in the loop below.
# ---------------------------------------------------------------------------

TOOLS = [
    {
        "name": "read_file",
        "description": "Read the contents of a file in the repository.",
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {
                    "type": "string",
                    "description": "Relative path from the repo root, e.g. 'playbooks/site.yml'",
                }
            },
            "required": ["path"],
        },
    },
    {
        "name": "list_files",
        "description": "List files/directories inside a given directory.",
        "input_schema": {
            "type": "object",
            "properties": {
                "directory": {
                    "type": "string",
                    "description": "Relative path to directory, e.g. 'roles/hello_world'",
                }
            },
            "required": ["directory"],
        },
    },
    {
        "name": "git_diff",
        "description": "Show the git diff for changed files (staged + unstaged).",
        "input_schema": {
            "type": "object",
            "properties": {
                "target": {
                    "type": "string",
                    "description": "Optional: a specific file path or branch to diff against (e.g. 'main' or 'playbooks/site.yml'). Leave empty for full diff.",
                }
            },
            "required": [],
        },
    },
    {
        "name": "git_log",
        "description": "Show recent git commit history.",
        "input_schema": {
            "type": "object",
            "properties": {
                "max_count": {
                    "type": "integer",
                    "description": "Number of commits to show (default 10).",
                }
            },
            "required": [],
        },
    },
]


# ---------------------------------------------------------------------------
# 2. Tool execution
#    Plain Python functions — no magic, just os/subprocess/pathlib calls.
# ---------------------------------------------------------------------------

REPO_ROOT = Path(__file__).parent


def read_file(path: str) -> str:
    full = REPO_ROOT / path
    if not full.exists():
        return f"ERROR: file not found: {path}"
    try:
        return full.read_text()
    except Exception as e:
        return f"ERROR reading {path}: {e}"


def list_files(directory: str) -> str:
    full = REPO_ROOT / directory
    if not full.exists():
        return f"ERROR: directory not found: {directory}"
    entries = sorted(full.rglob("*"))
    lines = [str(p.relative_to(REPO_ROOT)) for p in entries if not p.name.startswith(".")]
    return "\n".join(lines) if lines else "(empty)"


def git_diff(target: str = "") -> str:
    cmd = ["git", "diff", "--stat", "HEAD"]
    if target:
        cmd = ["git", "diff", target]
    result = subprocess.run(cmd, cwd=REPO_ROOT, capture_output=True, text=True)
    output = result.stdout or result.stderr
    return output.strip() or "(no diff output)"


def git_log(max_count: int = 10) -> str:
    cmd = ["git", "log", f"--max-count={max_count}", "--oneline", "--decorate"]
    result = subprocess.run(cmd, cwd=REPO_ROOT, capture_output=True, text=True)
    return result.stdout.strip() or "(no commits)"


def execute_tool(name: str, tool_input: dict) -> str:
    """Dispatch a tool call to the matching Python function."""
    if name == "read_file":
        return read_file(tool_input["path"])
    elif name == "list_files":
        return list_files(tool_input["directory"])
    elif name == "git_diff":
        return git_diff(tool_input.get("target", ""))
    elif name == "git_log":
        return git_log(tool_input.get("max_count", 10))
    else:
        return f"ERROR: unknown tool '{name}'"


# ---------------------------------------------------------------------------
# 3. The agentic loop
#    This is the core pattern for any tool-using agent:
#      - send messages → model responds
#      - if tool_use → run tool, add result, repeat
#      - if end_turn → we're done
# ---------------------------------------------------------------------------

def run_review_agent(user_request: str) -> str:
    """
    Run the code-review agent for a given user request.
    Returns the final text answer from the model.
    """
    client = anthropic.Anthropic()   # reads ANTHROPIC_API_KEY from env

    system_prompt = (
        "You are an expert Ansible code reviewer. "
        "You have tools to read files, list directories, and inspect git history. "
        "Use them to thoroughly review the code before giving your feedback. "
        "Structure your review with sections: Summary, Issues Found, Recommendations."
    )

    messages = [{"role": "user", "content": user_request}]

    print(f"\n{'='*60}")
    print("🤖 Code Review Agent starting...")
    print(f"{'='*60}")

    iteration = 0
    while True:
        iteration += 1
        print(f"\n[Turn {iteration}] Calling Claude API...")

        response = client.messages.create(
            model="claude-opus-4-6",
            max_tokens=4096,
            system=system_prompt,
            tools=TOOLS,
            messages=messages,
        )

        print(f"  stop_reason: {response.stop_reason}")

        # ------------------------------------------------------------------
        # CASE A: Model is done — extract and return the final text answer
        # ------------------------------------------------------------------
        if response.stop_reason == "end_turn":
            final_text = next(
                (block.text for block in response.content if block.type == "text"),
                "(no text in response)"
            )
            return final_text

        # ------------------------------------------------------------------
        # CASE B: Model wants to call tools — execute them and loop back
        # ------------------------------------------------------------------
        if response.stop_reason == "tool_use":
            # Add the assistant's response (including tool_use blocks) to history
            messages.append({"role": "assistant", "content": response.content})

            # Collect results for ALL tool calls in this turn
            tool_results = []
            for block in response.content:
                if block.type == "tool_use":
                    print(f"  🔧 Tool call: {block.name}({block.input})")
                    result = execute_tool(block.name, block.input)
                    # Truncate very long results to avoid blowing up context
                    if len(result) > 3000:
                        result = result[:3000] + "\n...[truncated]"
                    print(f"     → {len(result)} chars returned")

                    # Tool results must reference the matching tool_use_id
                    tool_results.append({
                        "type": "tool_result",
                        "tool_use_id": block.id,
                        "content": result,
                    })

            # Add all tool results as a single user message and loop
            messages.append({"role": "user", "content": tool_results})
            continue

        # ------------------------------------------------------------------
        # CASE C: Unexpected stop reason — bail out safely
        # ------------------------------------------------------------------
        return f"Unexpected stop_reason: {response.stop_reason}"


# ---------------------------------------------------------------------------
# 4. Entry point — try a few different review requests
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    if not os.environ.get("ANTHROPIC_API_KEY"):
        print("❌  Set ANTHROPIC_API_KEY before running this script.")
        exit(1)

    # You can change this prompt to review specific files, roles, or recent commits
    request = (
        "Please review the Ansible project in this repository. "
        "Start by listing the top-level structure, then read the main playbooks "
        "and at least one role. Check the git log for recent changes. "
        "Give me a concise code review with any issues or improvements you spot."
    )

    review = run_review_agent(request)

    print(f"\n{'='*60}")
    print("📋 REVIEW RESULT")
    print(f"{'='*60}\n")
    print(review)
