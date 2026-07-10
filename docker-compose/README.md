# Guardium VA Scanner — Use Case 2: Docker Compose

Deploy the Guardium Vulnerability Assessment Scanner on a **plain VM or server** using Docker Compose — no Kubernetes cluster required.

> **Use Case 1 (Helm)** is recommended for production environments with Kubernetes, Amazon EKS, or OpenShift.
> See the [main README](../README.md) for that guide.

---

## When to Use Docker Compose

| | Use Case 1 — Helm | Use Case 2 — Docker Compose |
|---|---|---|
| **Platform** | Kubernetes / EKS / OpenShift | Plain VM or server |
| **Scaling** | Auto-scaling (HPA, 2–10 replicas) | Manual (`--scale`) |
| **Secrets** | Kubernetes Secrets (auto-created from `values.yaml`) | `.env` file + files on disk (created manually) |
| **Certificate** | Base64 value in `values.yaml` → K8s Secret → mounted automatically | PEM file created manually and bind-mounted |
| **Registry auth** | K8s pull secret (auto-created from `values.yaml`) | `docker login` run manually |
| **Best for** | Production, cloud-native | POC, on-prem VM, simple setups |

---

## How Helm Secrets Map to Manual Steps

In Helm, running `helm install` **automatically** creates three Kubernetes Secrets from your `values.yaml`:

| What Helm creates automatically | What YOU must do manually (docker-compose) |
|---|---|
| **`va-scanner-credentials`** secret — GDP host, port, API key, agent name | Fill in `.env` file (Step 2) |
| **`va-cert`** secret — GDP SSL certificate stored as `ca.crt`, mounted as `vascanner.pem` | Fetch cert from GDP server, decode to `certs/vascanner.pem` (Step 3) |
| **`ibm-entitlement-key`** secret — registry credentials for pulling the image | Run `docker login cp.icr.io` (Step 1) |
| ConfigMap `guardAgent.properties` — generated from Helm template | Already provided in `config/guardAgent.properties` — no action needed ✅ |

The `docker-compose.yml` then bind-mounts these manually-created files into the container at the same paths the Helm chart mounts them:

```
certs/vascanner.pem   →  /var/vascanner/certs/vascanner.pem   (ro)
config/guardAgent.properties  →  /var/vascanner/etc/guardAgent_static.properties  (ro)
```

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                         VM / Server                              │
│                                                                  │
│  docker-compose/                                                 │
│  ├── .env                      ← GDP credentials (manual)       │
│  ├── certs/vascanner.pem       ← SSL cert (manual decode)       │
│  └── config/guardAgent.properties  ← provided ✅                │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  Docker Compose                                           │  │
│  │                                                           │  │
│  │  scanner-1 ──┐                                           │  │
│  │  scanner-2 ──┼──► GDP Server :8443 (HTTPS)              │  │
│  │  scanner-3 ──┘                                           │  │
│  │                                                           │  │
│  │  Volumes (bind-mounted from host):                       │  │
│  │  • certs/vascanner.pem → /var/vascanner/certs/           │  │
│  │  • config/guardAgent.properties → /var/vascanner/etc/    │  │
│  └───────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

- **Docker Engine 20.10+** with the `docker compose` plugin (v2)
  ```bash
  docker compose version   # must show v2.x
  ```
- **`openssl`** — for fetching and verifying the GDP certificate
- **IBM Entitlement Key** — from [IBM Container Library](https://myibm.ibm.com/products-services/containerlibrary)
- **GDP Server** reachable from this VM on port `8443`
- **GDP CLI access** — to generate an API key on the GDP server

---

## Complete Setup Guide

### Step 1 — Authenticate with the Container Registry

Helm auto-creates the `ibm-entitlement-key` Kubernetes pull secret from your `registry.*` values.
With docker-compose, you authenticate once at the Docker daemon level instead:

```bash
docker login cp.icr.io -u cp -p <YOUR_IBM_ENTITLEMENT_KEY>
```

Your IBM Entitlement Key is available at [myibm.ibm.com/products-services/containerlibrary](https://myibm.ibm.com/products-services/containerlibrary) — click **Copy entitlement key**.

Verify the login succeeded:
```bash
docker pull cp.icr.io/cp/ibm-guardium-data-security-center/guardium/vascanner-12.2.0/va-scanner:vascanner-v12.2.0
```

---

### Step 2 — Create the Credentials File (`.env`)

Helm auto-creates the `va-scanner-credentials` Kubernetes Secret from your `gdp.*` values.
With docker-compose, you create a `.env` file that is loaded directly into the container.

**2.1 — Copy the template:**
```bash
cp .env.example .env
```

**2.2 — Generate your GDP API key** on the GDP server:
```bash
# Run this ON the GDP server
grdapi create_api_key name=vm-va-scanner-01
```
Copy the **Encoded API key** value from the output.

**2.3 — Check your GDP certificate hostname** (you need this for `GDP_HOST`):
```bash
openssl s_client -connect YOUR_GDP_SERVER_IP:8443 -showcerts </dev/null 2>/dev/null \
  | openssl x509 -noout -text | grep -A2 "Subject Alternative Name"
```
Example output:
```
X509v3 Subject Alternative Name:
    DNS:guard.yourcompany.com
```
Use the DNS name from the certificate as `GDP_HOST` — **not** the server IP.

**2.4 — Fill in `.env`:**

Open `.env` and set these required fields:

```ini
# Mirrors gdp.host in values.yaml — MUST match the certificate hostname
GDP_HOST=guard.yourcompany.com

# Mirrors gdp.hostPort / gdp.agentPort
GDP_HOST_PORT=8443
GDP_AGENT_PORT=8443

# Mirrors gdp.apiKey — base64 encoded key from grdapi
GDP_API_KEY=eyJh...your-encoded-key...

# Mirrors gdp.agentName
GDP_AGENT_NAME=vm-va-scanner-01

# Mirrors vaScannerPollInMins — keeps scanner running between jobs (recommended: 5–15)
VA_SCANNER_POLL_IN_MINS=5

# Mirrors image.repository / image.tag
IMAGE_REPOSITORY=cp.icr.io/cp/ibm-guardium-data-security-center/guardium/vascanner-12.2.0/va-scanner
IMAGE_TAG=vascanner-v12.2.0
```

**2.5 — Check if you need a host alias** (mirrors `hostAliases` in values.yaml):

Only required when the `GDP_HOST` certificate hostname does not resolve to the correct IP via DNS.

```bash
# Does GDP_HOST resolve to the right IP?
nslookup guard.yourcompany.com

# If it doesn't resolve, set the real server IP:
# GDP_HOST_ALIAS_IP=52.21.60.157
```

Leave `GDP_HOST_ALIAS_IP` blank if DNS already resolves correctly.

> **Security:** Add `.env` to your `.gitignore` immediately:
> ```bash
> echo ".env" >> .gitignore
> ```

---

### Step 3 — Create the SSL Certificate File

Helm auto-creates the `va-cert` Kubernetes Secret from the `gdp.certBase64` value in your `values.yaml`,
then mounts it into each pod as `/var/vascanner/certs/vascanner.pem`.

With docker-compose, you create the PEM file manually and it is bind-mounted to the same path.

**3.1 — Fetch the GDP certificate** (run from this VM or any machine that can reach the GDP server):

```bash
openssl s_client -connect YOUR_GDP_SERVER_IP:8443 -showcerts </dev/null 2>/dev/null \
  | openssl x509 -outform PEM > certs/vascanner.pem
```

> This is the same certificate data as `gdp.certBase64` in `values.yaml` — just decoded directly to a file instead of going through base64 encoding → K8s Secret → volume mount.

**3.2 — Verify the certificate was saved correctly:**

```bash
openssl x509 -in certs/vascanner.pem -noout -subject -dates
```

Expected output:
```
subject=CN=guard.yourcompany.com
notBefore=Jan  1 00:00:00 2024 GMT
notAfter=Jan  1 00:00:00 2026 GMT
```

**3.3 — Confirm the hostname matches your `GDP_HOST`:**
```bash
openssl x509 -in certs/vascanner.pem -noout -text | grep -A2 "Subject Alternative Name"
```
The DNS name shown **must exactly match** the `GDP_HOST` value in your `.env`.

> **Security:** Add `certs/*.pem` to your `.gitignore`:
> ```bash
> echo "certs/*.pem" >> .gitignore
> ```

---

### Step 4 — Verify the Config File

The `config/guardAgent.properties` file is already provided in this directory — it mirrors the Helm
`configmap.yaml` exactly. The VA Scanner application resolves the `${...}` tokens at runtime from
environment variables, the same way it does in Kubernetes.

**No action is required.** Just confirm the file is present:

```bash
cat config/guardAgent.properties
```

Expected output:
```ini
[GDPHost_0]=
gdp.host=${GDP_HOST}
gdp.host.port=${GDP_HOST_PORT}
client.apiKey=${CLIENT_API_KEY}
...
```

---

### Step 5 — Run

Start 3 scanner replicas (mirrors `replicaCount: 3` in values.yaml):

```bash
docker compose up -d --scale scanner=3
```

Or start a single replica for testing:

```bash
docker compose up -d
```

---

### Step 6 — Verify

**Check all containers are running:**
```bash
docker compose ps
```

Expected output:
```
NAME                      IMAGE                           STATUS         
docker-compose-scanner-1  cp.icr.io/.../va-scanner:...   Up 2 minutes   
docker-compose-scanner-2  cp.icr.io/.../va-scanner:...   Up 2 minutes   
docker-compose-scanner-3  cp.icr.io/.../va-scanner:...   Up 2 minutes   
```

**Tail the logs:**
```bash
docker compose logs -f scanner
```

**Confirm GDP connection** — look for:
```
Connected to GDP server: guard.yourcompany.com:8443
```

---

## Common Operations

### View Logs
```bash
# All replicas
docker compose logs -f scanner

# Single replica by index
docker compose logs -f --index 1 scanner

# Last 100 lines
docker compose logs --tail=100 scanner
```

### Scale Replicas
```bash
docker compose up -d --scale scanner=5   # scale up
docker compose up -d --scale scanner=1   # scale down
```

> Docker Compose does not support auto-scaling. For CPU/memory-based dynamic scaling, use [Use Case 1 — Helm](../README.md).

### Update the Scanner Image

Update `IMAGE_TAG` in your `.env`, then:
```bash
docker compose pull
docker compose up -d --scale scanner=3
```

### Restart
```bash
docker compose restart scanner
```

### Stop (preserves containers)
```bash
docker compose stop
```

### Remove All Containers
```bash
docker compose down
```

---

## File Structure

```
docker-compose/
├── docker-compose.yml              # Service definition — edit only for advanced config
├── .env.example                    # Configuration template — copy to .env and fill in
├── .env                            # YOUR credentials — never commit this file ⚠️
├── config/
│   └── guardAgent.properties      # Static scanner config — provided, no edit needed ✅
└── certs/
    ├── README.txt                  # Instructions
    └── vascanner.pem               # YOUR decoded certificate — create in Step 3 ⚠️
```

### What is bind-mounted into the container

| Host path | Container path | How Helm does it |
|---|---|---|
| `certs/vascanner.pem` | `/var/vascanner/certs/vascanner.pem` | K8s Secret `va-cert` mounted as volume |
| `config/guardAgent.properties` | `/var/vascanner/etc/guardAgent_static.properties` | ConfigMap `va-scanner-config` mounted as volume |
| `.env` (env vars) | Container environment | K8s Secret `va-scanner-credentials` injected as `envFrom` |

---

## Configuration Reference

All configuration lives in `.env`. Fields mirror `values.yaml` in the Helm chart.

### Required Fields

| `.env` Field | Mirrors `values.yaml` | Description |
|---|---|---|
| `IMAGE_REPOSITORY` | `image.repository` | Docker image path |
| `IMAGE_TAG` | `image.tag` | Docker image tag |
| `GDP_HOST` | `gdp.host` | GDP certificate hostname (**must match cert SAN**) |
| `GDP_HOST_PORT` | `gdp.hostPort` | GDP host port (default: `8443`) |
| `GDP_AGENT_PORT` | `gdp.agentPort` | GDP agent port (default: `8443`) |
| `GDP_API_KEY` | `gdp.apiKey` | Base64-encoded API key from `grdapi` |
| `GDP_AGENT_NAME` | `gdp.agentName` | Unique scanner name |
| `VA_SCANNER_POLL_IN_MINS` | `vaScannerPollInMins` | Polling interval in minutes (recommended: 5) |

### Optional Fields

| `.env` Field | Mirrors `values.yaml` | Description |
|---|---|---|
| `GDP_HOST_ALIAS_IP` | `hostAliases[].ip` | GDP server IP when DNS doesn't resolve `GDP_HOST` |
| `GDP_USERNAME` | `gdp.username` | Alternative auth username |
| `GDP_CLIENT_ID` | `gdp.clientId` | OAuth client ID |
| `GDP_CLIENT_PASSWORD` | `gdp.clientPassword` | OAuth client password |
| `GDP_CLIENT_SECRET` | `gdp.clientSecret` | OAuth client secret |
| `GDP_HTTP_PROXY_IP` | `gdp.httpProxyIp` | Proxy IP |
| `GDP_HTTP_PROXY_PORT` | `gdp.httpProxyPort` | Proxy port |
| `GDP_CLOUD_RESOURCE_NAME` | `gdp.cloudResourceName` | Cloud resource name |
| `RESOURCES_LIMITS_CPU` | `resources.limits.cpu` | CPU limit (default: `1.0`) |
| `RESOURCES_LIMITS_MEMORY` | `resources.limits.memory` | Memory limit (default: `2g`) |
| `RESOURCES_REQUESTS_CPU` | `resources.requests.cpu` | CPU reservation (default: `0.25`) |
| `RESOURCES_REQUESTS_MEMORY` | `resources.requests.memory` | Memory reservation (default: `512m`) |

---

## Troubleshooting

### Certificate Hostname Mismatch

**Symptom:** Scanner logs show `PKIX path building failed` or `hostname mismatch`.

**Cause:** `GDP_HOST` in `.env` does not match the hostname in `certs/vascanner.pem`.

**Fix:**
```bash
# Check what hostname is in your cert
openssl x509 -in certs/vascanner.pem -noout -text | grep -A2 "Subject Alternative Name"

# Set GDP_HOST in .env to match exactly, then restart
docker compose up -d --scale scanner=3
```

---

### Container Exits Immediately

**Symptom:** Containers show `Exited (0)` shortly after starting.

**Cause:** `VA_SCANNER_POLL_IN_MINS` is `0` or unset — scanner exits after one run cycle.

**Fix:** Set a non-zero value in `.env`:
```ini
VA_SCANNER_POLL_IN_MINS=5
```
Then: `docker compose up -d --scale scanner=3`

---

### Image Pull Failure

**Symptom:** `pull access denied` or `unauthorized`.

**Fix:**
```bash
docker login cp.icr.io -u cp -p <YOUR_IBM_ENTITLEMENT_KEY>
docker compose up -d --scale scanner=3
```

---

### Cannot Connect to GDP (Connection Refused / Timeout)

**Symptom:** Logs show `Connection refused` or timeout on port `8443`.

**Checklist:**
```bash
# 1. Can this VM reach the GDP server?
nc -zv YOUR_GDP_SERVER_IP 8443

# 2. Does GDP_HOST resolve to the right IP?
nslookup $(grep GDP_HOST .env | cut -d= -f2)

# 3. If DNS doesn't resolve, set the IP manually in .env:
#    GDP_HOST_ALIAS_IP=52.21.60.157
```

---

### Certificate File Missing

**Symptom:** Scanner logs show `No such file` for `/var/vascanner/certs/vascanner.pem`.

**Fix:** Re-run Step 3:
```bash
openssl s_client -connect YOUR_GDP_SERVER_IP:8443 -showcerts </dev/null 2>/dev/null \
  | openssl x509 -outform PEM > certs/vascanner.pem

openssl x509 -in certs/vascanner.pem -noout -subject   # verify
docker compose up -d --scale scanner=3
```
