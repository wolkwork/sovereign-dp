#!/bin/bash
set -euo pipefail

NAMESPACE="sovereign-dp"

echo "🔑 Setting up S3 credentials (rustfs)"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed"
    exit 1
fi

# rustfs credentials
S3_ROOT_USER="rustfsadmin"
S3_ROOT_PASSWORD="rustfsadmin"
S3_ENDPOINT="http://rustfs.sovereign-dp.svc.cluster.local:9000"

# Create secret for rustfs credentials
echo "📦 Creating K8s secret: rustfs-credentials"
kubectl create secret generic rustfs-credentials \
    --from-literal=root-user="$S3_ROOT_USER" \
    --from-literal=root-password="$S3_ROOT_PASSWORD" \
    --from-literal=endpoint="$S3_ENDPOINT" \
    --namespace "$NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "✓ Secret created: rustfs-credentials"

# Create secret for S3 access
echo "📦 Creating K8s secret: s3-credentials"
kubectl create secret generic s3-credentials \
    --from-literal=access-key="$S3_ROOT_USER" \
    --from-literal=secret-key="$S3_ROOT_PASSWORD" \
    --from-literal=endpoint="$S3_ENDPOINT" \
    --namespace "$NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "✓ Secret created: s3-credentials"

echo ""
echo "✅ Credentials configured!"
echo ""
echo "Secrets created in namespace: $NAMESPACE"
echo "  - rustfs-credentials (for rustfs admin)"
echo "  - s3-credentials (for S3 API access)"
echo ""
echo "Usage in pods:"
echo '  env:'
echo '    - name: S3_ACCESS_KEY'
echo '      valueFrom:'
echo '        secretKeyRef:'
echo '          name: s3-credentials'
echo '          key: access-key'
