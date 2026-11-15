#!/usr/bin/env bash
# WS-C restore test. Simulates losing the database and restores it from the
# latest S3 backup. Keeps the old data folder so you can undo.
#   sudo /opt/askalinaw/scripts/restore-test.sh
set -euo pipefail
source "$(dirname "$0")/config.sh"
cd "$LC_DIR"

count() { docker exec chat-mongodb mongosh LibreChat --quiet --eval \
  'print("users=" + db.users.countDocuments() + " conversations=" + db.conversations.countDocuments() + " messages=" + db.messages.countDocuments())'; }

log "RESTORE TEST START"
echo "== Before (live data) =="; count | tee -a "$LOG_DIR/automation.log"

latest=$(aws s3 ls "s3://$BUCKET/backups/mongo/" | sort | tail -1 | awk '{print $4}')
echo "== Latest backup: $latest =="
aws s3 cp "s3://$BUCKET/backups/mongo/$latest" /tmp/restore.archive.gz --only-show-errors

t0=$(date +%s)
echo "== Simulating disaster: stopping app and moving the database folder away =="
docker compose stop api mongodb
mv data-node "data-node.before-restore-$(date +%s)"
docker compose up -d mongodb
sleep 10
echo "== Empty database now: =="; count

echo "== Restoring =="
docker exec -i chat-mongodb mongorestore --archive --gzip --drop < /tmp/restore.archive.gz
docker compose up -d --no-deps api
until curl -sf http://localhost:3080/health >/dev/null; do sleep 3; done
t1=$(date +%s)

echo "== After restore =="; count | tee -a "$LOG_DIR/automation.log"
log "RESTORE TEST DONE from $latest in $((t1 - t0)) seconds. Now log in and open an old conversation."
