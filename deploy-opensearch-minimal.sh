#!/bin/bash

# deploy-opensearch-minimal.sh
#
# Minimal script for deploying OpenSearch on Kubernetes.
# Use this for testing or simple deployments.
# For production, use the full deploy-opensearch.sh script.
#
# Usage:
#   ./deploy-opensearch-minimal.sh         # Deploy OpenSearch
#   ./deploy-opensearch-minimal.sh clean   # Remove OpenSearch

set -e  # Exit on error

# Function to detect and set the kubectl command
detect_kubectl() {
    if command -v kubectl &> /dev/null; then
        KUBECTL="kubectl"
        echo "Using kubectl command"
    elif command -v microk8s.kubectl &> /dev/null; then
        KUBECTL="microk8s.kubectl"
        echo "Using microk8s.kubectl command"
    else
        echo "Error: Neither kubectl nor microk8s.kubectl found"
        echo "Please install kubectl or microk8s"
        exit 1
    fi
}

# Detect kubectl command
detect_kubectl

# Check if cleanup was requested
if [[ "$1" == "clean" ]]; then
    echo "Cleaning up OpenSearch resources..."
    $KUBECTL delete deployment os01 os02 os03 kibana 2>/dev/null || true
    $KUBECTL delete service os01 os02 os03 kibana 2>/dev/null || true
    $KUBECTL delete configmap os01-cm0 os02-cm0 os03-cm0 kibana-cm1 2>/dev/null || true
    $KUBECTL delete job generate-certificates 2>/dev/null || true
    $KUBECTL delete pvc certificates-pvc os-data1 os-data2 os-data3 2>/dev/null || true
    $KUBECTL delete pv certificates-pv 2>/dev/null || true
    echo "Cleanup complete"
    exit 0
fi

echo "Starting OpenSearch deployment..."

# Create storage
echo "Setting up storage..."
$KUBECTL apply -f certificates-pv.yaml
$KUBECTL apply -f certificates-pvc.yaml
$KUBECTL apply -f os-data1-persistentvolumeclaim.yaml
$KUBECTL apply -f os-data2-persistentvolumeclaim.yaml
$KUBECTL apply -f os-data3-persistentvolumeclaim.yaml

# Generate certificates
echo "Generating certificates..."
$KUBECTL apply -f generate-certs-job.yaml
$KUBECTL wait --for=condition=complete job/generate-certificates --timeout=60s

# Deploy configurations
echo "Deploying configurations..."
$KUBECTL apply -f os01-cm0-configmap.yaml
$KUBECTL apply -f os02-cm0-configmap.yaml
$KUBECTL apply -f os03-cm0-configmap.yaml
$KUBECTL apply -f kibana-cm1-configmap.yaml

# Create services
echo "Creating services..."
$KUBECTL apply -f os01-service.yaml
$KUBECTL apply -f os02-service.yaml
$KUBECTL apply -f os03-service.yaml
$KUBECTL apply -f kibana-service.yaml

# Deploy OpenSearch nodes
echo "Deploying OpenSearch nodes..."
$KUBECTL apply -f os01-deployment.yaml
$KUBECTL apply -f os02-deployment.yaml
$KUBECTL apply -f os03-deployment.yaml

# Wait for OpenSearch nodes
echo "Waiting for OpenSearch nodes..."
$KUBECTL wait --for=condition=ready pod -l io.kompose.service=os01 --timeout=300s
$KUBECTL wait --for=condition=ready pod -l io.kompose.service=os02 --timeout=300s
$KUBECTL wait --for=condition=ready pod -l io.kompose.service=os03 --timeout=300s

# Deploy Dashboards
echo "Deploying OpenSearch Dashboards..."
$KUBECTL apply -f kibana-deployment.yaml
$KUBECTL wait --for=condition=ready pod -l io.kompose.service=kibana --timeout=300s

echo "Deployment complete!"
echo "
Access the cluster:
1. OpenSearch API: http://localhost:30920
   Test with: curl http://localhost:30920/_cluster/health

2. OpenSearch Dashboards: http://localhost:30561
   Visit in your browser (no login required)

Alternatively, use port-forwarding:
   $KUBECTL port-forward svc/os01 9200:9200
   $KUBECTL port-forward svc/kibana 5601:5601"

