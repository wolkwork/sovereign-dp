#!/bin/bash
set -euo pipefail

NAMESPACE="sovereign-dp"
MANIFEST_FILE="k8s/manifests/nessie-deployment.yaml"

echo "📚 Setting up Nessie catalog in namespace: $NAMESPACE"

# Check prerequisites
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed"
    exit 1
fi

# Check if Nessie is already running
if kubectl get deployment nessie -n "$NAMESPACE" &>/dev/null; then
    READY=$(kubectl get deployment nessie -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [ "$READY" = "1" ]; then
        echo "✅ Nessie is already running in namespace $NAMESPACE"
        exit 0
    fi
fi

# Create Nessie deployment manifest
cat > "$MANIFEST_FILE" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nessie
  namespace: $NAMESPACE
  labels:
    app: nessie
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nessie
  template:
    metadata:
      labels:
        app: nessie
    spec:
      containers:
      - name: nessie
        image: ghcr.io/projectnessie/nessie:0.106.1
        ports:
        - containerPort: 19120
          name: http
        env:
        - name: JAVA_OPTS
          value: "-Xmx512m"
        - name: NESSIE_VERSION_STORE_TYPE
          value: "IN_MEMORY"
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /api/v2/config
            port: 19120
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /api/v2/config
            port: 19120
          initialDelaySeconds: 10
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: nessie
  namespace: $NAMESPACE
  labels:
    app: nessie
spec:
  type: ClusterIP
  ports:
  - port: 19120
    targetPort: 19120
    protocol: TCP
    name: http
  selector:
    app: nessie
EOF

# Apply manifest
echo "📦 Deploying Nessie..."
kubectl apply -f "$MANIFEST_FILE"

# Wait for Nessie to be ready
echo "⏳ Waiting for Nessie to be ready..."
kubectl wait --for=condition=ready pod \
    -l app=nessie \
    -n "$NAMESPACE" \
    --timeout=300s

# Test Nessie API
echo "🧪 Testing Nessie API..."
kubectl exec -n "$NAMESPACE" deploy/nessie -- \
    curl -s http://localhost:19120/api/v2/config | head -n 5 || true

echo ""
echo "✅ Nessie is ready!"
echo ""
echo "📊 Nessie Information:"
echo "   Namespace: $NAMESPACE"
echo "   Service: nessie.sovereign-dp.svc.cluster.local:19120"
echo "   Storage: IN_MEMORY (for development)"
echo ""
echo "🔗 API Endpoints:"
echo "   Config: http://nessie:19120/api/v2/config"
echo "   Trees:  http://nessie:19120/api/v2/trees"
echo ""
echo "Next steps:"
echo "  1. Install Trino: ./scripts/setup-trino.sh"
