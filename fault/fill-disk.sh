#!/usr/bin/env bash
# WS-F fault injection: simulates a runaway "chat debug log" that is never rotated.
# Writes 1 GB every 30 s into /var/log/askalinaw/chat-debug.log until the root disk is 98% full.
# Run inside a Session Manager shell:  sudo /opt/askalinaw/fault/fill-disk.sh
# Then DO NOT FIX IT YET: wait for the disk alarm email and note the time. Follow the runbook.
set -euo pipefail
LOG=/var/log/askalinaw/fault-timeline.log
F=/var/log/askalinaw/chat-debug.log
echo "$(date -u +%FT%TZ) FAULT STARTED (fill-disk.sh)" | tee -a "$LOG"
df -h / | tee -a "$LOG"
i=0
while [ "$(df --output=pcent / | tail -1 | tr -dc 0-9)" -lt 98 ]; do
  i=$((i + 1))
  fallocate -l "$((i))G" "$F"
  echo "$(date -u +%FT%TZ) chat-debug.log = ${i}G, disk $(df --output=pcent / | tail -1)" | tee -a "$LOG"
  sleep 30
done
echo "$(date -u +%FT%TZ) disk at 98% - leaving it broken. Go and check the app + your email." | tee -a "$LOG"
