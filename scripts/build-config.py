#!/usr/bin/env python3
"""Build librechat.yaml from the template and the handbook stored in S3.

Reads:  s3://$BUCKET/content/kalinaw-handbook.md  (versioned bucket)
Writes: librechat/librechat.yaml

Usage:  python3 scripts/build-config.py            (pulls from S3)
        python3 scripts/build-config.py --local    (uses content/ for laptop testing)
"""
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEMPLATE = ROOT / "librechat" / "librechat.template.yaml"
OUT = ROOT / "librechat" / "librechat.yaml"
LOCAL_HANDBOOK = ROOT / "content" / "kalinaw-handbook.md"
MODEL = os.environ.get("ASKALINAW_MODEL", "gemini-3.5-flash")


def from_s3():
    bucket = os.environ["BUCKET"]
    key = "content/kalinaw-handbook.md"
    text = subprocess.check_output(
        ["aws", "s3", "cp", f"s3://{bucket}/{key}", "-"], text=True)
    meta = subprocess.check_output(
        ["aws", "s3api", "head-object", "--bucket", bucket, "--key", key,
         "--query", "VersionId", "--output", "text"], text=True).strip()
    return text, f"s3 {meta[:12]}"


def main():
    if "--local" in sys.argv:
        handbook, version = LOCAL_HANDBOOK.read_text(), "local"
    else:
        handbook, version = from_s3()
    if not handbook.strip():
        sys.exit("ERROR: handbook is empty - refusing to build an assistant with no content")
    indented = "\n".join("          " + line for line in handbook.splitlines())
    out = (TEMPLATE.read_text()
           .replace("{{HANDBOOK}}", indented)
           .replace("{{HANDBOOK_VERSION}}", version)
           .replace("{{MODEL}}", MODEL))
    OUT.write_text(out)
    print(f"wrote {OUT} (handbook {version}, {len(handbook)} chars, model {MODEL})")


if __name__ == "__main__":
    main()
