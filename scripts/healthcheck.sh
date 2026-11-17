#!/usr/bin/env bash
# AUTOMATION 2 — health + answer check (cron, every 5 minutes).
#  1. Is the website up? (every run, free)       -> metric SiteDown (0/1)
#  2. Does the model still answer correctly?      -> AnswersFailed, EmptyAnswer, AnswerLatencyMs
#     Only once an hour: every-5-minute model calls (288/day) exhausted the
#     Gemini free-tier quota and caused HTTP 429 (incident, 2026-11-17).
# Alarms on these metrics email the team through SNS.
set -uo pipefail
source "$(dirname "$0")/config.sh"

DOMAIN=$(aws ssm get-parameter --name "$PARAM_PREFIX/DOMAIN" --query Parameter.Value --output text)
put() { aws cloudwatch put-metric-data --namespace "$METRIC_NS" --metric-name "$1" --value "$2" ${3:+--unit $3}; }

# 1. website (every run)
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://$DOMAIN/health")
if [ "$code" = "200" ]; then put SiteDown 0; else put SiteDown 1; fi

# 2. model answer check (first run of each hour only)
minute=$((10#$(date -u +%M)))
if [ "$minute" -ge 5 ] && [ "${FORCE_ANSWER_CHECK:-0}" != "1" ]; then
  log "site=$code answer=skipped"
  exit 0
fi

result=$(python3 "$REPO_DIR/scripts/ask_model.py" \
  "Where is the Registrar's Office and what are its hours?" "Mabini" 2>&1)
status=$(echo "$result" | head -1 | cut -d' ' -f1)
latency=$(echo "$result" | head -1 | cut -d' ' -f2)
reason=""
[ "$status" = "ERROR" ] && reason=" reason=\"$(echo "$result" | sed -n 2p | cut -c1-80)\""

case "$status" in
  PASS)  put AnswersFailed 0; put EmptyAnswer 0 ;;
  EMPTY) put AnswersFailed 1; put EmptyAnswer 1 ;;
  *)     put AnswersFailed 1; put EmptyAnswer 0 ;;
esac
[ -n "$latency" ] && [ "$latency" != "0" ] && put AnswerLatencyMs "$latency" Milliseconds

log "site=$code answer=$status latency_ms=${latency:-NA}${reason}"