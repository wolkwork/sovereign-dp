#!/bin/bash
set -euo pipefail

NAMESPACE="sovereign-dp"

echo "📁 Setting up namespace: $NAMESPACE"

# Check prerequisites
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed"
    exit 1
fi

# Check if cluster is running
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Kubernetes cluster is not running"
    echo "Run: ./scripts/setup-cluster.sh"
    exit 1
fi

# Create namespace if it doesn't exist
if kubectl get namespace "$NAMESPACE" &> /dev/null; then
    echo "✓ Namespace $NAMESPACE already exists"
else
    echo "📦 Creating namespace $NAMESPACE..."
    kubectl create namespace "$NAMESPACE"
    echo "✅ Namespace $NAMESPACE created"
fi
