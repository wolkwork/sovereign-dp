#!/bin/bash
set -euo pipefail

IMAGE_NAME="sovereign-dp-demo"
IMAGE_TAG="latest"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🐳 Building custom JupyterHub notebook image"

cd "$PROJECT_ROOT"

# Copy notebook to docker context
cp notebooks/trino-iceberg-demo.ipynb notebooks/docker/

# Build the image
echo "📦 Building image: $IMAGE_NAME:$IMAGE_TAG"
docker build -t "$IMAGE_NAME:$IMAGE_TAG" notebooks/docker/

# Load into kind cluster if running
if kind get clusters 2>/dev/null | grep -q "sovereign-dp"; then
    echo "📤 Loading image into kind cluster..."
    kind load docker-image "$IMAGE_NAME:$IMAGE_TAG" --name sovereign-dp
    echo "✅ Image loaded into kind cluster"
else
    echo "⚠️  Kind cluster not running. Load manually with:"
    echo "   kind load docker-image $IMAGE_NAME:$IMAGE_TAG --name sovereign-dp"
fi

# Cleanup
rm -f notebooks/docker/trino-iceberg-demo.ipynb

echo ""
echo "✅ Image built: $IMAGE_NAME:$IMAGE_TAG"
echo ""
echo "To use this image, update JupyterHub:"
echo "  helm upgrade jupyterhub jupyterhub/jupyterhub -n sovereign-dp \\"
echo "    --values k8s/helm-values/jupyterhub-values.yaml --version 3.2.1"
