# RUNBOOK: Server disk full (askalinaw-disk-high)

Owner: Santiago & Dequiros   Last tested: 18 Nov 2026   Takes: ~15 minutes   Ask: Robert Santiago / Ivan Ray Dequiros

## 1. WHAT THIS IS FOR
Getting Askalinaw working again when the server's root disk is full, and stopping it filling again.

## 2. HOW YOU KNOW YOU NEED IT
- Email from AWS Notifications: **ALARM: "askalinaw-disk-high"** (disk > 85%).
- Often followed by `askalinaw-http-5xx` or `askalinaw-answers-failed`.
- Users: chats don't save, "Something went wrong", or login fails.

Command that shows the problem (EC2 > instance > Connect > Session Manager):
```bash
df -h /                     # Use% at 90-100%
```

## 3. WHAT IT AFFECTS
Everyone. MongoDB cannot write, so new messages and logins fail. Old pages may still load.

## 4. HOW TO DO IT
Step 1: Become root.
```bash
sudo -i
```
-> prompt ends in `#`

Step 2: Find what is big.
```bash
du -xh / --max-depth=2 2>/dev/null | sort -rh | head -15
du -sh /var/log/askalinaw/* | sort -rh | head
```
-> one huge file stands out (in INC-01: `/var/log/askalinaw/chat-debug.log`)

Step 3: Check nothing is holding deleted files open.
```bash
lsof +L1 | head
```
-> ideally empty. If a process holds a deleted file, restart that process.

Step 4: Free the space. Truncate (don't just `rm`) a log that a process might hold open.
```bash
truncate -s 0 /var/log/askalinaw/chat-debug.log
df -h /
```
-> Use% back to normal (≈ 20–30%)

Step 5: Restart the app so it reconnects cleanly to the database.
```bash
cd /opt/LibreChat && docker compose restart api mongodb
docker compose ps
```
-> all containers `Up`

Step 6: Install the prevention (log rotation) if it isn't already there.
```bash
cp /opt/askalinaw/infra/logrotate-askalinaw /etc/logrotate.d/askalinaw
dnf install -y logrotate
mkdir -p /etc/systemd/system/logrotate.timer.d
printf '[Timer]\nOnCalendar=\nOnCalendar=hourly\n' > /etc/systemd/system/logrotate.timer.d/hourly.conf
systemctl daemon-reload && systemctl enable --now logrotate.timer
logrotate -d /etc/logrotate.d/askalinaw 2>&1 | tail -5
systemctl list-timers logrotate.timer
```
-> debug output lists the askalinaw log files with no errors

## 5. HOW TO CHECK IT WORKED
- [ ] `df -h /` under 85%
- [ ] Open the site, log in, ask "Where is the Registrar's Office?" -> answer mentions Mabini Hall
- [ ] `askalinaw-disk-high` goes back to OK (OK email arrives)
- [ ] No new alarms for 10 minutes

## 6. HOW TO UNDO IT
Truncating a log loses that log's content only. If the app won't start after step 5:
`docker compose down && docker compose up -d --no-deps api mongodb meilisearch`.
If the database is damaged, follow the restore test: `/opt/askalinaw/scripts/restore-test.sh`.

## 7. GOTCHAS
- `rm` on a log that a process still writes to does NOT free space until the process restarts — use `truncate`.
- Session Manager itself needs a little free disk; if it won't connect, reboot the instance from the console first.
- Docker container logs live in `/var/lib/docker/containers/` — they are capped by our docker-compose.override.yml (10 MB × 3).

## 8. CHANGE HISTORY
18 Nov 2026 – Written after incident INC-01 (runaway debug log filled the disk).
