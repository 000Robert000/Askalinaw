#!/usr/bin/env bash
# END OF TERM: deletes everything Askalinaw created (brief section 6.2).
# Run in CloudShell AFTER you have recorded the video and taken every screenshot.
set -uo pipefail
REGION="${REGION:-ap-southeast-2}"; export AWS_DEFAULT_REGION="$REGION"
read -rp "Type DELETE to remove all askalinaw resources: " ok; [ "$ok" = "DELETE" ] || exit 1

IID=$(aws ec2 describe-instances --filters Name=tag:Name,Values=askalinaw-server Name=instance-state-name,Values=running,stopped --query 'Reservations[].Instances[].InstanceId' --output text)
[ -n "$IID" ] && aws ec2 terminate-instances --instance-ids $IID && aws ec2 wait instance-terminated --instance-ids $IID
for a in $(aws ec2 describe-addresses --filters Name=tag:Project,Values=SAM10 Name=tag:Team,Values=Santiago-Dequiros --query 'Addresses[].AllocationId' --output text); do aws ec2 release-address --allocation-id "$a"; done
aws ec2 delete-security-group --group-name askalinaw-web
BUCKET=$(aws ssm get-parameter --name /askalinaw/BUCKET --query Parameter.Value --output text)
python3 - "$BUCKET" <<'EOF'
import boto3, sys
b = boto3.resource("s3").Bucket(sys.argv[1]); b.object_versions.delete(); b.delete(); print("bucket deleted")
EOF
aws ssm delete-parameters --names $(aws ssm get-parameters-by-path --path /askalinaw --query 'Parameters[].Name' --output text)
aws cloudwatch delete-alarms --alarm-names $(aws cloudwatch describe-alarms --alarm-name-prefix askalinaw- --query 'MetricAlarms[].AlarmName' --output text)
aws cloudwatch delete-dashboards --dashboard-names Askalinaw
for g in /askalinaw/access /askalinaw/app /askalinaw/containers /askalinaw/automation; do aws logs delete-log-group --log-group-name $g; done
aws sns delete-topic --topic-arn "$(aws sns list-topics --query "Topics[?ends_with(TopicArn,':askalinaw-alerts')].TopicArn" --output text)"
aws iam remove-role-from-instance-profile --instance-profile-name askalinaw-ec2-profile --role-name askalinaw-ec2-role
aws iam delete-instance-profile --instance-profile-name askalinaw-ec2-profile
aws iam delete-role-policy --role-name askalinaw-ec2-role --policy-name askalinaw-least-privilege
aws iam detach-role-policy --role-name askalinaw-ec2-role --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam detach-role-policy --role-name askalinaw-ec2-role --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
aws iam delete-role --role-name askalinaw-ec2-role
echo "Done. Also: delete your Gemini API key at https://aistudio.google.com/apikey and tell your instructor."
