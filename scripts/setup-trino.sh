#!/bin/bash
set -euo pipefail

NAMESPACE="sovereign-dp"
RELEASE_NAME="trino"
CHART_REPO="https://trinodb.github.io/charts"

echo "🔍 Setting up Trino in namespace: $NAMESPACE"

# Check prerequisites
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed"
    exit 1
fi

if ! command -v helm &> /dev/null; then
    echo "❌ Helm is not installed"
    exit 1
fi

# Add Trino Helm repo
if ! helm repo list | grep -q "trino"; then
    echo "📚 Adding Trino Helm repository..."
    helm repo add trino https://trinodb.github.io/charts
fi

echo "🔄 Updating Helm repositories..."
helm repo update

# Check if Nessie is running
if ! kubectl get deployment nessie -n "$NAMESPACE" &> /dev/null; then
    echo "⚠️  Nessie is not deployed. Trino needs Nessie for Iceberg catalog."
    echo "Run: ./scripts/setup-nessie.sh first"
    exit 1
fi

# Install or upgrade Trino
if helm list -n "$NAMESPACE" | grep -q "^${RELEASE_NAME}"; then
    echo "⬆️  Upgrading Trino..."
    helm upgrade "$RELEASE_NAME" trino/trino \
        --namespace "$NAMESPACE" \
        --values k8s/helm-values/trino-values.yaml
else
    echo "📦 Installing Trino via Helm..."
    helm install "$RELEASE_NAME" trino/trino \
        --namespace "$NAMESPACE" \
        --values k8s/helm-values/trino-values.yaml \
        --wait \
        --timeout 10m
fi

# Wait for Trino to be ready
echo "⏳ Waiting for Trino to be ready..."
kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=trino \
    -l app.kubernetes.io/component=coordinator \
    -n "$NAMESPACE" \
    --timeout=600s

echo ""
echo "✅ Trino is ready!"
echo ""
echo "📊 Trino Information:"
echo "   Namespace: $NAMESPACE"
echo "   Release: $RELEASE_NAME"
echo "   Workers: 2"
echo ""
echo "🔗 Access:"
echo "   Web UI: http://localhost:8080"
echo "   JDBC: jdbc:trino://localhost:8080"
echo ""
echo "📝 Test connection:"
echo '   kubectl exec -n sovereign-dp deploy/trino-coordinator -- trino --execute "SHOW CATALOGS;"'
echo ""
echo "Next steps:"
echo "  1. Test Iceberg tables: ./scripts/test-iceberg.sh"
echo "  2. Configure DBeaver connection"
