#!/bin/bash
set -euo pipefail

CLUSTER_NAME="sovereign-dp"
CONFIG_FILE="kind-config.yaml"

echo "🚀 Setting up kind cluster: $CLUSTER_NAME"

# Check if kind is installed
if ! command -v kind &> /dev/null; then
    echo "❌ kind is not installed"
    echo "Install with: curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64"
    echo "              chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind"
    exit 1
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed"
    echo "Install with: curl -LO https://dl.k8s.io/release/v1.28.0/bin/linux/amd64/kubectl"
    echo "              chmod +x kubectl && sudo mv kubectl /usr/local/bin/"
    exit 1
fi

# Check if cluster already exists
if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
    echo "⚠️  Cluster $CLUSTER_NAME already exists"
    read -p "Delete and recreate? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🗑️  Deleting existing cluster..."
        kind delete cluster --name "$CLUSTER_NAME"
    else
        echo "✓ Using existing cluster"
        kubectl cluster-info --context "kind-${CLUSTER_NAME}"
        exit 0
    fi
fi

# Create cluster
echo "📦 Creating kind cluster with config: $CONFIG_FILE"
kind create cluster --config "$CONFIG_FILE"

# Verify cluster
echo "✓ Cluster created successfully"
kubectl cluster-info --context "kind-${CLUSTER_NAME}"
kubectl get nodes

echo ""
echo "✅ Kind cluster is ready!"
echo "   Cluster name: $CLUSTER_NAME"
echo "   Context: kind-${CLUSTER_NAME}"
echo ""
echo "Next steps:"
echo "  1. Install Helm: ./scripts/install-helm.sh"
echo "  2. Set up rustfs: ./scripts/setup-rustfs.sh"
