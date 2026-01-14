#!/bin/bash
set -euo pipefail

NAMESPACE="sovereign-dp"
MANIFEST_FILE="k8s/manifests/rustfs-deployment.yaml"

echo "🦀 Setting up rustfs in namespace: $NAMESPACE"

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
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    echo "📁 Creating namespace $NAMESPACE..."
    kubectl create namespace "$NAMESPACE"
fi

# Create rustfs deployment manifest
mkdir -p k8s/manifests
cat > "$MANIFEST_FILE" <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: rustfs-data
  namespace: sovereign-dp
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rustfs
  namespace: sovereign-dp
  labels:
    app: rustfs
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rustfs
  template:
    metadata:
      labels:
        app: rustfs
    spec:
      securityContext:
        fsGroup: 10001
      containers:
      - name: rustfs
        image: rustfs/rustfs:latest
        ports:
        - containerPort: 9000
          name: s3
        - containerPort: 9001
          name: console
        env:
        - name: RUSTFS_ROOT_USER
          value: "rustfsadmin"
        - name: RUSTFS_ROOT_PASSWORD
          value: "rustfsadmin"
        volumeMounts:
        - name: data
          mountPath: /data
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "1"
        livenessProbe:
          tcpSocket:
            port: 9000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          tcpSocket:
            port: 9000
          initialDelaySeconds: 10
          periodSeconds: 5
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: rustfs-data
---
apiVersion: v1
kind: Service
metadata:
  name: rustfs
  namespace: sovereign-dp
  labels:
    app: rustfs
spec:
  type: NodePort
  ports:
  - port: 9000
    targetPort: 9000
    nodePort: 30900
    protocol: TCP
    name: s3
  - port: 9001
    targetPort: 9001
    nodePort: 30901
    protocol: TCP
    name: console
  selector:
    app: rustfs
EOF

# Apply manifest
echo "📦 Deploying rustfs..."
kubectl apply -f "$MANIFEST_FILE"

# Wait for rustfs to be ready
echo "⏳ Waiting for rustfs to be ready..."
kubectl wait --for=condition=ready pod \
    -l app=rustfs \
    -n "$NAMESPACE" \
    --timeout=300s

# Create the sovereign-dp bucket for Iceberg warehouse
echo "🪣 Creating sovereign-dp bucket..."
sleep 5  # Give rustfs a moment to fully initialize

# Create bucket using Python in a temporary pod
kubectl run bucket-init -n "$NAMESPACE" --restart=Never --image=python:3.11-slim \
    --env="AWS_ACCESS_KEY_ID=rustfsadmin" \
    --env="AWS_SECRET_ACCESS_KEY=rustfsadmin" \
    --command -- sh -c '
pip install -q boto3 && python3 -c "
import boto3
from botocore.config import Config
s3 = boto3.client(\"s3\", endpoint_url=\"http://rustfs:9000\",
    config=Config(signature_version=\"s3v4\"), region_name=\"us-east-1\")
try:
    s3.create_bucket(Bucket=\"sovereign-dp\")
    print(\"Created bucket: sovereign-dp\")
except Exception as e:
    if \"BucketAlreadyOwnedByYou\" in str(e) or \"BucketAlreadyExists\" in str(e):
        print(\"Bucket already exists\")
    else:
        print(f\"Error: {e}\")
"' 2>/dev/null

# Wait for bucket creation to complete
echo "⏳ Waiting for bucket creation..."
kubectl wait --for=condition=Ready pod/bucket-init -n "$NAMESPACE" --timeout=120s 2>/dev/null || true
sleep 10
kubectl logs bucket-init -n "$NAMESPACE" 2>/dev/null || true
kubectl delete pod bucket-init -n "$NAMESPACE" --ignore-not-found 2>/dev/null || true

echo ""
echo "✅ rustfs is ready!"
echo ""
echo "📊 rustfs Information:"
echo "   Namespace: $NAMESPACE"
echo "   Service: rustfs.sovereign-dp.svc.cluster.local"
echo ""
echo "🔗 Access URLs:"
echo "   S3 API:   http://localhost:9000"
echo "   Console:  http://localhost:9001"
echo ""
echo "🔑 Credentials:"
echo "   Username: rustfsadmin"
echo "   Password: rustfsadmin"
echo ""
echo "Next steps:"
echo "  1. Configure credentials: ./scripts/setup-credentials.sh"
echo "  2. Install Trino: ./scripts/setup-trino.sh"
echo "  3. Access console: open http://localhost:9001"
