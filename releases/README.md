# Helm Chart Releases

This directory contains packaged Helm chart releases for easy distribution.

## Available Releases

- `va-scanner-1.0.0.tgz` - Initial release (v1.0.0)

## How to Use

### Install from this directory

```bash
# Clone the repository
git clone https://github.ibm.com/Guardium/va-scanner-helm.git
cd va-scanner-helm

# Install from the packaged release
helm install va-scanner ./releases/va-scanner-1.0.0.tgz -f my-values.yaml -n va-scanner --create-namespace
```

### Create a new release

```bash
# Make changes to the chart in src/va-scanner
cd src/va-scanner

# Update version in Chart.yaml
# Then package the chart
cd ../..
helm package ./src/va-scanner -d ./releases

# This creates: releases/va-scanner-<version>.tgz
```

## Distribution

These packaged charts can be:
- Shared directly with customers
- Uploaded to GitHub releases
- Distributed in air-gapped environments
- Used for offline installations