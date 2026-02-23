#!/bin/bash

# Prepare Namespace for Helm Deployment
# This script ensures the namespace has the correct labels and annotations
# for Helm to manage it properly.

set -e

# Configuration
NAMESPACE="${1:-va-scanner6}"
RELEASE_NAME="${2:-va-scanner}"

echo "=================================================="
echo "Preparing namespace: $NAMESPACE"
echo "Release name: $RELEASE_NAME"
echo "=================================================="

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    echo "✓ Creating namespace: $NAMESPACE"
    kubectl create namespace "$NAMESPACE"
else
    echo "✓ Namespace already exists: $NAMESPACE"
fi

# Add Helm management label
echo "✓ Adding Helm management label..."
kubectl label namespace "$NAMESPACE" \
    app.kubernetes.io/managed-by=Helm \
    --overwrite

# Add Helm release annotations
echo "✓ Adding Helm release annotations..."
kubectl annotate namespace "$NAMESPACE" \
    meta.helm.sh/release-name="$RELEASE_NAME" \
    meta.helm.sh/release-namespace="$NAMESPACE" \
    --overwrite

# Verify the configuration
echo ""
echo "=================================================="
echo "Namespace Configuration:"
echo "=================================================="
kubectl get namespace "$NAMESPACE" -o yaml | grep -A 10 "metadata:"

echo ""
echo "✅ Namespace is ready for Helm deployment!"
echo ""
echo "Next steps:"
echo "  1. Update your values.yaml with correct configuration"
echo "  2. Run: helm install $RELEASE_NAME ./va-scanner -f my-values.yaml -n $NAMESPACE"
echo ""