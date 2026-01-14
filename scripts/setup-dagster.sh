#!/bin/bash
set -euo pipefail

NAMESPACE="sovereign-dp"
POSTGRES_RELEASE="dagster-postgresql"
DAGSTER_RELEASE="dagster"
DAGSTER_IMAGE="sovereign-dp-dagster:latest"

echo "🎯 Setting up Dagster in namespace: $NAMESPACE"

# Check prerequisites
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed"
    exit 1
fi

if ! command -v helm &> /dev/null; then
    echo "❌ Helm is not installed"
    exit 1
fi

if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed"
    exit 1
fi

# Check if cluster is running
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Kubernetes cluster is not running"
    echo "Run: ./scripts/setup-cluster.sh"
    exit 1
fi

# Add Helm repos
echo "📚 Adding Helm repositories..."
helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
helm repo add dagster https://dagster-io.github.io/helm 2>/dev/null || true
helm repo update

# Step 1: Deploy PostgreSQL for Dagster
echo ""
echo "🐘 Deploying PostgreSQL for Dagster metadata..."
if helm list -n "$NAMESPACE" | grep -q "^${POSTGRES_RELEASE}"; then
    echo "⬆️  Upgrading PostgreSQL..."
    helm upgrade "$POSTGRES_RELEASE" bitnami/postgresql \
        --namespace "$NAMESPACE" \
        --values k8s/helm-values/postgresql-dagster-values.yaml
else
    echo "📦 Installing PostgreSQL..."
    helm install "$POSTGRES_RELEASE" bitnami/postgresql \
        --namespace "$NAMESPACE" \
        --values k8s/helm-values/postgresql-dagster-values.yaml \
        --wait \
        --timeout 5m
fi

# Wait for PostgreSQL
echo "⏳ Waiting for PostgreSQL to be ready..."
kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=postgresql \
    -l app.kubernetes.io/instance=$POSTGRES_RELEASE \
    -n "$NAMESPACE" \
    --timeout=300s

# Step 2: Create Dagster secrets
echo ""
echo "🔐 Creating Dagster secrets..."

# PostgreSQL connection secret
kubectl create secret generic dagster-postgresql-secret \
    --namespace "$NAMESPACE" \
    --from-literal=postgresql-password=dagster \
    --dry-run=client -o yaml | kubectl apply -f -

# Environment secrets for Dagster (rustfs credentials, etc.)
kubectl create secret generic dagster-env \
    --namespace "$NAMESPACE" \
    --from-literal=AWS_ACCESS_KEY_ID=rustfsadmin \
    --from-literal=AWS_SECRET_ACCESS_KEY=rustfsadmin \
    --from-literal=AWS_ENDPOINT_URL=http://rustfs.sovereign-dp.svc.cluster.local:9000 \
    --from-literal=TRINO_HOST=trino-coordinator.sovereign-dp.svc.cluster.local \
    --from-literal=TRINO_PORT=8080 \
    --dry-run=client -o yaml | kubectl apply -f -

# Step 3: Build and load Dagster code image
echo ""
echo "🐳 Building Dagster code image..."
if [ -d "dagster" ]; then
    docker build -t "$DAGSTER_IMAGE" dagster/

    echo "📤 Loading image into kind cluster..."
    kind load docker-image "$DAGSTER_IMAGE" --name sovereign-dp
else
    echo "⚠️  No dagster/ directory found, skipping code image build"
    echo "   User deployments will need to be configured separately"
fi

# Step 4: Deploy Dagster
echo ""
echo "🎯 Deploying Dagster..."
if helm list -n "$NAMESPACE" | grep -q "^${DAGSTER_RELEASE}[[:space:]]"; then
    echo "⬆️  Upgrading Dagster..."
    helm upgrade "$DAGSTER_RELEASE" dagster/dagster \
        --namespace "$NAMESPACE" \
        --values k8s/helm-values/dagster-values.yaml
else
    echo "📦 Installing Dagster..."
    helm install "$DAGSTER_RELEASE" dagster/dagster \
        --namespace "$NAMESPACE" \
        --values k8s/helm-values/dagster-values.yaml \
        --wait \
        --timeout 10m
fi

# Wait for Dagster webserver
echo "⏳ Waiting for Dagster to be ready..."
kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=dagster \
    -l component=dagster-webserver \
    -n "$NAMESPACE" \
    --timeout=300s 2>/dev/null || \
kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/instance=dagster \
    -n "$NAMESPACE" \
    --timeout=300s

echo ""
echo "✅ Dagster is ready!"
echo ""
echo "📊 Dagster Information:"
echo "   Namespace: $NAMESPACE"
echo "   PostgreSQL: $POSTGRES_RELEASE"
echo "   Dagster: $DAGSTER_RELEASE"
echo ""
echo "🔗 Access:"
echo "   Web UI: http://localhost:3000"
echo ""
echo "📝 Verify deployment:"
echo "   kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=dagster"
echo ""
echo "Next steps:"
echo "  1. Open Dagster UI: open http://localhost:3000"
echo "  2. Materialize assets from the UI"
echo "  3. Monitor runs and logs"
