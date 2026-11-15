#!/usr/bin/env python3
"""Ask the Gemini model one question with the Askalinaw system prompt.

Used by healthcheck.sh and evaluate.py. Reads the API key from Parameter Store
at runtime (never from a file in the repo).

Prints:  "<PASS|FAIL|EMPTY|ERROR> <latency_ms>" on line 1, the answer after it.
Usage:   ask_model.py "<question>" "<keyword expected in a correct answer>"
"""
import json
import os
import re
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REGION = os.environ.get("REGION", "ap-southeast-1")
MODEL = os.environ.get("ASKALINAW_MODEL", "gemini-2.5-flash")


def get_param(name, decrypt=True):
    cmd = ["aws", "ssm", "get-parameter", "--region", REGION, "--name", f"/askalinaw/{name}",
           "--query", "Parameter.Value", "--output", "text"]
    if decrypt:
        cmd.insert(3, "--with-decryption")
    return subprocess.check_output(cmd, text=True).strip()


def system_prompt():
    """Take the exact promptPrefix the running app uses."""
    cfg = (ROOT / "librechat" / "librechat.yaml")
    if not cfg.exists():
        cfg = ROOT / "librechat" / "librechat.template.yaml"
    text = cfg.read_text()
    block = text.split("promptPrefix: |", 1)[1]
    return "\n".join(line[10:] for line in block.splitlines()[1:])


def ask(question, key):
    url = (f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent")
    body = {
        "systemInstruction": {"parts": [{"text": system_prompt()}]},
        "contents": [{"role": "user", "parts": [{"text": question}]}],
        "generationConfig": {"temperature": 0.2},
    }
    req = urllib.request.Request(url, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json",
                                          "x-goog-api-key": key})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=60) as r:
        data = json.load(r)
    ms = int((time.time() - t0) * 1000)
    try:
        answer = data["candidates"][0]["content"]["parts"][0]["text"]
    except (KeyError, IndexError):
        answer = ""
    return answer, ms


def main():
    question, expected = sys.argv[1], sys.argv[2]
    try:
        answer, ms = ask(question, get_param("GOOGLE_KEY"))
    except Exception as e:  # network, quota, bad key...
        print(f"ERROR 0\n{type(e).__name__}: {e}")
        return
    if not answer.strip():
        status = "EMPTY"
    elif re.search(expected, answer, re.IGNORECASE):
        status = "PASS"
    else:
        status = "FAIL"
    print(f"{status} {ms}\n{answer.strip()}")


if __name__ == "__main__":
    main()
