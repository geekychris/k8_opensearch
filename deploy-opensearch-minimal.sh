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

# Check if cleanup was requested
if [[ "$1" == "clean" ]]; then
    echo "Cleaning up OpenSearch resources..."
    kubectl delete deployment os01 os02 os03 kibana 2>/dev/null || true
    kubectl delete service os01 os02 os03 kibana 2>/dev/null || true
    kubectl delete configmap os01-cm0 os02-cm0 os03-cm0 kibana-cm1 2>/dev/null || true
    kubectl delete job generate-certificates 2>/dev/null || true
    kubectl delete pvc certificates-pvc os-data1 os-data2 os-data3 2>/dev/null || true
    kubectl delete pv certificates-pv 2>/dev/null || true
    echo "Cleanup complete"
    exit 0
fi

# Check for kubectl
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl not found"
    exit 1
fi

echo "Starting OpenSearch deployment..."

# Create storage
echo "Setting up storage..."
kubectl apply -f certificates-pv.yaml
kubectl apply -f certificates-pvc.yaml
kubectl apply -f os-data1-persistentvolumeclaim.yaml
kubectl apply -f os-data2-persistentvolumeclaim.yaml
kubectl apply -f os-data3-persistentvolumeclaim.yaml

# Generate certificates
echo "Generating certificates..."
kubectl apply -f generate-certs-job.yaml
kubectl wait --for=condition=complete job/generate-certificates --timeout=60s

# Deploy configurations
echo "Deploying configurations..."
kubectl apply -f os01-cm0-configmap.yaml
kubectl apply -f os02-cm0-configmap.yaml
kubectl apply -f os03-cm0-configmap.yaml
kubectl apply -f kibana-cm1-configmap.yaml

# Create services
echo "Creating services..."
kubectl apply -f os01-service.yaml
kubectl apply -f os02-service.yaml
kubectl apply -f os03-service.yaml
kubectl apply -f kibana-service.yaml

# Deploy OpenSearch nodes
echo "Deploying OpenSearch nodes..."
kubectl apply -f os01-deployment.yaml
kubectl apply -f os02-deployment.yaml
kubectl apply -f os03-deployment.yaml

# Wait for OpenSearch nodes
echo "Waiting for OpenSearch nodes..."
kubectl wait --for=condition=ready pod -l io.kompose.service=os01 --timeout=300s
kubectl wait --for=condition=ready pod -l io.kompose.service=os02 --timeout=300s
kubectl wait --for=condition=ready pod -l io.kompose.service=os03 --timeout=300s

# Deploy Dashboards
echo "Deploying OpenSearch Dashboards..."
kubectl apply -f kibana-deployment.yaml
kubectl wait --for=condition=ready pod -l io.kompose.service=kibana --timeout=300s

echo "Deployment complete!"
echo "
Access the cluster:
1. OpenSearch API:
   kubectl port-forward svc/os01 9200:9200
   curl -k -u admin:admin https://localhost:9200

2. OpenSearch Dashboards:
   kubectl port-forward svc/kibana 5601:5601
   Visit https://localhost:5601
   Login with admin:admin"

