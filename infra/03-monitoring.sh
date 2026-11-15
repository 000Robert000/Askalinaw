#!/usr/bin/env bash
# Creates: log metric filters (requests, 5xx, latency), 8 alarms -> SNS, and the dashboard.
# Called by 01-create-aws.sh, or on its own:
#   INSTANCE_ID=i-... TOPIC=arn:aws:sns:... bash infra/03-monitoring.sh
set -euo pipefail
: "${INSTANCE_ID:?}" "${TOPIC:?}"
REGION="${REGION:-ap-southeast-1}"; export AWS_DEFAULT_REGION="$REGION"
NS=Askalinaw

# Log groups exist before the agent ships anything, with retention set (not "Never expire")
for g in /askalinaw/access:14 /askalinaw/app:14 /askalinaw/containers:7 /askalinaw/automation:30; do
  aws logs create-log-group --log-group-name "${g%%:*}" --tags Project=SAM10,Team=Santiago-Dequiros 2>/dev/null || true
  aws logs put-retention-policy --log-group-name "${g%%:*}" --retention-in-days "${g##*:}"
done

# Caddy JSON access log -> request metrics
aws logs put-metric-filter --log-group-name /askalinaw/access --filter-name requests \
  --filter-pattern '{ $.status = * }' \
  --metric-transformations metricName=RequestCount,metricNamespace=$NS,metricValue=1,defaultValue=0
aws logs put-metric-filter --log-group-name /askalinaw/access --filter-name errors5xx \
  --filter-pattern '{ $.status >= 500 }' \
  --metric-transformations metricName=Errors5xx,metricNamespace=$NS,metricValue=1,defaultValue=0
aws logs put-metric-filter --log-group-name /askalinaw/access --filter-name chat-requests \
  --filter-pattern '{ $.request.uri = "/api/agents/chat*" || $.request.uri = "/api/ask*" || $.request.uri = "/api/messages*" }' \
  --metric-transformations metricName=ChatRequests,metricNamespace=$NS,metricValue=1,defaultValue=0
aws logs put-metric-filter --log-group-name /askalinaw/access --filter-name latency \
  --filter-pattern '{ $.duration > 0 }' \
  --metric-transformations 'metricName=ResponseTimeSeconds,metricNamespace='$NS',metricValue=$.duration,unit=Seconds'

alarm() {  # name, description, namespace, metric, stat, period, evals, threshold, comparison, [dims], [missing]
  aws cloudwatch put-metric-alarm --alarm-name "askalinaw-$1" --alarm-description "$2" \
    --namespace "$3" --metric-name "$4" --statistic "$5" --period "$6" --evaluation-periods "$7" \
    --threshold "$8" --comparison-operator "$9" ${10:+--dimensions ${10}} \
    --treat-missing-data "${11:-notBreaching}" \
    --alarm-actions "$TOPIC" --ok-actions "$TOPIC" --tags Key=Project,Value=SAM10
  echo "  alarm askalinaw-$1"
}
I="Name=InstanceId,Value=$INSTANCE_ID"
alarm cpu-high        "CPU >85% for 10 min: stuck process or runaway loop"  AWS/EC2 CPUUtilization Average 300 2 85 GreaterThanThreshold "$I"
alarm status-check    "EC2 status check failed: look at the instance"       AWS/EC2 StatusCheckFailed Maximum 60 1 0 GreaterThanThreshold "$I"
alarm disk-high       "Root disk >85% used: clean up or grow the disk"      CWAgent disk_used_percent Average 300 1 85 GreaterThanThreshold "$I Name=path,Value=/ Name=fstype,Value=xfs"
alarm memory-high     "Memory >90% for 5 min: process may be killed"        CWAgent mem_used_percent Average 300 1 90 GreaterThanThreshold "$I"
alarm http-5xx        "Any 5xx error from the site"                         $NS Errors5xx Sum 60 1 0 GreaterThanThreshold
alarm slow-responses  "Average response >3 s over 5 min"                    $NS ResponseTimeSeconds Average 300 1 3 GreaterThanThreshold
alarm site-down       "Health check cannot load the site (2 checks in a row)" $NS SiteDown Maximum 300 2 0 GreaterThanThreshold "" breaching
alarm answers-failed  "Model gave a wrong/failed answer to the known test question (3 checks)" $NS AnswersFailed Sum 900 1 2 GreaterThanThreshold "" breaching
alarm empty-answer    "Model returned an EMPTY answer: content or key problem" $NS EmptyAnswer Maximum 1800 1 0 GreaterThanThreshold
alarm backup-failed   "Nightly backup failed"                              $NS BackupFailed Maximum 86400 1 0 GreaterThanThreshold

# Dashboard
sed "s/INSTANCE_ID/$INSTANCE_ID/g; s/REGION/$REGION/g" infra/dashboard.json > /tmp/dash.json
aws cloudwatch put-dashboard --dashboard-name Askalinaw --dashboard-body file:///tmp/dash.json >/dev/null
echo "  dashboard Askalinaw"
