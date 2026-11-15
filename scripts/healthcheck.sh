#!/usr/bin/env bash
# AUTOMATION 2 — health + answer check every 5 minutes (cron).
#  1. Is the website up?          -> metric SiteDown (0/1)
#  2. Does the model still answer a known question correctly?
#                                  -> metrics AnswersFailed, EmptyAnswer, AnswerLatencyMs
# Alarms on these metrics email the team through SNS.
set -uo pipefail
source "$(dirname "$0")/config.sh"

DOMAIN=$(aws ssm get-parameter --name "$PARAM_PREFIX/DOMAIN" --query Parameter.Value --output text)
put() { aws cloudwatch put-metric-data --namespace "$METRIC_NS" --metric-name "$1" --value "$2" ${3:+--unit $3}; }

# 1. website
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://$DOMAIN/health")
if [ "$code" = "200" ]; then put SiteDown 0; else put SiteDown 1; fi

# 2. model answer check (same prompt the app uses, a question with a known answer)
result=$(python3 "$REPO_DIR/scripts/ask_model.py" \
  "Where is the Registrar's Office and what are its hours?" "Mabini" 2>&1)
status=$(echo "$result" | head -1 | cut -d' ' -f1)
latency=$(echo "$result" | head -1 | cut -d' ' -f2)

case "$status" in
  PASS)  put AnswersFailed 0; put EmptyAnswer 0 ;;
  EMPTY) put AnswersFailed 1; put EmptyAnswer 1 ;;
  *)     put AnswersFailed 1; put EmptyAnswer 0 ;;
esac
[ -n "$latency" ] && put AnswerLatencyMs "$latency" Milliseconds

log "site=$code answer=$status latency_ms=${latency:-NA}"
