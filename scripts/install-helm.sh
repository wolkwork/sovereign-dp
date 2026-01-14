#!/bin/bash
set -euo pipefail

echo "📦 Installing Helm..."

# Check if helm is already installed
if command -v helm &> /dev/null; then
    HELM_VERSION=$(helm version --short)
    echo "✓ Helm is already installed: $HELM_VERSION"
    exit 0
fi

# Install Helm
echo "Downloading Helm installer..."
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify installation
if command -v helm &> /dev/null; then
    HELM_VERSION=$(helm version --short)
    echo "✅ Helm installed successfully: $HELM_VERSION"
else
    echo "❌ Helm installation failed"
    exit 1
fi

echo ""
echo "Add common repositories:"
echo "  helm repo add bitnami https://charts.bitnami.com/bitnami"
echo "  helm repo add trino https://trinodb.github.io/charts"
echo "  helm repo update"
