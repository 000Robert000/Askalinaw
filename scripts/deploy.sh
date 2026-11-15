#!/usr/bin/env bash
# (Re)deploys Askalinaw: pull repo, fetch secrets, rebuild config from S3, restart.
# Run as root on the EC2 instance:  sudo /opt/askalinaw/scripts/deploy.sh
set -euo pipefail
source "$(dirname "$0")/config.sh"

cd "$REPO_DIR" && git pull --ff-only || true
export ASKALINAW_VERSION=$(git -C "$REPO_DIR" rev-parse --short HEAD)

"$REPO_DIR/scripts/fetch-secrets.sh"
python3 "$REPO_DIR/scripts/build-config.py"
cp "$REPO_DIR/librechat/librechat.yaml" "$LC_DIR/librechat.yaml"
cp "$REPO_DIR/librechat/docker-compose.override.yml" "$LC_DIR/docker-compose.override.yml"
"$REPO_DIR/scripts/apply-branding.sh"

cd "$LC_DIR"
# Only the services we need (no RAG/vector DB -> smaller, cheaper)
docker compose up -d --no-deps --force-recreate api mongodb meilisearch
log "deployed version $ASKALINAW_VERSION"
