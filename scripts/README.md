# sovereign-dp Setup Scripts

Scripts for setting up and managing the local lakehouse development environment.

## Prerequisites

- Docker (required for kind)
- kubectl
- Helm

## Quick Start

### All-in-One Deployment

For the fastest setup, use the all-in-one deployment script:

```bash
./scripts/deploy-all.sh
```

This script orchestrates the complete deployment sequence with:
- Automatic dependency checking
- Progress tracking and clear feedback
- Error handling with helpful messages
- Deployment time tracking
- Final summary with access URLs

**Features:**
- ✅ Deploys entire stack in correct order
- ✅ Validates each step before proceeding
- ✅ Provides colored output for readability
- ✅ Shows deployment summary with service URLs
- ✅ Non-interactive mode support for CI/CD

### Individual Scripts

For more control or troubleshooting, run scripts individually:

### 1. Set up Kubernetes Cluster

```bash
./scripts/setup-cluster.sh
```

Creates a kind cluster with:
- 1 control plane node
- 2 worker nodes
- Port mappings for rustfs (9000, 9001) and Trino (8080)
- Cluster name: `sovereign-dp`

### 2. Install Helm

```bash
./scripts/install-helm.sh
```

Installs Helm 3 if not already present.

### 3. Set up rustfs

```bash
./scripts/setup-rustfs.sh
```

Deploys rustfs to the cluster with:
- S3-compatible object storage
- sovereign-dp bucket pre-created
- NodePort services for access

### 4. Install Trino

```bash
./scripts/setup-trino.sh
```

Deploys Trino query engine configured for:
- Iceberg table format
- rustfs as object storage backend
- Nessie as catalog

### 5. Install Nessie

```bash
./scripts/setup-nessie.sh
```

Deploys Nessie catalog server for Iceberg table versioning.

### 6. Install JupyterHub (Optional)

```bash
./scripts/setup-jupyterhub.sh
```

Deploys JupyterHub for interactive notebook-based SQL queries. Includes:
- Jupyter notebooks with Python kernel
- Pre-installed packages: trino, pandas, matplotlib, seaborn, plotly
- SQL magic commands for inline queries
- Trino connection pre-configured
- Access at http://localhost:8888 (user: any, password: jupyter)

### 7. Install Dagster (Optional)

```bash
./scripts/setup-dagster.sh
```

Deploys Dagster data orchestration platform. Includes:
- PostgreSQL database for Dagster metadata
- Dagster webserver, daemon, and user code deployments
- Pre-configured resources for Trino and rustfs
- Demo assets for Iceberg table operations
- Access at http://localhost:3000

## Management Scripts

### Full Deployment

```bash
./scripts/deploy-all.sh
# Or with Dagster:
./scripts/deploy-all.sh --with-dagster
```

Deploys the complete lakehouse stack in one command. Includes:
- Dependency checking and validation
- Automated step sequencing
- Progress tracking with colored output
- Error handling with clear messages
- Final summary with service URLs and credentials

### Teardown

```bash
./scripts/teardown-cluster.sh
```

Completely removes the kind cluster and all resources.

## Configuration Files

- `kind-config.yaml`: Kind cluster configuration
- `k8s/manifests/`: Kubernetes manifests
- `k8s/helm-values/`: Helm values files for services

## Ports

- **9000**: rustfs API (S3-compatible)
- **9001**: rustfs Console (Web UI)
- **8080**: Trino Web UI
- **8888**: JupyterHub (notebooks)
- **3000**: Dagster UI (optional)
