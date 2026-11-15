#!/usr/bin/env bash
# Copies our logo/CSS next to LibreChat and makes an index.html that loads our CSS.
set -euo pipefail
source "$(dirname "$0")/config.sh"

B="$LC_DIR/askalinaw-branding"
mkdir -p "$B"
cp "$REPO_DIR/librechat/branding/logo.svg" "$REPO_DIR/librechat/branding/askalinaw.css" "$B/"

# Pull the stock index.html out of the image once, then add our stylesheet + title.
IMAGE=$(cd "$LC_DIR" && docker compose config --images | grep -i librechat | head -1)
cid=$(docker create "$IMAGE")
docker cp "$cid:/app/client/dist/index.html" "$B/index.html.orig"
docker rm "$cid" >/dev/null

sed -e 's|</head>|<link rel="stylesheet" href="/assets/askalinaw.css"></head>|' \
    -e 's|<title>[^<]*</title>|<title>Askalinaw</title>|' \
    "$B/index.html.orig" > "$B/index.html"
log "branding applied (logo, css, title)"
