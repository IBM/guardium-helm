# Guardium VA Scanner Helm Chart

Production-ready Helm chart for deploying Guardium Vulnerability Assessment Scanner on Kubernetes.


## Overview

This Helm chart deploys the Guardium Vulnerability Assessment (VA) Scanner on Kubernetes/EKS. The scanner connects to your Guardium Data Protection (GDP) server to perform security assessments on your databases.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          AWS Cloud Environment                           │
│                                                                          │
│  ┌────────────────────┐         ┌─────────────────────────────────┐   │
│  │   Amazon RDS       │         │      Amazon EKS Cluster          │   │
│  │  ┌──────────────┐  │         │  ┌───────────────────────────┐  │   │
│  │  │   Oracle DB  │  │         │  │      va-scanner           │  │   │
│  │  │   MySQL DB   │◄─┼─────────┼──┤   (Helm Deployment)       │  │   │
│  │  │ PostgreSQL   │  │         │  │                           │  │   │
│  │  │     etc.     │  │         │  │  • Pods (2-10 replicas)   │  │   │
│  │  └──────────────┘  │         │  │  • Auto-scaling (HPA)     │  │   │
│  └────────────────────┘         │  │  • Secrets Management     │  │   │
│           ▲                      │  └───────────────────────────┘  │   │
│           │                      │              │                   │   │
│           │                      └──────────────┼───────────────────┘   │
│           │                                     │                       │
│           │                                     │ HTTPS:8443            │
│           │                                     ▼                       │
│           │                      ┌─────────────────────────────────┐   │
│           │                      │    GDP Server (EC2/VM)          │   │
│           │                      │  ┌───────────────────────────┐  │   │
│           └──────────────────────┼──┤  Guardium Data Protection │  │   │
│                Assessment         │  │                           │  │   │
│                 Results           │  │  • Assessment Builder     │  │   │
│                                   │  │  • Data Sources Config    │  │   │
│                                   │  │  • Security Tests         │  │   │
│                                   │  │  • API Key Management     │  │   │
│                                   │  └───────────────────────────┘  │   │
│                                   └─────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘

                    ┌──────────────────────────────┐
                    │   Your Local Machine         │
                    │                              │
                    │  • kubectl (EKS access)      │
                    │  • Helm CLI                  │
                    │  • values.yaml config        │
                    └──────────────────────────────┘
```

### Component Roles

| Component | Purpose | Setup Phase |
|-----------|---------|-------------|
| **GDP Server** | Central management server for security assessments | Step 1 |
| **Database (RDS)** | Target database to be assessed for vulnerabilities | Step 2 |
| **EKS Cluster** | Kubernetes environment hosting the VA Scanner | Step 3 |
| **VA Scanner (Helm)** | Automated scanner pods that execute assessments | Step 6 |
| **GDP Data Source** | Configuration linking GDP to your database | Step 4 |
| **GDP Assessment** | Security test definitions and schedules | Step 5 |

### How It Works

1. **GDP Server** manages assessment configurations and stores results
2. **Database** is registered as a data source in GDP
3. **VA Scanner pods** (deployed via Helm) connect to GDP and receive assessment tasks
4. **Scanners execute tests** against the database through GDP
5. **Results** are sent back to GDP for analysis and reporting
6. **Helm** automates the deployment, scaling, and management of scanner pods

> **Note:** While Helm deployment (Step 6) is the final step, it's the key automation piece that enables continuous, scalable vulnerability assessments across your database infrastructure.

---

## Complete Setup Guide

Follow these steps in order to successfully deploy and configure the VA Scanner:

---

### Step 1: Deploy GDP Server 🖥️

**⚠️ Critical Requirement:** The GDP server must be deployed in an environment where port 8443 is accessible from non-IBM addresses.

**Recommended Approach:**
- ✅ Deploy GDP on **AWS EC2** (or another public cloud provider)
- ✅ Ensure GDP server's **port 8443** is accessible from your EKS cluster
- ❌ **Avoid IBM Cloud** environments - they may have network restrictions preventing external access

**AWS EC2 Deployment Example:**
```bash
# 1. Launch EC2 instance with appropriate instance type
# 2. Configure Security Group to allow inbound traffic on port 8443
# 3. Install and configure Guardium Data Protection
# 4. Verify GDP is accessible: https://your-gdp-ip:8443
```

**Security Group Configuration:**
- Inbound Rule: TCP port 8443 from your EKS cluster CIDR or security group
- Outbound Rule: Allow all (for database connectivity)

---

### Step 2: Create Database on Cloud Environment 🗄️

Create a database instance in your cloud environment (e.g., AWS RDS) that will be assessed for vulnerabilities.

**AWS RDS Example:**
```bash
# Create RDS instance via AWS Console or CLI
# Important: Note down these connection details:
```

**Required Information:**
- 📍 **Database endpoint** (e.g., `mydb.abc123.us-east-1.rds.amazonaws.com`)
- 🔌 **Port** (1521 for Oracle, 3306 for MySQL, 5432 for PostgreSQL)
- 🏷️ **Database name/Service name**
- 👤 **Master username**
- 🔑 **Master password**

**Supported Database Types:**
- ✅ Oracle Database
- ✅ MySQL / MariaDB
- ✅ PostgreSQL
- ✅ Microsoft SQL Server
- ✅ IBM DB2
- ✅ MongoDB
- ✅ And other Guardium-supported databases

**Network Configuration:**
- Ensure database security group allows connections from GDP server
- For RDS: Enable public accessibility or use VPC peering if needed

---

### Step 3: Setup EKS Cluster ☸️

Create and configure your Amazon EKS cluster with proper permissions for deploying the VA Scanner.

#### 3.1 Create EKS Cluster

**Using eksctl (Recommended):**
```bash
eksctl create cluster \
  --name va-scanner-cluster \
  --region us-east-1 \
  --nodegroup-name standard-workers \
  --node-type t3.medium \
  --nodes 3 \
  --nodes-min 2 \
  --nodes-max 4 \
  --managed
```

**Or use AWS Console:**

<img width="1580" alt="EKS Cluster Creation" src="https://github.ibm.com/user-attachments/assets/3244636f-4368-4c55-8ea2-a3c436aaae54" />

#### 3.2 Configure kubectl Access

```bash
# Update kubeconfig to access your cluster
aws eks update-kubeconfig --region us-east-1 --name va-scanner-cluster

# Verify connection
kubectl get nodes
```

#### 3.3 Verify Authentication

```bash
# Check current context
kubectl config current-context
# Expected output: arn:aws:eks:us-east-1:ACCOUNT_ID:cluster/va-scanner-cluster
```

```bash
# Verify cluster info
kubectl cluster-info
# Expected output:
# Kubernetes control plane is running at https://...
# CoreDNS is running at https://...
```

#### 3.4 Create Namespace

```bash
# Create dedicated namespace for VA Scanner
kubectl create namespace va-scanner

# Verify namespace creation
kubectl get namespaces | grep va-scanner
```

#### 3.5 Verify Permissions

Ensure you have sufficient RBAC permissions:

```bash
# Test required permissions
kubectl auth can-i create deployments -n va-scanner      # Should return: yes
kubectl auth can-i create secrets -n va-scanner          # Should return: yes
kubectl auth can-i create serviceaccounts -n va-scanner  # Should return: yes
kubectl auth can-i create hpa -n va-scanner              # Should return: yes
```


---

### Step 4: Configure Data Source in GDP 🔗

Connect your database to the GDP system so it can be assessed for vulnerabilities.

#### 4.1 Access GDP Console

Open your browser and navigate to:
```
https://your-gdp-server:8443
```
Login with your GDP administrator credentials.

#### 4.2 Add Data Source

Follow these steps in the GDP console:

1. **Navigate** to **Data Sources** section
2. **Click** the **➕ Add Data Source** button
3. **Select** your database type:
   - Oracle Database
   - MySQL
   - PostgreSQL
   - SQL Server
   - DB2
   - MongoDB
   - etc.

4. **Enter connection details:**

| Field | Description | Example |
|-------|-------------|---------|
| **Host** | Database endpoint | `mydb.abc123.us-east-1.rds.amazonaws.com` |
| **Port** | Database port | `1521` (Oracle), `3306` (MySQL), `5432` (PostgreSQL) |
| **Database/Service Name** | Database identifier | `ORCL`, `mydb` |
| **Username** | Database user | `admin` |
| **Password** | Database password | `your-secure-password` |

5. **Click** **Test Connection** to verify connectivity
6. **Click** **Save** to store the data source

<img width="1680" alt="GDP Data Source Configuration" src="https://github.ibm.com/user-attachments/assets/c2b97c31-b60d-4d7f-a2f6-23e3b296c680" />

**✅ Success Indicator:** You should see "Connection successful" message before saving.

---

### Step 5: Create Security Assessment in GDP 🔍

Configure the vulnerability assessment tests that will run on your database.

#### 5.1 Navigate to Assessment Builder

1. Log into GDP console
2. Navigate to **Assessment Builder** section

#### 5.2 Create New Assessment

1. **Click** the **➕ Plus** button to create a new assessment
2. **Enter** a descriptive name (e.g., "Oracle Production DB Assessment")
3. **Click** **Create**

#### 5.3 Add Data Source to Assessment

1. In the assessment configuration page, **click** **➕ Add Data Source**
2. **Select** the data source you created in Step 4
3. **Click** **Save**

<img width="1603" alt="Adding Data Source to Assessment" src="https://github.ibm.com/user-attachments/assets/fbb80ac4-7834-4a15-b0a0-3f866befecd9" />

<img width="1473" alt="Data Source Selection" src="https://github.ibm.com/user-attachments/assets/bfe2dd80-c71c-4cc6-9db9-f8e016a387c2" />

#### 5.4 Configure Security Tests

1. **Click** **Configure Test** button
2. **Navigate** to the **Config** tab
3. **Select** your database type (e.g., Oracle, MySQL, PostgreSQL)
4. **Choose** the security tests you want to run:
   - ✅ Configuration vulnerabilities
   - ✅ User privilege checks
   - ✅ Password policy validation
   - ✅ Patch level verification
   - ✅ Encryption settings
   - ✅ Audit configuration
   - ✅ And many more...
5. **Click** **Save**

<img width="1489" alt="Configuring Security Tests" src="https://github.ibm.com/user-attachments/assets/0d27f2a2-afd6-4efe-81d2-f62bf6ed9f4d" />

#### 5.5 Run Assessment (Test)

Before deploying the scanner, test the assessment manually:

1. **Go back** to the assessment overview
2. **Click** **Run Once Now** button
3. The assessment will execute immediately
4. **View results** in the **Assessment Results** section

**✅ Success Indicator:** You should see test results appearing in the results section, indicating the assessment is properly configured.

---

### Step 6: Deploy VA Scanner with Helm 🚀

**This is the final step!** Deploy the VA Scanner to your EKS cluster to automate continuous vulnerability assessments.

## Installation Methods

You can install the VA Scanner Helm chart using one of three methods:

### Method 1: Clone Repository (Recommended)

```bash
# Clone the repository
git clone https://github.ibm.com/Guardium/va-scanner-helm.git
cd va-scanner-helm

# Install using local chart from src directory
helm install va-scanner ./src/va-scanner -f my-values.yaml -n va-scanner --create-namespace
```

### Method 2: Install from Packaged Tar File

**Option A: Use pre-packaged chart from repository**
```bash
# Clone the repository (authentication required for IBM GitHub Enterprise)
git clone https://github.ibm.com/Guardium/va-scanner-helm.git
cd va-scanner-helm

# The packaged chart is in the releases directory
# Install directly from the .tgz file
helm install va-scanner ./releases/va-scanner-1.0.0.tgz -f my-values.yaml -n va-scanner --create-namespace
```

**Option B: Package it yourself (for custom versions)**
```bash
# Clone the repository
git clone https://github.ibm.com/Guardium/va-scanner-helm.git
cd va-scanner-helm

# Make any custom changes to the chart in src/va-scanner if needed
# Then package the chart
helm package ./src/va-scanner -d ./releases

# This creates: releases/va-scanner-1.0.0.tgz (version from Chart.yaml)

# Install from the packaged file
helm install va-scanner ./releases/va-scanner-1.0.0.tgz -f my-values.yaml -n va-scanner --create-namespace
```


### Method 3: Download from GitHub Release

```bash
# Download the repository archive from a specific release
curl -L https://github.ibm.com/Guardium/va-scanner-helm/archive/refs/tags/v1.0.0.tar.gz -o va-scanner-helm.tar.gz

# Extract the archive
tar -xzf va-scanner-helm.tar.gz

# Navigate to the extracted directory
cd va-scanner-helm-v1.0.0

# Install from the chart directory in src
helm install va-scanner ./src/va-scanner -f my-values.yaml -n va-scanner --create-namespace

# Or use the packaged .tgz file from releases directory
helm install va-scanner ./releases/va-scanner-1.0.0.tgz -f my-values.yaml -n va-scanner --create-namespace
```

**Benefits:**
- ✅ Install specific version by tag
- ✅ No need to clone with Git
- ✅ Works with curl/wget

---

## Summary: Which Method to Use?

| Method | Best For | Pros | Cons |
|--------|----------|------|------|
| **Method 1: Clone** | Development, customization | Simple, full control, latest code | Requires Git |
| **Method 2: Packaged .tgz** | Production, distribution | Single file, air-gapped support | Need to get file first |
| **Method 3: GitHub Release** | Specific versions | Version pinning, no Git needed | Requires authentication |

**Recommendation:**
- **Development:** Use Method 1 (clone)
- **Production:** Use Method 2 (packaged .tgz) or Method 3 (GitHub release)
- **Air-gapped:** Use Method 2 (distribute the .tgz file)

---

#### 6.1 Gather Required Credentials

**GDP API Key:**
```bash
# SSH to your GDP server
ssh user@your-gdp-server

# Create API key for the scanner
grdapi create_api_key name=vascannereks

# Copy and save the "Encoded API key" from the output
```

**GDP Certificate:**

Extract the certificate directly from your GDP server using OpenSSL:

```bash
# Run this command on YOUR LAPTOP (replace YOUR_GDP_HOST with your GDP server):
openssl s_client -connect YOUR_GDP_HOST:8443 -showcerts </dev/null 2>/dev/null | openssl x509 -outform PEM | base64 | tr -d '\n'

# Example:
openssl s_client -connect ec2-54-85-148-224.compute-1.amazonaws.com:8443 -showcerts </dev/null 2>/dev/null | openssl x509 -outform PEM | base64 | tr -d '\n'
```

This will output the base64-encoded certificate in a single line. Copy the entire output.

**Check Certificate Hostname:**

Verify what hostname the certificate is issued for:

```bash
# Run this command to see the certificate's Subject Alternative Name (SAN):
openssl s_client -connect YOUR_GDP_HOST:8443 -showcerts </dev/null 2>/dev/null | openssl x509 -noout -text | grep -A2 "Subject Alternative Name"

# Example output:
#     X509v3 Subject Alternative Name:
#         DNS:ec2-54-85-148-224.compute-1.amazonaws.com
```

**Important:** The hostname in the certificate (DNS name) must match the `gdp.host` value in your configuration. If they match, you don't need host aliases.

**IBM Entitlement Key:**

Get your IBM Entitlement Key for pulling the scanner image:

```bash
# Go to: https://myibm.ibm.com/products-services/containerlibrary
# Click "Copy entitlement key" button
# Save the key - you'll need it for registry.password
```

#### 6.2 Prepare Helm Values File

```bash
# Navigate to the Helm chart directory
cd src/va-scanner

# Copy the example values file
cp values-example.yaml my-values.yaml
```

#### 6.3 Configure Your Values

Edit `my-values.yaml` with your specific configuration:

```yaml
# Namespace Configuration
namespace:
  create: false  # Set to false if using --create-namespace flag
  name: va-scanner6

# GDP Server Configuration
gdp:
  # GDP Server hostname - MUST match the hostname in your SSL certificate
  # STEP 1: Check certificate hostname:
  #   openssl s_client -connect YOUR_GDP_HOST:8443 -showcerts </dev/null 2>/dev/null | openssl x509 -noout -text | grep -A2 "Subject Alternative Name"
  # STEP 2: Use the DNS name from certificate output
  host: "guard.yourcompany.com"                      # TODO: Replace with YOUR certificate DNS name
  apiKey: "your-base64-encoded-api-key"              # TODO: From step 6.1
  agentName: "eks-va-scanner-01"                     # Unique identifier for this scanner
  certBase64: "your-base64-encoded-certificate"      # TODO: From step 6.1

# IBM Container Registry Credentials (for cp.icr.io)
registry:
  username: "cp"                                      # Use 'cp' for IBM entitled software
  password: "your-ibm-entitlement-key"               # TODO: From https://myibm.ibm.com/products-services/containerlibrary
  email: "cp"                                        # Use 'cp' for entitled software
  server: cp.icr.io                                  # IBM Container Registry

# Scanner Container Image
image:
  repository: cp.icr.io/cp/ibm-guardium-data-security-center/guardium/vascanner-12.2.0/va-scanner
  tag: "vascanner-v12.2.0"
  pullPolicy: IfNotPresent

# Deployment Configuration
replicaCount: 3  # Number of scanner pods (if HPA is disabled)

# VA Scanner Polling (prevents CrashLoopBackOff when no jobs available)
vaScannerPollInMins: 10  # Poll every 10 minutes

# Optional: Enable auto-scaling
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10

# Host Aliases - ONLY needed if certificate hostname differs from actual hostname
# Check if needed by comparing certificate DNS name with gdp.host above
# If they MATCH → use empty array: hostAliases: []
# If they DIFFER → configure mapping:
# hostAliases:
#   - ip: "52.21.60.157"              # TODO: Your GDP server's actual IP
#     hostnames:
#       - "guard.yourcompany.com"     # TODO: Must match gdp.host above
hostAliases: []  # Default: empty (assumes certificate hostname matches)
```

#### 6.4 Deploy with Helm

Choose one of the installation methods below based on your preference:

**Method 1: From Cloned Repository**
```bash
# Navigate to the cloned repository
cd va-scanner-helm

# Install the Helm chart from src directory
helm install va-scanner ./src/va-scanner -f my-values.yaml -n va-scanner --create-namespace

# Watch the deployment progress
kubectl get pods -n va-scanner -w
```

**Method 2: From Packaged Tar File**
```bash
# Install from packaged tar file in releases directory
helm install va-scanner ./releases/va-scanner-1.0.0.tgz -f my-values.yaml -n va-scanner --create-namespace

# Watch the deployment progress
kubectl get pods -n va-scanner -w
```

**Method 3: Using Helm Git Support**
```bash
# Install directly from Git repository (Helm 3.7+)
helm install va-scanner \
  git+https://github.ibm.com/Guardium/va-scanner-helm@main?path=src/va-scanner \
  -f my-values.yaml \
  -n va-scanner \
  --create-namespace

# Watch the deployment progress
kubectl get pods -n va-scanner -w
```

**Note:** The `--create-namespace` flag is required for the first installation. It tells Helm to create the namespace before deploying resources.

**Expected Output:**
```
NAME                          READY   STATUS    RESTARTS   AGE
va-scanner-5d8f7b9c4d-abc12   1/1     Running   0          30s
va-scanner-5d8f7b9c4d-def34   1/1     Running   0          30s
va-scanner-5d8f7b9c4d-ghi56   1/1     Running   0          30s
```

#### 6.5 Verify Successful Deployment

**Check all resources:**
```bash
kubectl get all -n va-scanner
```

**Check scanner logs:**
```bash
kubectl logs -n va-scanner -l app=va-scanner --tail=100 -f
```

**✅ Expected Log Output (Success Indicators):**
```
Using this certificate file for keystore: [ /var/vascanner/certs/vascanner.pem ]
2025-12-18 18:39:09 INFO  VAScannerLogger:147 - VA Scanner App is starting to run
2025-12-18 18:39:09 INFO  VAScannerLogger:147 - VA Scanner App running
2025-12-18 18:39:09 INFO  VAScannerLogger:147 - VA Scanner App connecting to Guardium server
2025-12-18 18:39:14 INFO  VAScannerLogger:147 - Test ID Assessment : ID : 20000 TestID : 4211 Severity : INFO completed
```

**Sample Assessment Execution Logs:**
```
2025-11-26 18:33:49 INFO  VAScannerLogger:147 - Test ID Assessment : ID : 20000 TestID : 20 Severity : INFO completed in 0 minutes and 0 seconds.
2025-11-26 18:33:56 INFO  VAScannerLogger:147 - Test ID Assessment : ID : 20000 TestID : 250 Severity : INFO completed in 0 minutes and 0 seconds.
2025-11-26 18:33:56 INFO  VAScannerLogger:147 - Test ID Assessment : ID : 20000 TestID : 251 Severity : INFO completed in 0 minutes and 0 seconds.
2025-11-26 18:34:07 INFO  VAScannerLogger:147 - Test ID Assessment : ID : 20000 TestID : 220 Severity : INFO completed in 0 minutes and 0 seconds.
```

**Key Success Indicators:**
- ✅ `VA Scanner App is starting to run` - Scanner initialized
- ✅ `VA Scanner App running` - Scanner is active
- ✅ `VA Scanner App connecting to Guardium server` - Connection established
- ✅ `Test ID Assessment : ID : XXXXX TestID : XXX ... completed` - Assessments executing

**🎉 Congratulations!** Your VA Scanner is now deployed and automatically running security assessments on your databases!

---
## Prerequisites Summary

Before starting, ensure you have:

- ✅ AWS account with permissions to create EKS clusters and RDS databases
- ✅ GDP server deployed and accessible (port 8443 open)
- ✅ Database instance created (RDS or other)
- ✅ Kubernetes 1.19+
- ✅ Helm 3.0+
- ✅ kubectl configured
- ✅ IBM Artifactory credentials (for scanner image)
- ✅ Sufficient EKS permissions (create deployments, secrets, etc.)

## Common Operations

### Upgrade Deployment

```bash
# Update your values file, then upgrade
helm upgrade va-scanner . -f my-values.yaml

# Watch the rollout
kubectl rollout status deployment/va-scanner -n va-scanner
```

### Rollback Deployment

```bash
# List revisions
helm history va-scanner

# Rollback to previous version
helm rollback va-scanner

# Rollback to specific revision
helm rollback va-scanner 2
```

### Scale Deployment

```bash
# Disable HPA first if enabled
helm upgrade va-scanner . -f my-values.yaml --set autoscaling.enabled=false

# Scale deployment manually
kubectl scale deployment va-scanner -n va-scanner --replicas=5
```

### Uninstall

```bash
# Remove the deployment
helm uninstall va-scanner

# Optionally delete the namespace
kubectl delete namespace va-scanner
```

## Advanced Configuration

### Autoscaling (HPA)

```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80
```

### Resource Limits

```yaml
resources:
  limits:
    cpu: 1000m
    memory: 2Gi
  requests:
    cpu: 250m
    memory: 512Mi
```

### Node Affinity

```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: workload-type
          operator: In
          values:
          - scanner
```

## Troubleshooting

### Issue: Certificate Hostname Mismatch Error

**Symptoms:**
```
SSL certificate verification failed
Certificate hostname doesn't match
Connection refused or SSL handshake failed
```

**Root Cause:**
Your GDP server certificate is issued for a specific hostname (e.g., `guard.yourcompany.com`), but the actual server is accessed via a different hostname or IP (e.g., `ec2-52-21-60-157.compute-1.amazonaws.com`).

**Solution:**

1. **Use the certificate hostname in your configuration:**
   ```yaml
   gdp:
     host: "guard.yourcompany.com"  # Use certificate hostname, NOT EC2 hostname
   ```

2. **Add hostAliases to map the hostname to the actual IP:**
   ```yaml
   hostAliases:
     - ip: "52.21.60.157"  # Your GDP server's actual IP
       hostnames:
         - "guard.yourcompany.com"  # Certificate hostname
   ```

3. **Extract the correct certificate:**
   ```bash
   # Use the server.pem file that matches your certificate hostname
   base64 < server.pem | tr -d '\n' | pbcopy  # macOS
   base64 -w 0 < server.pem                    # Linux
   ```

4. **Verify your certificate fingerprint:**
   ```bash
   openssl x509 -in server.pem -noout -fingerprint -sha256
   # Should match: C4:40:9D:9A:... (your expected fingerprint)
   ```

**Complete Example:**
```yaml
gdp:
  host: "guard.yourcompany.com"
  certBase64: "LS0tLS1CRUdJTi..."  # From server.pem

hostAliases:
  - ip: "52.21.60.157"
    hostnames:
      - "guard.yourcompany.com"
```

---

### Issue: Helm Installation Failed - Namespace Already Exists

**Symptoms:**
```
Error: INSTALLATION FAILED: Namespace "va-scanner" exists and cannot be imported
```

**Solution:**
If you created the namespace manually in Step 3 before running Helm, either:

**Option 1: Delete and let Helm create it**
```bash
kubectl delete namespace va-scanner
helm install va-scanner . -f my-values.yaml
```

**Option 2: Skip namespace creation in Helm**
```bash
# Edit your my-values.yaml file
# Set: namespace.create: false
helm install va-scanner . -f my-values.yaml
```

---

### Issue: Pods in CrashLoopBackOff When No Jobs Available

**Symptoms:**
```bash
kubectl get pods -n va-scanner
NAME                          READY   STATUS             RESTARTS   AGE
va-scanner-6bffc45f54-5xsl2   0/1     CrashLoopBackOff   4          3m23s
va-scanner-6bffc45f54-s5h2c   0/1     CrashLoopBackOff   4          3m39s
```

**Logs show normal operation:**
```
VA Scanner App got empty JobQueue. Nothing to do.
VA Scanner App status: Success.
VA Scanner App shutting down at 2025-11-26 18:07:18
```

**Root Cause:**
The VA scanner exits successfully (code 0) when no jobs are available. Kubernetes restarts the pod, causing CrashLoopBackOff status even though the scanner is working correctly.

**Solution:**
Enable internal polling to keep pods running:

```yaml
# In your values.yaml
vaScannerPollInMins: 10  # Poll every 10 minutes
```

**Result:**
```bash
kubectl get pods -n va-scanner
NAME                          READY   STATUS    RESTARTS   AGE
va-scanner-6bffc45f54-5xsl2   1/1     Running   0          10m
va-scanner-6bffc45f54-s5h2c   1/1     Running   0          10m
```

---

### Issue: Pods Not Starting

**Symptoms:**
- Pods stuck in `Pending` or `ImagePullBackOff` state

**Solutions:**

1. **Check image pull secrets:**
```bash
kubectl get secret ibm-entitlement-key -n va-scanner
kubectl describe pod -n va-scanner -l app=va-scanner
```

2. **Verify registry credentials:**
```bash
# Check if secret exists and has correct data
kubectl get secret ibm-entitlement-key -n va-scanner -o yaml
```

3. **Check events:**
```bash
kubectl get events -n va-scanner --sort-by='.lastTimestamp' | grep -i pull
```

### Issue: Scanner Cannot Connect to GDP

**Symptoms:**
- Logs show connection errors
- No assessment results in GDP

**Solutions:**

1. **Verify GDP host is accessible:**
```bash
# Test from a debug pod
kubectl run -it --rm debug --image=busybox --restart=Never -n va-scanner -- sh
nc -zv your-gdp-host 8443
```

2. **Check GDP configuration:**
```bash
# Verify GDP host
kubectl get secret va-scanner-credentials -n va-scanner -o jsonpath='{.data.GDP_HOST_IP}' | base64 -d

# Verify API key exists
kubectl get secret va-scanner-credentials -n va-scanner -o jsonpath='{.data.GDP_API_KEY}' | base64 -d
```

3. **Verify certificate:**
```bash
kubectl get secret va-cert -n va-scanner -o jsonpath='{.data.ca\.crt}' | base64 -d | openssl x509 -text -noout
```

4. **Check network connectivity:**
- Ensure GDP server port 8443 is open
- Verify security groups (AWS) or firewall rules allow traffic
- Confirm GDP is not behind IBM-only network restrictions

### Issue: Assessments Not Running

**Symptoms:**
- Scanner connects but no assessments execute
- No test results in GDP console

**Solutions:**

1. **Verify assessment configuration in GDP:**
   - Check that data source is added to assessment
   - Confirm tests are configured
   - Ensure assessment is set to run

2. **Check scanner logs:**
```bash
kubectl logs -n va-scanner -l app=va-scanner --tail=200 -f
```

3. **Verify data source connectivity from GDP:**
   - Test connection in GDP console
   - Check database credentials
   - Ensure database is accessible from GDP server

### View Detailed Logs

```bash
# All pods
kubectl logs -n va-scanner -l app=va-scanner --tail=200

# Specific pod
kubectl logs -n va-scanner <pod-name> --tail=200 -f

# Previous container (if crashed)
kubectl logs -n va-scanner <pod-name> --previous
```

### Check Resource Usage

```bash
# Pod resource usage
kubectl top pods -n va-scanner

# HPA status
kubectl describe hpa -n va-scanner

# Node resource usage
kubectl top nodes
```

## Configuration Reference

### Required Values

| Parameter | Description | Example |
|-----------|-------------|---------|
| `namespace.name` | Kubernetes namespace | `va-scanner` |
| `gdp.host` | GDP server hostname/IP | `ec2-xx-xxx.compute-1.amazonaws.com` |
| `gdp.apiKey` | GDP API key (base64 encoded) | `your-base64-api-key` |
| `gdp.agentName` | Unique VA agent identifier | `my-va-scanner` |
| `gdp.certBase64` | GDP certificate (base64 encoded) | `LS0tLS1CRUdJTi...` |
| `registry.username` | IBM Artifactory username | `your-email@company.com` |
| `registry.password` | IBM Artifactory token | `your-token` |
| `registry.email` | Registry email | `your-email@company.com` |

### Optional Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `vaScannerPollInMins` | **IMPORTANT:** Polling interval in minutes. Prevents CrashLoopBackOff when no jobs available. Set to 0 to disable. | `10` |
| `namespace.create` | Create namespace | `true` |
| `registry.server` | Registry server URL | `docker-na-public.artifactory.swg-devops.com` |
| `image.repository` | Scanner image repository | `docker-na-public.artifactory.swg-devops.com/sec-guardium-next-gen-docker-local/va-scanner` |
| `image.tag` | Scanner image tag | `vascanner_trunk-b823b06-15936-20251125_0327` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `replicaCount` | Number of replicas (if HPA disabled) | `3` |
| `autoscaling.enabled` | Enable Horizontal Pod Autoscaler | `true` |
| `autoscaling.minReplicas` | Minimum replicas | `2` |
| `autoscaling.maxReplicas` | Maximum replicas | `10` |
| `autoscaling.targetCPUUtilizationPercentage` | Target CPU for scaling | `70` |
| `autoscaling.targetMemoryUtilizationPercentage` | Target memory for scaling | `80` |
| `resources.requests.cpu` | CPU request | `250m` |
| `resources.requests.memory` | Memory request | `512Mi` |
| `resources.limits.cpu` | CPU limit | `1000m` |
| `resources.limits.memory` | Memory limit | `2Gi` |

## Support and Documentation

### Additional Resources

- [Guardium Data Protection Documentation](https://www.ibm.com/docs/en/guardium)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Helm Documentation](https://helm.sh/docs/)
- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)

### Getting Help

If you encounter issues:
1. Check the troubleshooting section above
2. Review scanner logs for error messages
3. Verify all prerequisites are met
4. Ensure network connectivity between components
5. Contact your Guardium administrator or IBM support

