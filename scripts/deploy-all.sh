#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✅${NC} $1"
}

log_error() {
    echo -e "${RED}❌${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠️ ${NC} $1"
}

log_step() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# Error handler
error_exit() {
    log_error "Deployment failed at: $1"
    log_info "Check the logs above for details"
    exit 1
}

# Change to project root
cd "$PROJECT_ROOT"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║           sovereign-dp Lakehouse Platform Deployment             ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

log_info "This script will deploy the complete sovereign-dp stack:"
log_info "  • Kubernetes (kind) cluster"
log_info "  • Helm package manager"
log_info "  • Pileus namespace"
log_info "  • Nessie catalog server"
log_info "  • rustfs object storage"
log_info "  • Credentials and secrets"
log_info "  • Trino query engine"
log_info "  • JupyterHub notebooks"
log_info "  • Dagster orchestration (optional)"
echo ""

# Check for --with-dagster flag
DEPLOY_DAGSTER=false
for arg in "$@"; do
    if [ "$arg" = "--with-dagster" ]; then
        DEPLOY_DAGSTER=true
    fi
done

# Check Docker resources
check_docker_resources() {
    if command -v docker &> /dev/null; then
        # Get Docker memory limit in GB
        DOCKER_MEM=$(docker info 2>/dev/null | grep "Total Memory" | awk '{print $3}' | sed 's/GiB//')
        if [ -n "$DOCKER_MEM" ]; then
            # Compare as integers (multiply by 10 to handle decimals)
            MEM_INT=$(echo "$DOCKER_MEM * 10" | bc 2>/dev/null | cut -d. -f1 || echo "0")
            MIN_MEM=100  # 10 GB * 10
            REC_MEM=160  # 16 GB * 10

            if [ "$MEM_INT" -lt "$MIN_MEM" ] 2>/dev/null; then
                log_warning "Docker has ${DOCKER_MEM}GB memory allocated"
                log_warning "Minimum recommended: 10GB (16GB for smooth operation)"
                log_warning "Increase via: Docker Desktop → Settings → Resources"
                echo ""
            elif [ "$MEM_INT" -lt "$REC_MEM" ] 2>/dev/null; then
                log_info "Docker has ${DOCKER_MEM}GB memory (16GB recommended for best performance)"
            fi
        fi
    fi
}

check_docker_resources

# Check if running in non-interactive mode
if [ -t 0 ]; then
    read -p "Continue with deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warning "Deployment cancelled"
        exit 0
    fi
else
    log_info "Running in non-interactive mode, proceeding with deployment..."
fi

# Track deployment time
START_TIME=$(date +%s)

# Step 1: Setup Kubernetes cluster
log_step "Step 1/9: Setting up Kubernetes cluster"
if ./scripts/setup-cluster.sh; then
    log_success "Kubernetes cluster ready"
else
    error_exit "Kubernetes cluster setup"
fi

# Step 2: Install Helm
log_step "Step 2/9: Installing Helm"
if ./scripts/install-helm.sh; then
    log_success "Helm ready"
else
    error_exit "Helm installation"
fi

# Add Helm repositories
log_info "Adding Helm repositories..."
helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
helm repo add trino https://trinodb.github.io/charts 2>/dev/null || true
if [ "$DEPLOY_DAGSTER" = true ]; then
    helm repo add dagster https://dagster-io.github.io/helm 2>/dev/null || true
fi
helm repo update > /dev/null 2>&1
log_success "Helm repositories updated"

# Step 3: Create namespace
log_step "Step 3/9: Creating sovereign-dp namespace"
if ./scripts/setup-namespace.sh; then
    log_success "Namespace ready"
else
    error_exit "Namespace creation"
fi

# Step 4: Deploy Nessie
log_step "Step 4/9: Deploying Nessie catalog"
if ./scripts/setup-nessie.sh; then
    log_success "Nessie deployed"
else
    error_exit "Nessie deployment"
fi

# Step 5: Deploy rustfs
log_step "Step 5/9: Deploying rustfs object storage"
if ./scripts/setup-rustfs.sh; then
    log_success "rustfs deployed"
else
    error_exit "rustfs deployment"
fi

# Step 6: Configure credentials
log_step "Step 6/9: Configuring credentials"
if ./scripts/setup-credentials.sh; then
    log_success "Credentials configured"
else
    error_exit "Credentials configuration"
fi

# Step 7: Deploy Trino
log_step "Step 7/9: Deploying Trino query engine"
if ./scripts/setup-trino.sh; then
    log_success "Trino deployed"
else
    error_exit "Trino deployment"
fi

# Step 8: Build notebook image
log_step "Step 8/9: Building notebook image"
if ./scripts/build-notebook-image.sh; then
    log_success "Notebook image built and loaded"
else
    error_exit "Notebook image build"
fi

# Step 9: Deploy JupyterHub
log_step "Step 9/9: Deploying JupyterHub"
if ./scripts/setup-jupyterhub.sh; then
    log_success "JupyterHub deployed"
else
    error_exit "JupyterHub deployment"
fi

# Optional Step 9: Deploy Dagster
if [ "$DEPLOY_DAGSTER" = true ]; then
    log_step "Step 9 (Optional): Deploying Dagster orchestration"
    if ./scripts/setup-dagster.sh; then
        log_success "Dagster deployed"
    else
        error_exit "Dagster deployment"
    fi
fi

# Calculate deployment time
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

# Final summary
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║              🎉 Deployment Successful! 🎉                  ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
log_success "Lakehouse platform is ready!"
log_info "Deployment time: ${MINUTES}m ${SECONDS}s"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Service Access URLs:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  rustfs Console: http://localhost:9001"
echo "  rustfs API:     http://localhost:9000"
echo "  Trino Web UI:   http://localhost:8080"
echo "  JupyterHub:     http://localhost:8888"
if [ "$DEPLOY_DAGSTER" = true ]; then
echo "  Dagster UI:     http://localhost:3000"
fi
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔑 Credentials:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  rustfs Username: rustfsadmin"
echo "  rustfs Password: rustfsadmin"
echo ""
echo "  JupyterHub Username: any"
echo "  JupyterHub Password: jupyter"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧪 Quick Test:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  # Connect to Trino"
echo "  kubectl exec -n sovereign-dp deploy/trino-coordinator -it -- trino"
echo ""
echo "  # Test queries"
echo "  SHOW CATALOGS;"
echo "  CREATE SCHEMA iceberg.demo;"
echo "  CREATE TABLE iceberg.demo.test (id int, name varchar);"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📚 Next Steps:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  1. Access rustfs Console: open http://localhost:9001"
echo "  2. Access Trino Web UI:  open http://localhost:8080"
echo "  3. Access JupyterHub:    open http://localhost:8888"
echo "  4. Run test queries with Trino CLI"
echo "  5. Configure DBeaver connection"
if [ "$DEPLOY_DAGSTER" = false ]; then
echo "  6. Deploy Dagster: ./scripts/deploy-all.sh --with-dagster"
fi
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🛠️  Management:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Check status:  kubectl get pods -n sovereign-dp"
echo "  View logs:     kubectl logs -n sovereign-dp <pod-name>"
echo "  Teardown:      ./scripts/teardown-cluster.sh"
echo ""
