#!/usr/bin/env bash
# Creates all AWS resources for Askalinaw. Run it in AWS CloudShell
# (the >_ icon at the top of the console), logged in as YOUR OWN IAM user.
#
#   1. Upload this repo's ZIP to CloudShell (Actions > Upload file), unzip, cd into it
#   2. TEAM_EMAIL=you@example.com GITHUB_REPO=https://github.com/you/askalinaw.git bash infra/01-create-aws.sh
#
# It only creates things whose names start with "askalinaw-", all tagged
# Project=SAM10, Team=Santiago-Dequiros, so you don't touch classmates' resources.
set -euo pipefail
: "${TEAM_EMAIL:?set TEAM_EMAIL=your-real-email}"
: "${GITHUB_REPO:?set GITHUB_REPO=https://github.com/you/askalinaw.git (public repo, no secrets in it)}"
REGION="${REGION:-ap-southeast-2}"; export AWS_DEFAULT_REGION="$REGION"
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
SUFFIX=$(echo "$ACCOUNT" | tail -c 5)
BUCKET="askalinaw-$SUFFIX-$(date +%s | tail -c 5)"
TAGS="Key=Project,Value=SAM10 Key=Team,Value=Santiago-Dequiros"
TAGSPEC="{Key=Project,Value=SAM10},{Key=Team,Value=Santiago-Dequiros}"
say() { echo -e "\n\033[1;32m== $* ==\033[0m"; }

say "1/8 S3 bucket $BUCKET (versioning, encryption, no public access, backup expiry 14 days)"
aws s3api create-bucket --bucket "$BUCKET" --create-bucket-configuration LocationConstraint="$REGION"
aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$BUCKET" --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-bucket-lifecycle-configuration --bucket "$BUCKET" --lifecycle-configuration \
  '{"Rules":[{"ID":"expire-backups","Status":"Enabled","Filter":{"Prefix":"backups/"},"Expiration":{"Days":14},"NoncurrentVersionExpiration":{"NoncurrentDays":14}}]}'
aws s3api put-bucket-tagging --bucket "$BUCKET" --tagging "TagSet=[$TAGSPEC]"
aws s3 cp content/kalinaw-handbook.md "s3://$BUCKET/content/kalinaw-handbook.md"

say "2/8 Parameter Store (secrets are SecureString)"
read -rsp "Paste your Gemini API key from https://aistudio.google.com/apikey (hidden): " GKEY; echo
put_secret() { aws ssm put-parameter --name "/askalinaw/$1" --type SecureString --value "$2" --overwrite >/dev/null; echo "  /askalinaw/$1 (SecureString)"; }
put_secret GOOGLE_KEY "$GKEY"; unset GKEY
put_secret CREDS_KEY "$(openssl rand -hex 32)"
put_secret CREDS_IV "$(openssl rand -hex 16)"
put_secret JWT_SECRET "$(openssl rand -hex 32)"
put_secret JWT_REFRESH_SECRET "$(openssl rand -hex 32)"
put_secret MEILI_MASTER_KEY "$(openssl rand -hex 16)"
aws ssm put-parameter --name /askalinaw/BUCKET --type String --value "$BUCKET" --overwrite >/dev/null

say "3/8 IAM role for the server (least privilege)"
aws iam create-role --role-name askalinaw-ec2-role --tags $TAGS \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
sed "s/BUCKET_NAME/$BUCKET/g; s/ACCOUNT_ID/$ACCOUNT/g; s/REGION/$REGION/g" infra/iam-policy.json > /tmp/policy.json
aws iam put-role-policy --role-name askalinaw-ec2-role --policy-name askalinaw-least-privilege --policy-document file:///tmp/policy.json
aws iam attach-role-policy --role-name askalinaw-ec2-role --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam attach-role-policy --role-name askalinaw-ec2-role --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
aws iam create-instance-profile --instance-profile-name askalinaw-ec2-profile >/dev/null
aws iam add-role-to-instance-profile --instance-profile-name askalinaw-ec2-profile --role-name askalinaw-ec2-role
sleep 10

say "4/8 Security group: only 80/443 open. NO SSH - we use Session Manager."
VPC=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)
SG=$(aws ec2 create-security-group --group-name askalinaw-web --description "Askalinaw web 80/443 only" \
     --vpc-id "$VPC" --tag-specifications "ResourceType=security-group,Tags=[$TAGSPEC]" --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG" --ip-permissions \
  'IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0}]' \
  'IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges=[{CidrIp=0.0.0.0/0}]' >/dev/null

say "5/8 Elastic IP + EC2 (t3.small, Amazon Linux 2023, encrypted 30 GB disk)"
EIP_ALLOC=$(aws ec2 allocate-address --tag-specifications "ResourceType=elastic-ip,Tags=[$TAGSPEC]" --query AllocationId --output text)
EIP=$(aws ec2 describe-addresses --allocation-ids "$EIP_ALLOC" --query 'Addresses[0].PublicIp' --output text)
DOMAIN="$(echo "$EIP" | tr . -).sslip.io"
aws ssm put-parameter --name /askalinaw/DOMAIN --type String --value "$DOMAIN" --overwrite >/dev/null
AMI=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query Parameter.Value --output text)
sed "s/REPLACE-WITH-IP.sslip.io/$DOMAIN/; s/REPLACE-WITH-TEAM-EMAIL/$TEAM_EMAIL/" infra/Caddyfile > /tmp/Caddyfile
aws ssm put-parameter --name /askalinaw/CADDYFILE --type String --value "$(cat /tmp/Caddyfile)" --overwrite >/dev/null
sed "s|__REPO_URL__|$GITHUB_REPO|; s|__REGION__|$REGION|" infra/02-server-setup.sh > /tmp/userdata.sh
IID=$(aws ec2 run-instances --image-id "$AMI" --instance-type t3.small \
  --iam-instance-profile Name=askalinaw-ec2-profile --security-group-ids "$SG" \
  --metadata-options HttpTokens=required,HttpPutResponseHopLimit=2 \
  --block-device-mappings 'DeviceName=/dev/xvda,Ebs={VolumeSize=30,VolumeType=gp3,Encrypted=true}' \
  --user-data file:///tmp/userdata.sh \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=askalinaw-server},$TAGSPEC]" "ResourceType=volume,Tags=[$TAGSPEC]" \
  --query 'Instances[0].InstanceId' --output text)
aws ec2 wait instance-running --instance-ids "$IID"
aws ec2 associate-address --instance-id "$IID" --allocation-id "$EIP_ALLOC" >/dev/null

say "6/8 SNS topic -> $TEAM_EMAIL  (CLICK THE CONFIRM LINK IN YOUR EMAIL)"
TOPIC=$(aws sns create-topic --name askalinaw-alerts --tags $TAGS --query TopicArn --output text)
aws sns subscribe --topic-arn "$TOPIC" --protocol email --notification-endpoint "$TEAM_EMAIL" >/dev/null

say "7/8 Alarms, log metric filters and dashboard"
INSTANCE_ID="$IID" TOPIC="$TOPIC" bash infra/03-monitoring.sh

say "8/8 CloudTrail (skipped if the class account already has one)"
if [ "$(aws cloudtrail describe-trails --query 'length(trailList)' --output text)" = "0" ]; then
  echo "  No trail found - create one in the console (CloudTrail > Create trail) or ask your instructor."
else
  aws cloudtrail describe-trails --query 'trailList[].[Name,HomeRegion,IsMultiRegionTrail]' --output table
fi

cat <<EOF

DONE. Save these:
  Instance:  $IID
  Bucket:    $BUCKET
  URL:       https://$DOMAIN   (ready ~10 minutes after this, once the server finishes installing)
  Alerts:    $TOPIC  -> confirm the email from AWS Notifications!
EOF
