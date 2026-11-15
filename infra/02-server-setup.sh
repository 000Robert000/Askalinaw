#!/bin/bash
# EC2 user-data: runs ONCE as root when the server first boots.
# Installs Docker, Caddy (HTTPS), CloudWatch agent, LibreChat and our repo, then deploys.
# Progress log on the server: /var/log/cloud-init-output.log
set -euxo pipefail
REPO_URL="__REPO_URL__"
REGION="__REGION__"
export AWS_DEFAULT_REGION="$REGION"

dnf install -y docker git cronie python3 amazon-cloudwatch-agent
systemctl enable --now docker crond

# Docker compose plugin
mkdir -p /usr/local/lib/docker/cli-plugins
curl -sSL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# 2 GB swap so a memory spike doesn't kill the app
fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# Repos
git clone "$REPO_URL" /opt/askalinaw
git clone --depth 1 https://github.com/LibreChat-AI/LibreChat.git /opt/LibreChat
git -C /opt/LibreChat rev-parse HEAD > /opt/askalinaw-librechat-commit.txt
mkdir -p /var/log/askalinaw /var/log/caddy /opt/LibreChat/logs
chmod +x /opt/askalinaw/scripts/*.sh /opt/askalinaw/fault/*.sh

# Caddy (automatic HTTPS)
curl -sSL "https://caddyserver.com/api/download?os=linux&arch=amd64" -o /usr/bin/caddy
chmod +x /usr/bin/caddy
mkdir -p /etc/caddy
aws ssm get-parameter --name /askalinaw/CADDYFILE --query Parameter.Value --output text > /etc/caddy/Caddyfile
cat > /etc/systemd/system/caddy.service <<'EOF'
[Unit]
Description=Caddy
After=network-online.target
[Service]
ExecStart=/usr/bin/caddy run --config /etc/caddy/Caddyfile
Restart=always
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload && systemctl enable --now caddy

# CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s \
  -c file:/opt/askalinaw/infra/cloudwatch-agent.json

# Deploy app + schedule automations
REGION="$REGION" /opt/askalinaw/scripts/deploy.sh
crontab /opt/askalinaw/infra/crontab
echo "Askalinaw setup finished $(date -u)" >> /var/log/askalinaw/automation.log
