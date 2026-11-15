#!/usr/bin/env bash
# Reads every secret from Parameter Store (SecureString) and writes LibreChat's .env.
# The .env exists only on the server (chmod 600), never in git.
set -euo pipefail
source "$(dirname "$0")/config.sh"

ENV_OUT="$LC_DIR/.env"
tmp=$(mktemp)
cp "$REPO_DIR/librechat/.env.example" "$tmp"

for name in GOOGLE_KEY CREDS_KEY CREDS_IV JWT_SECRET JWT_REFRESH_SECRET MEILI_MASTER_KEY; do
  value=$(aws ssm get-parameter --with-decryption --name "$PARAM_PREFIX/$name" \
          --query Parameter.Value --output text)
  # replace the placeholder line with the real value
  sed -i "s|^$name=.*|$name=$value|" "$tmp"
done
sed -i "s|^AWS_BUCKET_NAME=.*|AWS_BUCKET_NAME=$BUCKET|" "$tmp"
sed -i "s|^AWS_REGION=.*|AWS_REGION=$REGION|" "$tmp"

DOMAIN=$(aws ssm get-parameter --name "$PARAM_PREFIX/DOMAIN" --query Parameter.Value --output text)
sed -i "s|^DOMAIN_CLIENT=.*|DOMAIN_CLIENT=https://$DOMAIN|; s|^DOMAIN_SERVER=.*|DOMAIN_SERVER=https://$DOMAIN|" "$tmp"

install -m 600 "$tmp" "$ENV_OUT"
rm -f "$tmp"
log "wrote $ENV_OUT from Parameter Store (values not printed)"
