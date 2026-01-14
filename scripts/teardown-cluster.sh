#!/bin/bash
set -euo pipefail

CLUSTER_NAME="sovereign-dp"

echo "🗑️  Tearing down kind cluster: $CLUSTER_NAME"

if ! kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
    echo "⚠️  Cluster $CLUSTER_NAME does not exist"
    exit 0
fi

read -p "Are you sure you want to delete cluster $CLUSTER_NAME? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 0
fi

kind delete cluster --name "$CLUSTER_NAME"

echo "✅ Cluster deleted"
