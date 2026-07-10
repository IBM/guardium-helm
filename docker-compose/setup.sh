#!/usr/bin/env bash
# =============================================================================
# Guardium VA Scanner — Docker Compose Setup Helper
# =============================================================================
# This script automates the manual preparation steps that Helm handles
# automatically via Kubernetes Secrets and ConfigMaps.
#
# What it does (mirrors what `helm install` creates automatically):
#   Step 1 — Validates Docker and docker compose are installed
#   Step 2 — Creates .env from .env.example if not already present
#   Step 3 — Fetches the GDP SSL certificate and writes certs/vascanner.pem
#            (mirrors: Helm Secret `va-cert` from gdp.certBase64 in values.yaml)
#   Step 4 — Validates the certificate hostname matches GDP_HOST in .env
#            (mirrors: Helm hostAliases validation)
#   Step 5 — Verifies docker login for the container registry
#            (mirrors: Helm Secret `ibm-entitlement-key` from registry.* in values.yaml)
#   Step 6 — Confirms config/guardAgent.properties is present
#            (mirrors: Helm ConfigMap from configmap.yaml)
#
# Usage:
#   chmod +x setup.sh
#   ./setup.sh
#
# To only fetch the certificate (re-run Step 3 alone):
#   ./setup.sh --cert-only
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
ENV_EXAMPLE="${SCRIPT_DIR}/.env.example"
CERT_FILE="${SCRIPT_DIR}/certs/vascanner.pem"
CONFIG_FILE="${SCRIPT_DIR}/config/guardAgent.properties"

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()     { error "$*"; exit 1; }

# ── Argument parsing ──────────────────────────────────────────────────────────
CERT_ONLY=false
for arg in "$@"; do
  [[ "$arg" == "--cert-only" ]] && CERT_ONLY=true
done

# ── Helper: read a value from .env ────────────────────────────────────────────
env_val() {
  grep -E "^${1}=" "${ENV_FILE}" 2>/dev/null | cut -d= -f2- | tr -d '"' | tr -d "'" | xargs
}

echo ""
echo "============================================================"
echo "  Guardium VA Scanner — Docker Compose Setup"
echo "  (Use Case 2: VM / standalone deployment)"
echo "============================================================"
echo ""

# =============================================================================
# STEP 1 — Check prerequisites
# =============================================================================
if [[ "$CERT_ONLY" == false ]]; then
  info "Step 1: Checking prerequisites..."

  command -v docker >/dev/null 2>&1 || die "Docker is not installed. Install Docker Engine 20.10+ first."
  docker compose version >/dev/null 2>&1 || die "'docker compose' plugin not found. Install Docker Compose v2."
  command -v openssl >/dev/null 2>&1 || die "openssl is not installed."

  success "Docker $(docker --version | awk '{print $3}' | tr -d ',') and docker compose $(docker compose version --short) found."
  echo ""
fi

# =============================================================================
# STEP 2 — Create .env from template
# =============================================================================
if [[ "$CERT_ONLY" == false ]]; then
  info "Step 2: Checking .env file..."

  if [[ ! -f "${ENV_FILE}" ]]; then
    if [[ ! -f "${ENV_EXAMPLE}" ]]; then
      die ".env.example not found at ${ENV_EXAMPLE}"
    fi
    cp "${ENV_EXAMPLE}" "${ENV_FILE}"
    warn ".env created from .env.example"
    warn "IMPORTANT: Open .env and fill in all required values before continuing."
    warn "  Required: GDP_HOST, GDP_API_KEY, GDP_AGENT_NAME, IMAGE_REPOSITORY, IMAGE_TAG"
    echo ""
    echo "  After editing .env, re-run this script:"
    echo "    ./setup.sh"
    echo ""
    exit 0
  fi

  # Validate required fields are filled
  MISSING=()
  for field in GDP_HOST GDP_HOST_PORT GDP_AGENT_PORT GDP_API_KEY GDP_AGENT_NAME IMAGE_REPOSITORY IMAGE_TAG; do
    val=$(env_val "$field")
    if [[ -z "$val" || "$val" == *"REPLACE_WITH"* || "$val" == *"your-"* ]]; then
      MISSING+=("$field")
    fi
  done

  if [[ ${#MISSING[@]} -gt 0 ]]; then
    error "The following required fields are not set in .env:"
    for f in "${MISSING[@]}"; do echo "    - $f"; done
    echo ""
    die "Fill in all required fields in .env, then re-run this script."
  fi

  success ".env is present and required fields are set."
  echo ""
fi

# =============================================================================
# STEP 3 — Fetch GDP SSL certificate → certs/vascanner.pem
# (Mirrors: Helm Secret `va-cert` created from gdp.certBase64 in values.yaml)
# =============================================================================
GDP_HOST=$(env_val "GDP_HOST")
GDP_HOST_PORT=$(env_val "GDP_HOST_PORT")
GDP_HOST_ALIAS_IP=$(env_val "GDP_HOST_ALIAS_IP")

# Determine the server address to connect to (IP if alias set, hostname otherwise)
CONNECT_TARGET="${GDP_HOST_ALIAS_IP:-${GDP_HOST}}"
[[ -z "${CONNECT_TARGET}" ]] && CONNECT_TARGET="${GDP_HOST}"

info "Step 3: Fetching GDP SSL certificate from ${CONNECT_TARGET}:${GDP_HOST_PORT}..."
info "  (Mirrors: Helm Secret 'va-cert' from gdp.certBase64 in values.yaml)"

mkdir -p "${SCRIPT_DIR}/certs"

# Test connectivity first
if ! timeout 5 bash -c "echo >/dev/tcp/${CONNECT_TARGET}/${GDP_HOST_PORT}" 2>/dev/null; then
  die "Cannot reach ${CONNECT_TARGET}:${GDP_HOST_PORT}. Verify the GDP server is running and port is open."
fi

# Fetch the certificate
openssl s_client \
  -connect "${CONNECT_TARGET}:${GDP_HOST_PORT}" \
  -showcerts \
  </dev/null 2>/dev/null \
  | openssl x509 -outform PEM > "${CERT_FILE}"

if [[ ! -s "${CERT_FILE}" ]]; then
  die "Certificate file is empty. Failed to fetch from ${CONNECT_TARGET}:${GDP_HOST_PORT}."
fi

success "Certificate saved to certs/vascanner.pem"
echo ""

# =============================================================================
# STEP 4 — Validate certificate hostname matches GDP_HOST
# (Mirrors: Helm hostAliases — ensures the cert SAN matches gdp.host in values.yaml)
# =============================================================================
info "Step 4: Validating certificate hostname matches GDP_HOST=${GDP_HOST}..."
info "  (Mirrors: Helm hostAliases validation — gdp.host must match cert SAN)"

CERT_SANS=$(openssl x509 -in "${CERT_FILE}" -noout -text 2>/dev/null | grep -A2 "Subject Alternative Name" | grep "DNS:" | tr ',' '\n' | sed 's/.*DNS://g' | xargs)
CERT_CN=$(openssl x509 -in "${CERT_FILE}" -noout -subject 2>/dev/null | sed 's/.*CN=//;s/,.*//')

CERT_VALID=false
for san in $CERT_SANS; do
  [[ "$san" == "$GDP_HOST" ]] && CERT_VALID=true && break
done
[[ "$CERT_CN" == "$GDP_HOST" ]] && CERT_VALID=true

if [[ "$CERT_VALID" == false ]]; then
  warn "Certificate hostname mismatch!"
  warn "  GDP_HOST in .env:  ${GDP_HOST}"
  warn "  Certificate SANs:  ${CERT_SANS:-none}"
  warn "  Certificate CN:    ${CERT_CN:-none}"
  warn ""
  warn "Options:"
  warn "  1. Change GDP_HOST in .env to match one of: ${CERT_SANS:-${CERT_CN}}"
  warn "  2. If the server's IP differs from GDP_HOST, set GDP_HOST_ALIAS_IP=<server-ip> in .env"
  warn "     This mirrors the Helm hostAliases configuration."
  echo ""
else
  success "Certificate hostname '${GDP_HOST}' is valid."

  EXPIRY=$(openssl x509 -in "${CERT_FILE}" -noout -enddate 2>/dev/null | cut -d= -f2)
  success "Certificate expires: ${EXPIRY}"
  echo ""
fi

if [[ "$CERT_ONLY" == true ]]; then
  success "Certificate setup complete. Run 'docker compose up -d --scale scanner=3' when ready."
  exit 0
fi

# =============================================================================
# STEP 5 — Verify container registry authentication
# (Mirrors: Helm Secret `ibm-entitlement-key` from registry.* in values.yaml)
# =============================================================================
info "Step 5: Checking container registry authentication..."
info "  (Mirrors: Helm Secret 'ibm-entitlement-key' from registry.* in values.yaml)"

REGISTRY_SERVER=$(env_val "REGISTRY_SERVER")
REGISTRY_SERVER="${REGISTRY_SERVER:-cp.icr.io}"
IMAGE_REPO=$(env_val "IMAGE_REPOSITORY")

# Check if docker config has credentials for this registry
if docker pull "${IMAGE_REPO}:$(env_val 'IMAGE_TAG')" --quiet >/dev/null 2>&1; then
  success "Registry authentication verified — image pull succeeded."
else
  warn "Could not pull image. You may need to authenticate:"
  warn "  docker login ${REGISTRY_SERVER} -u cp -p <YOUR_IBM_ENTITLEMENT_KEY>"
  warn "  Get your key at: https://myibm.ibm.com/products-services/containerlibrary"
fi
echo ""

# =============================================================================
# STEP 6 — Verify config/guardAgent.properties
# (Mirrors: Helm ConfigMap from configmap.yaml — provided, no action needed)
# =============================================================================
info "Step 6: Checking config/guardAgent.properties..."
info "  (Mirrors: Helm ConfigMap 'va-scanner-config' from configmap.yaml — provided ✅)"

if [[ ! -f "${CONFIG_FILE}" ]]; then
  die "config/guardAgent.properties not found at ${CONFIG_FILE}. This file should be included in the repository."
fi

success "config/guardAgent.properties is present."
echo ""

# =============================================================================
# Summary
# =============================================================================
echo "============================================================"
echo -e "  ${GREEN}Setup complete!${NC}"
echo "============================================================"
echo ""
echo "  Manually created (what Helm would auto-create):"
echo "    ✅  .env                        ← mirrors Kubernetes Secret va-scanner-credentials"
echo "    ✅  certs/vascanner.pem         ← mirrors Kubernetes Secret va-cert"
echo "    ✅  docker login                ← mirrors Kubernetes Secret ibm-entitlement-key"
echo "    ✅  config/guardAgent.properties ← mirrors Kubernetes ConfigMap (provided)"
echo ""
echo "  To start the scanner (3 replicas, mirrors replicaCount: 3 in values.yaml):"
echo ""
echo "    docker compose up -d --scale scanner=3"
echo ""
echo "  To view logs:"
echo ""
echo "    docker compose logs -f scanner"
echo ""
