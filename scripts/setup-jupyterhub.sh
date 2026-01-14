#!/bin/bash
set -euo pipefail

NAMESPACE="sovereign-dp"
RELEASE_NAME="jupyterhub"
CHART_VERSION="3.2.1"

echo "📓 Setting up JupyterHub in namespace: $NAMESPACE"

# Check prerequisites
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed"
    exit 1
fi

if ! command -v helm &> /dev/null; then
    echo "❌ Helm is not installed"
    exit 1
fi

# Check if cluster is running
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Kubernetes cluster is not running"
    echo "Run: ./scripts/setup-cluster.sh"
    exit 1
fi

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    echo "⚠️  Namespace $NAMESPACE does not exist"
    echo "Creating namespace..."
    kubectl create namespace "$NAMESPACE"
fi

# Add JupyterHub Helm repo
if ! helm repo list | grep -q "jupyterhub"; then
    echo "📚 Adding JupyterHub Helm repository..."
    helm repo add jupyterhub https://hub.jupyter.org/helm-chart/
fi

echo "🔄 Updating Helm repositories..."
helm repo update

# Generate random token for proxy secret token (if not exists)
if ! kubectl get secret -n "$NAMESPACE" jupyterhub-proxy-secret &> /dev/null; then
    echo "🔑 Generating proxy secret token..."
    PROXY_SECRET_TOKEN=$(openssl rand -hex 32)
    kubectl create secret generic jupyterhub-proxy-secret \
        --from-literal=proxy-token="$PROXY_SECRET_TOKEN" \
        --namespace "$NAMESPACE"
else
    echo "✓ Proxy secret already exists"
fi

# Install or upgrade JupyterHub
if helm list -n "$NAMESPACE" | grep -q "^${RELEASE_NAME}"; then
    echo "⬆️  Upgrading JupyterHub..."
    helm upgrade "$RELEASE_NAME" jupyterhub/jupyterhub \
        --namespace "$NAMESPACE" \
        --values k8s/helm-values/jupyterhub-values.yaml \
        --version "$CHART_VERSION" \
        --timeout 10m
else
    echo "📦 Installing JupyterHub via Helm..."
    helm install "$RELEASE_NAME" jupyterhub/jupyterhub \
        --namespace "$NAMESPACE" \
        --values k8s/helm-values/jupyterhub-values.yaml \
        --version "$CHART_VERSION" \
        --wait \
        --timeout 10m
fi

# Wait for JupyterHub to be ready
echo "⏳ Waiting for JupyterHub to be ready..."
kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=jupyterhub \
    -l component=hub \
    -n "$NAMESPACE" \
    --timeout=600s || true

# Give it a few more seconds to stabilize
sleep 5

echo ""
echo "✅ JupyterHub is ready!"
echo ""
echo "📊 JupyterHub Information:"
echo "   Namespace: $NAMESPACE"
echo "   Release: $RELEASE_NAME"
echo ""
echo "🔗 Access:"
echo "   URL: http://localhost:8888"
echo ""
echo "🔑 Login:"
echo "   Username: any username (dummy authenticator)"
echo "   Password: jupyter"
echo ""
echo "📝 Installed Python packages in notebooks:"
echo "   - trino (SQL client for Trino/Iceberg)"
echo "   - pandas, numpy (data manipulation)"
echo "   - matplotlib, seaborn, plotly (visualization)"
echo "   - pyarrow (Arrow/Parquet support)"
echo "   - ipython-sql (SQL magic commands)"
echo ""
echo "🧪 Test Trino connection in notebook:"
echo '   from trino.dbapi import connect'
echo '   conn = connect('
echo '       host="trino-coordinator.sovereign-dp.svc.cluster.local",'
echo '       port=8080,'
echo '       catalog="iceberg",'
echo '       schema="default"'
echo '   )'
echo '   cursor = conn.cursor()'
echo '   cursor.execute("SHOW SCHEMAS")'
echo '   print(cursor.fetchall())'
echo ""
echo "Or use SQL magic:"
echo '   %load_ext sql'
echo '   %sql trino://trino-coordinator.sovereign-dp.svc.cluster.local:8080/iceberg'
echo '   %%sql'
echo '   SHOW CATALOGS;'
echo ""
echo "📚 Access JupyterLab: http://localhost:8888/lab"
