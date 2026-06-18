y# VA Scanner Enterprise CA Certificate Support - Root Cause Analysis & Solution

## Executive Summary

**Problem**: VA Scanner failed to connect to Guardium Data Protection (GDP) servers in production environments with error: `PKIX path building failed: unable to find valid certification path to requested target`

**Root Cause**: The VA Scanner application requires explicit keystore configuration in `guardAgent.properties` to use enterprise CA certificates (like IBM Internal CA). Without these properties, it falls back to Java's default truststore which doesn't include enterprise CAs.

**Solution**: Use Kubernetes ConfigMap to inject complete `guardAgent.properties` file with keystore configuration, making the solution persistent across pod restarts.

---

## Problem Analysis

### What Happened

1. **Production Deployment Failed** with certificate validation errors
2. **Dev/PreProd Worked** with identical Helm configuration
3. **Manual Fix Applied** by support team:
   - Edited `guardAgent.properties` inside running pods
   - Added keystore path and type properties
   - Scanner connected successfully
4. **Problem Persisted** after pod restarts (configuration lost)

### Error Details

```
ERROR GuardiumConnection:333 - GuardiumConnection failed : PKIX path building failed: 
sun.security.provider.certpath.SunCertPathBuilderException: unable to find valid 
certification path to requested target
```

This error indicates:
- SSL/TLS handshake failed during certificate validation
- Java couldn't build a trust chain from server certificate to a trusted root CA
- The IBM Internal Root CA was not in the truststore being used

### Certificate Chain

Production GDP server (`pdl10gdmngr01.ciso.ibm.com:8443`) presents:
```
Server Certificate
  ↓ issued by
IBM INTERNAL INTERMEDIATE CA
  ↓ issued by
IBM Internal Root CA (self-signed)
```

The root CA is **not** in Java's default truststore (`cacerts`).

---

## Root Cause: Missing Keystore Configuration

### How VA Scanner Handles Certificates

The VA Scanner application has a two-step certificate handling process:

1. **Automatic Keystore Creation**:
   - Reads PEM certificate from `/var/vascanner/certs/vascanner.pem`
   - Automatically creates PKCS12 keystore at `/var/vascanner/vascanner_keystore.p12`
   - Imports the certificate chain into the keystore

2. **Keystore Usage** (CRITICAL):
   - **Only uses the created keystore if explicitly configured** in `guardAgent.properties`
   - Without configuration, falls back to Java's default truststore
   - Default truststore doesn't contain enterprise CAs

### The Missing Configuration

The `guardAgent.properties` file **must** contain:

```properties
guardium.keystore.path=/var/vascanner/vascanner_keystore.p12
guardium.keystore.type=PKCS12
```

### Why Manual Fix Wasn't Persistent

Support team manually edited the file inside running pods:
```bash
# Inside pod
vi /var/vascanner/conf/guardAgent.properties
# Added keystore properties
```

**Problem**: Container filesystem is ephemeral
- Changes lost on pod restart
- Not part of container image or Helm deployment
- Not scalable or maintainable

---

## Why Dev/PreProd Worked

Several possible reasons:

1. **Different VA Scanner Image Version**:
   - Older versions may have had different default behavior
   - May have included enterprise CAs in default truststore

2. **Different GDP Server Configuration**:
   - May use different certificate authority
   - Certificate chain might be in Java's default truststore

3. **Undocumented Manual Configuration**:
   - Someone may have manually configured it previously
   - Configuration not documented or tracked

4. **Environment-Specific Patches**:
   - GDP server patches may differ between environments
   - Certificate handling may have changed

---

## Solution: ConfigMap-Based Configuration

### Approach

Use Kubernetes ConfigMap to inject complete `guardAgent.properties` file with:
- Base configuration (GDP host, port, API key)
- **Keystore configuration** (path and type)
- Environment variable substitution support

### Implementation

#### 1. ConfigMap Template (`templates/configmap.yaml`)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "va-scanner.fullname" . }}-config
  namespace: {{ include "va-scanner.namespace" . }}
  labels:
    {{- include "va-scanner.labels" . | nindent 4 }}
data:
  guardAgent.properties: |
    # VA Scanner Configuration
    [GDPHost_0]=
    gdp.host=${GDP_HOST}
    gdp.host.port=${GDP_HOST_PORT}
    client.apiKey=${CLIENT_API_KEY}
    client.name.internal=
    client.registered=false
    
    # Keystore configuration for enterprise CA certificates
    guardium.keystore.path=/var/vascanner/vascanner_keystore.p12
    guardium.keystore.type=PKCS12
```

#### 2. Deployment Volume Mount (`templates/deployment.yaml`)

```yaml
# Volume definition
volumes:
- name: guardagent-config
  configMap:
    name: {{ include "va-scanner.fullname" . }}-config
    defaultMode: 0644

# Container volume mount
volumeMounts:
- name: guardagent-config
  mountPath: /var/vascanner/conf/guardAgent.properties
  subPath: guardAgent.properties
```

### How It Works

1. **Helm Install/Upgrade**:
   - Creates ConfigMap with complete `guardAgent.properties`
   - Mounts ConfigMap as file in pod

2. **Pod Startup**:
   - VA Scanner reads configuration from mounted file
   - Sees keystore path and type properties
   - Creates PKCS12 keystore from PEM certificate
   - Uses keystore for SSL/TLS connections

3. **Certificate Validation**:
   - Java uses configured keystore instead of default truststore
   - Finds IBM Internal Root CA in keystore
   - Successfully validates certificate chain
   - Connection succeeds

4. **Pod Restart**:
   - Configuration persists (part of Helm deployment)
   - No manual intervention needed
   - Consistent across all pods

---

## Benefits of This Solution

### ✅ Persistent Configuration
- Survives pod restarts
- Part of Helm chart deployment
- Version controlled

### ✅ Scalable
- Works for all replicas automatically
- No manual configuration per pod
- Consistent across environments

### ✅ Maintainable
- Configuration in one place (ConfigMap)
- Easy to update via Helm upgrade
- Clear documentation

### ✅ Enterprise CA Support
- Works with any enterprise CA
- No need to modify Java truststore
- Certificate chain validation works correctly

### ✅ Environment Variable Substitution
- GDP host, port, API key from secrets
- Flexible configuration
- Secure credential handling

---

## Verification Steps

### 1. Deploy with Helm

```bash
helm upgrade --install va-scanner ./guardium-helm/src/va-scanner \
  --namespace va-scanner \
  --create-namespace \
  -f my-values.yaml
```

### 2. Check ConfigMap Created

```bash
kubectl get configmap -n va-scanner
kubectl describe configmap va-scanner-config -n va-scanner
```

### 3. Verify File Mounted in Pod

```bash
kubectl exec -n va-scanner deployment/va-scanner -- \
  cat /var/vascanner/conf/guardAgent.properties
```

Should show keystore properties:
```
guardium.keystore.path=/var/vascanner/vascanner_keystore.p12
guardium.keystore.type=PKCS12
```

### 4. Check Pod Logs

```bash
kubectl logs -n va-scanner deployment/va-scanner --tail=50
```

Look for:
- `VAScanner keystore is created successfully`
- `VA Scanner App connecting to Guardium server`
- `VA Scanner App status: Success`

**No errors** like:
- ❌ `PKIX path building failed`
- ❌ `unable to find valid certification path`

### 5. Test Pod Restart

```bash
kubectl rollout restart deployment/va-scanner -n va-scanner
kubectl logs -n va-scanner deployment/va-scanner --tail=50
```

Configuration should persist, connection should succeed.

---

## Technical Details

### PKCS12 Keystore Format

- **Standard**: Public-Key Cryptography Standards #12
- **Purpose**: Store private keys and certificates
- **Java Support**: Native support in Java 8+
- **File Extension**: `.p12` or `.pfx`
- **Content**: Certificate chain + private key (if present)

### VA Scanner Certificate Handling

The VA Scanner application:

1. **Reads PEM certificate** from mounted volume
2. **Converts to PKCS12** keystore automatically
3. **Imports certificate chain** into keystore
4. **Uses keystore** for SSL/TLS if configured
5. **Falls back** to default truststore if not configured

### Environment Variable Substitution

The `guardAgent.properties` file supports variable substitution:

```properties
gdp.host=${GDP_HOST}           # Replaced at runtime
gdp.host.port=${GDP_HOST_PORT} # From environment variables
client.apiKey=${CLIENT_API_KEY}
```

Variables are provided via Kubernetes secrets in deployment.

---

## Comparison: Before vs After

### Before (Manual Fix)

```
❌ Configuration in pod filesystem (ephemeral)
❌ Lost on pod restart
❌ Manual intervention required
❌ Not scalable
❌ Not version controlled
❌ Inconsistent across environments
```

### After (ConfigMap Solution)

```
✅ Configuration in ConfigMap (persistent)
✅ Survives pod restarts
✅ Automated via Helm
✅ Scales automatically
✅ Version controlled
✅ Consistent across environments
```

---

## Lessons Learned

### 1. Document Manual Fixes
When support applies manual fixes, document:
- What was changed
- Why it was needed
- How to make it persistent

### 2. Understand Application Behavior
The VA Scanner's certificate handling wasn't obvious:
- Creates keystore automatically
- But only uses it if configured
- Falls back to default truststore silently

### 3. Test Across Environments
Dev/PreProd working doesn't guarantee production will work:
- Different certificate authorities
- Different application versions
- Different configurations

### 4. Use Kubernetes Native Solutions
ConfigMaps are designed for this:
- Configuration injection
- Persistent across restarts
- Scalable and maintainable

---

## Future Improvements

### 1. Add Validation
Add init container to validate configuration:
```yaml
initContainers:
- name: validate-config
  command: ["/bin/sh", "-c"]
  args:
    - |
      grep -q "guardium.keystore.path" /var/vascanner/conf/guardAgent.properties
      grep -q "guardium.keystore.type" /var/vascanner/conf/guardAgent.properties
```

### 2. Add Health Checks
Improve liveness/readiness probes to detect certificate issues early.

### 3. Document Certificate Requirements
Add clear documentation about:
- Supported certificate formats
- Certificate chain requirements
- Enterprise CA support

### 4. Automated Testing
Add tests to verify:
- ConfigMap creation
- File mounting
- Certificate validation

---

## Conclusion

The root cause was **missing keystore configuration** in `guardAgent.properties`. The VA Scanner application requires explicit configuration to use the PKCS12 keystore it creates from the mounted PEM certificate. Without this configuration, it falls back to Java's default truststore, which doesn't include enterprise CAs like IBM Internal CA.

The solution uses a **Kubernetes ConfigMap** to inject the complete configuration file with keystore properties, making it persistent, scalable, and maintainable. This approach eliminates the need for manual intervention and ensures consistent behavior across all environments and pod restarts.

**Key Takeaway**: Always ensure application configuration is part of the deployment manifest, not applied manually to running containers.

---

*Document created: 2026-06-17*  
*Author: Bob (AI Assistant)*  
*Version: 1.0*