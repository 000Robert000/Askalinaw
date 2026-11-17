# Askalinaw

A student help-desk assistant for **Kalinaw University** (fictional), built by reskinning
[LibreChat](https://github.com/LibreChat-AI/LibreChat) and operated on AWS.
SAM10 Systems Administration and Maintenance final project, by **Robert Santiago & Ivan Ray Dequiros**.

- Website (system card, evidence, video): https://000robert000.github.io/Askalinaw/
- Live system: https://32-236-2-242.sslip.io

## Credits and licence
- **Base system:** LibreChat by Danny Avila and contributors, <https://github.com/LibreChat-AI/LibreChat>,
  **MIT licence**. We do not copy LibreChat's code into this repo; the server clones it at deploy time
  and we add configuration, branding and operations scripts.
- **Model:** Google Gemini (`gemini-3.5-flash`) via the free-tier API. Subject to Google's Gemini API terms.
- **Content:** `content/kalinaw-handbook.md`, written by us. Entirely invented; no real personal data.
- **AI assistance:** scripts and first drafts written with Claude (Anthropic). Declared on the website.

## What's in here
| Path | What |
|---|---|
| `content/` | The handbook the assistant answers from (uploaded to S3) |
| `librechat/` | Config template, `.env.example` (no secrets), compose override, logo and CSS |
| `scripts/` | `deploy.sh`, `fetch-secrets.sh`, `build-config.py`, `backup.sh` (automation 1), `healthcheck.sh` + `ask_model.py` (automation 2), `evaluate.py`, `restore-test.sh` |
| `infra/` | `01-create-aws.sh` (creates everything), `02-server-setup.sh` (EC2 user-data), `03-monitoring.sh` (alarms + dashboard), IAM policy, CloudWatch agent config, Caddyfile, crontab, logrotate, `99-teardown.sh` |
| `fault/` | Disk-fill fault injection and the runbook |
| `docs/` | The project website (GitHub Pages) |

## How to deploy
1. Get a Gemini API key at <https://aistudio.google.com/apikey>.
2. In AWS CloudShell (as your own IAM user, with MFA), from this repo:
   ```bash
   TEAM_EMAIL=you@example.com GITHUB_REPO=https://github.com/YOU/askalinaw.git bash infra/01-create-aws.sh
   ```
   This creates the S3 bucket, Parameter Store secrets, IAM role, security group, EC2 + Elastic IP,
   SNS topic, alarms and dashboard. The EC2 user-data installs Docker, Caddy, the CloudWatch agent and
   LibreChat, runs `scripts/deploy.sh`, and installs the crontab.
3. Confirm the SNS email subscription. Open `https://<elastic-ip-with-dashes>.sslip.io`.

**Redeploy after a change:** push to `main`, then in Session Manager run `sudo /opt/askalinaw/scripts/deploy.sh`.

**Automations** (installed by `infra/crontab`):
- `backup.sh`: nightly at 18:00 UTC (02:00 Manila). Dumps MongoDB and config to S3.
- `healthcheck.sh`: every 5 minutes. Checks the site; once an hour it also checks a model answer (more often hit the Gemini free-tier limit). Publishes metrics.

Both write timestamped lines to `/var/log/askalinaw/automation.log`, which is shipped to the CloudWatch log group `/askalinaw/automation`.

**Tear down:** `bash infra/99-teardown.sh`

## Secrets policy
No key, password or token is ever committed. All secrets are SecureString parameters under `/askalinaw/`
and are read at runtime. Check before every push:
```bash
git log -p | grep -iE "AIza|AKIA|secret_access|password=" || echo "clean"
```

## Contribution log
Who did what, week by week.

| Week | Date | Robert Santiago | Ivan Ray Dequiros |
|---|---|---|---|
| 1 | 2026-11-15 | Read brief, chose domain, generated starter repo (with Claude, declared) | |
| 1 | 2026-11-16 | | Reviewed the brief, Robert's guide and the starter repo; got repo access and set up my git identity |
| 2 | 2026-11-17 | Joined the AWS project as my own member with MFA; subscribed to the alarm emails; took the monitoring and security screenshots (dashboard, alarms, request log, Parameter Store, security group, IAM role, EBS); first Well-Architected pass; updated the website with the live deployment details (with Claude's help, declared) | Created the AWS account (Free plan) with a $30 budget alert and MFA; invited Robert; deployed to Sydney with 01-create-aws.sh; found and fixed 4 deploy problems (region SCP, Free-tier instance type, branding image bug, retired Gemini model); fixed the Gemini 429 quota problem by making the model check hourly (with Claude's help, declared) |
| 3 | | | |
| 4 | | | |
| 5 | | | |
