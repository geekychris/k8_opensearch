#!/bin/bash

# shutdown-opensearch.sh
#
# Script to shut down all Kubernetes services that were started 
# with the deploy-opensearch-minimal.sh script.
#
# This script will remove:
# - Deployments: os01, os02, os03, kibana
# - Services: os01, os02, os03, kibana
# - ConfigMaps: os01-cm0, os02-cm0, os03-cm0, kibana-cm1
# - Jobs: generate-certificates
# - PVCs: certificates-pvc, os-data1, os-data2, os-data3
# - PVs: certificates-pv
#
# Usage:
#   ./shutdown-opensearch.sh

set -e  # Exit on error

echo "Shutting down OpenSearch Kubernetes services..."

# Check for kubectl
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl not found"
    exit 1
fi

# Function to safely delete resources
delete_resource() {
    local resource_type=$1
    local resource_name=$2
    
    echo "Deleting $resource_type: $resource_name"
    kubectl delete $resource_type $resource_name 2>/dev/null || {
        echo "  Warning: $resource_type $resource_name not found or already deleted"
    }
}

# Delete deployments
echo "Removing deployments..."
delete_resource "deployment" "os01"
delete_resource "deployment" "os02" 
delete_resource "deployment" "os03"
delete_resource "deployment" "kibana"

# Delete services
echo "Removing services..."
delete_resource "service" "os01"
delete_resource "service" "os02"
delete_resource "service" "os03"
delete_resource "service" "kibana"

# Delete configmaps
echo "Removing configmaps..."
delete_resource "configmap" "os01-cm0"
delete_resource "configmap" "os02-cm0"
delete_resource "configmap" "os03-cm0"
delete_resource "configmap" "kibana-cm1"

# Delete jobs
echo "Removing jobs..."
delete_resource "job" "generate-certificates"

# Delete persistent volume claims
echo "Removing persistent volume claims..."
delete_resource "pvc" "certificates-pvc"
delete_resource "pvc" "os-data1"
delete_resource "pvc" "os-data2"
delete_resource "pvc" "os-data3"

# Delete persistent volumes
echo "Removing persistent volumes..."
delete_resource "pv" "certificates-pv"

echo ""
echo "✅ OpenSearch shutdown complete!"
echo ""
echo "All Kubernetes resources created by deploy-opensearch-minimal.sh have been removed."
echo "Note: Any data stored in the persistent volumes has been deleted."
