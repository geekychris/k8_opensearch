#!/bin/bash

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy or clean up OpenSearch cluster in Kubernetes.

Options:
    -h, --help      Show this help message
    --cleanup       Remove all OpenSearch resources
    --force         Skip confirmation prompts during cleanup

Example:
    $0              Deploy OpenSearch cluster
    $0 --cleanup    Remove OpenSearch cluster and all related resources
EOF
}

# Function to print status messages
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

# Function to check system requirements
check_system_requirements() {
    log "Checking system requirements..."
    
    # Get OS type
    local os_type
    case "$(uname -s)" in
        Linux*)     os_type=Linux;;
        Darwin*)    os_type=Mac;;
        *)         os_type=Other;;
    esac
    
    # Check system requirements based on OS type
    if [[ "$os_type" == "Linux" ]]; then
        # Check vm.max_map_count
        local max_map_count
        max_map_count=$(sysctl -n vm.max_map_count 2>/dev/null || echo 0)
        if [[ "$max_map_count" -lt 262144 ]]; then
            warn "vm.max_map_count is too low ($max_map_count). OpenSearch requires at least 262144"
            warn "To fix this, run:"
            warn "sudo sysctl -w vm.max_map_count=262144"
            warn "To make it permanent, add this line to /etc/sysctl.conf:"
            warn "vm.max_map_count = 262144"
            return 1
        fi
    elif [[ "$os_type" == "Mac" ]]; then
        warn "Running on macOS. Ensure Docker Desktop has sufficient resources:"
        warn "1. Open Docker Desktop preferences"
        warn "2. Go to 'Resources' tab"
        warn "3. Ensure at least 4GB RAM is allocated"
        warn "4. Add these lines to ~/.docker/daemon.json:"
        warn '{
  "default-ulimits": {
    "memlock": {
      "name": "memlock",
      "hard": -1,
      "soft": -1
    }
  }
}'
        read -p "Have you configured Docker Desktop with these settings? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            error "Please configure Docker Desktop with the required settings and try again"
            return 1
        fi
    else
        error "Unsupported operating system: $(uname -s)"
        return 1
    fi
    
    # Check if kubectl context is set to a reachable cluster
    if ! kubectl cluster-info &>/dev/null; then
        error "Cannot reach Kubernetes cluster. Please check your kubectl configuration"
        return 1
    fi
    
    # Check if nodes have enough resources
    local total_memory=0
    local total_cpu=0
    
    while IFS= read -r line; do
        if [[ $line =~ ([0-9]+)Ki ]]; then
            total_memory=$((total_memory + ${BASH_REMATCH[1]}))
        fi
    done < <(kubectl get nodes -o jsonpath='{.items[*].status.allocatable.memory}')
    
    while IFS= read -r line; do
        if [[ $line =~ ([0-9]+)m ]]; then
            total_cpu=$((total_cpu + ${BASH_REMATCH[1]}))
        fi
    done < <(kubectl get nodes -o jsonpath='{.items[*].status.allocatable.cpu}')
    
    total_memory=$((total_memory / 1024 / 1024)) # Convert to GB
    total_cpu=$((total_cpu / 1000)) # Convert to cores
    
    if [[ "$total_memory" -lt 8 ]]; then
        warn "Cluster has less than 8GB total memory ($total_memory GB)"
        warn "OpenSearch cluster may not perform optimally"
    fi
    
    if [[ "$total_cpu" -lt 4 ]]; then
        warn "Cluster has less than 4 CPU cores ($total_cpu cores)"
        warn "OpenSearch cluster may not perform optimally"
    fi
    
    log "System requirements check completed"
    return 0
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

# Function to check if a resource exists
resource_exists() {
    kubectl get $1 $2 &> /dev/null
}

# Function to wait for a job to complete
wait_for_job() {
    local job_name=$1
    local timeout=${2:-300}  # Default timeout of 300 seconds
    log "Waiting for job $job_name to complete..."
    
    kubectl wait --for=condition=complete job/$job_name --timeout=${timeout}s || {
        error "Job $job_name failed to complete within $timeout seconds"
        kubectl logs -l job-name=$job_name
        return 1
    }
}

# Function to wait for pod readiness
wait_for_pods() {
    local label=$1
    local count=$2
    local timeout=${3:-300}  # Default timeout of 300 seconds
    
    log "Waiting for $count pods with label $label to be ready..."
    kubectl wait --for=condition=ready pod -l $label --timeout=${timeout}s || {
        error "Pods with label $label failed to become ready within $timeout seconds"
        kubectl get pods -l $label
        return 1
    }
}

# Function to backup certificates if they exist
backup_certificates() {
    local backup_dir="/tmp/opensearch-certs-backup-$(date +%Y%m%d_%H%M%S)"
    
    # Create a temporary pod to check and backup certificates
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: cert-backup
spec:
  containers:
  - name: backup
    image: busybox
    command: ['sleep', '3600']
    volumeMounts:
    - name: cert-volume
      mountPath: /certs
  volumes:
  - name: cert-volume
    persistentVolumeClaim:
      claimName: certificates-pvc
EOF
    
    # Wait for backup pod to be ready
    kubectl wait --for=condition=ready pod/cert-backup --timeout=30s || {
        warn "Failed to create backup pod, continuing without backup"
        kubectl delete pod cert-backup --force 2>/dev/null || true
        return 0
    }
    
    # Check if certificates exist and create backup
    if kubectl exec cert-backup -- test -d /certs/ca; then
        log "Found existing certificates, creating backup at $backup_dir"
        mkdir -p "$backup_dir"
        kubectl cp cert-backup:/certs/. "$backup_dir"
        log "Certificates backed up to $backup_dir"
    fi
    
    # Cleanup backup pod
    kubectl delete pod cert-backup --force
}

# Function to remove all OpenSearch resources
cleanup_all() {
    log "Preparing to remove all OpenSearch resources..."
    
    if [[ "$FORCE_CLEANUP" != "true" ]]; then
        warn "This will remove ALL OpenSearch resources, including:"
        warn "- All OpenSearch and Dashboards pods"
        warn "- All services and configmaps"
        warn "- All PersistentVolumeClaims and data"
        warn "- All certificates"
        echo
        read -p "Are you sure you want to proceed? (yes/no) " -r
        echo
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log "Cleanup cancelled"
            exit 0
        fi
    fi
    
    # Backup certificates if they exist
    if resource_exists pvc certificates-pvc; then
        backup_certificates
    fi
    
    log "Removing OpenSearch deployments..."
    kubectl delete deployment os01 os02 os03 2>/dev/null || true
    
    log "Removing OpenSearch Dashboards deployment..."
    kubectl delete deployment kibana 2>/dev/null || true
    
    log "Removing services..."
    kubectl delete service os01 os02 os03 kibana 2>/dev/null || true
    
    log "Removing configmaps..."
    kubectl delete configmap os01-cm0 os02-cm0 os03-cm0 kibana-cm1 2>/dev/null || true
    
    log "Removing certificate job..."
    kubectl delete job generate-certificates 2>/dev/null || true
    
    log "Removing PVCs..."
    kubectl delete pvc certificates-pvc 2>/dev/null || true
    kubectl delete pvc os-data1 os-data2 os-data3 2>/dev/null || true
    
    log "Removing PV..."
    kubectl delete pv certificates-pv 2>/dev/null || true
    
    log "Waiting for resources to be removed..."
    sleep 5
    
    log "Cleanup completed successfully"
    if [[ -d "$BACKUP_DIR" ]]; then
        log "Certificates were backed up to: $BACKUP_DIR"
    fi
}

# Clean up existing certificate resources
cleanup_certs() {
    log "Checking for existing resources..."
    
    local resources_exist=false
    
    # Check for existing resources
    if resource_exists job generate-certificates || \
       resource_exists pvc certificates-pvc || \
       resource_exists pv certificates-pv; then
        resources_exist=true
        warn "Found existing OpenSearch resources"
    fi
    
    # If resources exist, try to backup certificates
    if [ "$resources_exist" = true ]; then
        warn "This script will delete existing certificates and resources"
        warn "You have 10 seconds to cancel (Ctrl+C) if this is not intended..."
        sleep 10
        
        if resource_exists pvc certificates-pvc; then
            backup_certificates
        fi
    fi
    
    # Delete resources if they exist
    resource_exists job generate-certificates && {
        log "Removing existing certificate generation job..."
        kubectl delete job generate-certificates
    }
    
    resource_exists pvc certificates-pvc && {
        log "Removing existing certificate PVC..."
        kubectl delete pvc certificates-pvc
    }
    
    resource_exists pv certificates-pv && {
        log "Removing existing certificate PV..."
        kubectl delete pv certificates-pv
    }
    
    # Wait for resources to be deleted
    sleep 5
    
    if [ "$resources_exist" = true ]; then
        log "Cleanup completed. Any existing certificates have been backed up"
    fi
}

# Deploy storage resources
deploy_storage() {
    log "Deploying storage resources..."
    
    kubectl apply -f certificates-pv.yaml
    kubectl apply -f certificates-pvc.yaml
    
    log "Storage resources created - PVC will bind automatically when the certificate generation job starts"
}

# Generate certificates
generate_certificates() {
    log "Generating certificates..."
    
    kubectl apply -f generate-certs-job.yaml
    wait_for_job generate-certificates || return 1
    
    log "Certificates generated successfully"
}

# Deploy OpenSearch configuration
deploy_config() {
    log "Deploying OpenSearch configuration..."
    
    kubectl apply -f os01-cm0-configmap.yaml
    kubectl apply -f os02-cm0-configmap.yaml
    kubectl apply -f os03-cm0-configmap.yaml
    kubectl apply -f kibana-cm1-configmap.yaml
}

# Deploy OpenSearch services
deploy_services() {
    log "Deploying OpenSearch services..."
    
    kubectl apply -f os01-service.yaml
    kubectl apply -f os02-service.yaml
    kubectl apply -f os03-service.yaml
    kubectl apply -f kibana-service.yaml
}

# Deploy data PVCs
deploy_data_pvcs() {
    log "Deploying data PVCs..."
    
    kubectl apply -f os-data1-persistentvolumeclaim.yaml
    kubectl apply -f os-data2-persistentvolumeclaim.yaml
    kubectl apply -f os-data3-persistentvolumeclaim.yaml
    
    log "Data PVCs created - they will bind automatically when the OpenSearch pods are created"
}

# Deploy OpenSearch nodes
deploy_nodes() {
    log "Deploying OpenSearch nodes..."
    
    kubectl apply -f os01-deployment.yaml
    kubectl apply -f os02-deployment.yaml
    kubectl apply -f os03-deployment.yaml
    
    # Wait for OpenSearch pods to be ready
    wait_for_pods "io.kompose.service in (os01,os02,os03)" 3 300 || return 1
}

# Deploy OpenSearch Dashboards
deploy_dashboards() {
    log "Deploying OpenSearch Dashboards..."
    
    kubectl apply -f kibana-deployment.yaml
    
    # Wait for Dashboards pod to be ready
    wait_for_pods "io.kompose.service=kibana" 1 300 || return 1
}

# Verify deployment
verify_deployment() {
    log "Verifying deployment..."
    
    # Wait for pods to stabilize
    sleep 30
    
    # Check OpenSearch cluster health
    log "Checking OpenSearch cluster health..."
    kubectl exec $(kubectl get pod -l io.kompose.service=os01 -o jsonpath='{.items[0].metadata.name}') -- \
        curl -ks -u admin:admin https://localhost:9200/_cluster/health | grep -q '"status":"green"' || {
        error "Cluster health check failed"
        return 1
    }
    
    log "Deployment verification completed successfully"
}

# Main deployment process
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --cleanup)
                CLEANUP_MODE="true"
                shift
                ;;
            --force)
                FORCE_CLEANUP="true"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Ensure kubectl is available
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not available"
        exit 1
    fi
    
    # Handle cleanup mode
    if [[ "$CLEANUP_MODE" == "true" ]]; then
        cleanup_all
        exit 0
    fi
    
    # Check system requirements
    check_system_requirements || {
        error "System requirements check failed"
        exit 1
    }
    
    # Check if required files exist
    local required_files=(
        # Certificate storage
        "certificates-pv.yaml"
        "certificates-pvc.yaml"
        "generate-certs-job.yaml"
        
        # ConfigMaps
        "os01-cm0-configmap.yaml"
        "os02-cm0-configmap.yaml"
        "os03-cm0-configmap.yaml"
        "kibana-cm1-configmap.yaml"
        
        # Services
        "os01-service.yaml"
        "os02-service.yaml"
        "os03-service.yaml"
        "kibana-service.yaml"
        
        # Data Storage
        "os-data1-persistentvolumeclaim.yaml"
        "os-data2-persistentvolumeclaim.yaml"
        "os-data3-persistentvolumeclaim.yaml"
        
        # Deployments
        "os01-deployment.yaml"
        "os02-deployment.yaml"
        "os03-deployment.yaml"
        "kibana-deployment.yaml"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            error "Required file $file not found"
            exit 1
        fi
    done
    
    # Start deployment process
    log "Starting OpenSearch deployment..."
    
    cleanup_certs
    deploy_storage || exit 1
    generate_certificates || exit 1
    deploy_config || exit 1
    deploy_services || exit 1
    deploy_data_pvcs || exit 1
    deploy_nodes || exit 1
    deploy_dashboards || exit 1
    verify_deployment || exit 1
    
    log "OpenSearch deployment completed successfully!"
    log "You can access OpenSearch Dashboards at https://localhost:5601"
    log "Default credentials: admin/admin"
}

# Run the script
main "$@"

