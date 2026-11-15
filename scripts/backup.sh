#!/usr/bin/env bash
# AUTOMATION 1 — nightly backup (cron 02:00 Manila time).
# Dumps MongoDB, copies the LibreChat config, uploads both to S3.
# S3 lifecycle rule deletes backups after 14 days (requirement: keep >= 7).
set -euo pipefail
source "$(dirname "$0")/config.sh"

stamp=$(date -u +%Y%m%dT%H%M%SZ)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

docker exec chat-mongodb mongodump --db LibreChat --archive --gzip > "$work/mongo-$stamp.archive.gz"
size=$(stat -c %s "$work/mongo-$stamp.archive.gz")
if [ "$size" -lt 1000 ]; then
  log "FAILED: dump suspiciously small ($size bytes)"
  aws cloudwatch put-metric-data --namespace "$METRIC_NS" --metric-name BackupFailed --value 1
  exit 1
fi

tar -czf "$work/config-$stamp.tar.gz" -C "$LC_DIR" librechat.yaml docker-compose.override.yml

aws s3 cp "$work/mongo-$stamp.archive.gz" "s3://$BUCKET/backups/mongo/" --only-show-errors
aws s3 cp "$work/config-$stamp.tar.gz"   "s3://$BUCKET/backups/config/" --only-show-errors
aws cloudwatch put-metric-data --namespace "$METRIC_NS" --metric-name BackupFailed --value 0
log "OK: backup $stamp uploaded (mongo $size bytes) to s3://$BUCKET/backups/"
