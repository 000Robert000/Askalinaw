# Shared settings, sourced by every script. Edit REGION if your class uses another one.
export REGION="${REGION:-ap-southeast-1}"
export AWS_DEFAULT_REGION="$REGION"
export PARAM_PREFIX="/askalinaw"
export REPO_DIR="/opt/askalinaw"
export LC_DIR="/opt/LibreChat"
export LOG_DIR="/var/log/askalinaw"
export METRIC_NS="Askalinaw"
mkdir -p "$LOG_DIR" 2>/dev/null || true

# BUCKET comes from Parameter Store (not a secret, but kept with the rest of the config)
if [ -z "${BUCKET:-}" ]; then
  BUCKET=$(aws ssm get-parameter --name "$PARAM_PREFIX/BUCKET" --query Parameter.Value --output text 2>/dev/null || true)
  export BUCKET
fi

log() {  # timestamped log line, also what proves automations ran unattended
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [$(basename "$0")] $*" | tee -a "$LOG_DIR/automation.log"
}
