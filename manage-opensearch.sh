#!/bin/bash

# Script to manage OpenSearch cluster

# Prevent errors from unset variables
set -u

# Colors for output
READ="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
NC="\033[0m"

# Logging functions
log() { printf "[] \n" "$(date +%Y-%m-%d\ %H:%M:%S)" "$*"; }
log_success() { log "${GREEN}$*${NC}"; }
log_error() { log "${RED}ERROR: $*${NC}" >&2; }
log_warn() { log "${YELLOW}WARNING: $*${NC}"; }

show_status() {
    log "Checking cluster status..."
    kubectl get pvc,configmap,deployment,pod -l "io.kompose.service in (os01,os02,os03,kibana)"
}

show_usage() {
    cat << EOF
Usage: $0 [command]

Commands:
  start   Start the OpenSearch cluster and Kibana
  stop    Stop the OpenSearch cluster and Kibana
  status  Show cluster status
  help    Show this help message
EOF
}

start_cluster() {
    log "Starting cluster..."
    kubectl apply -f storage.yaml
    kubectl apply -f os01.yaml
    kubectl apply -f os02.yaml
    kubectl apply -f os03.yaml
    kubectl apply -f kibana.yaml
}

stop_cluster() {
    log "Stopping cluster..."
    kubectl delete -f kibana.yaml --ignore-not-found
    kubectl delete -f os03.yaml --ignore-not-found
    kubectl delete -f os02.yaml --ignore-not-found
    kubectl delete -f os01.yaml --ignore-not-found
    kubectl delete -f storage.yaml --ignore-not-found
}

case "${1:-help}" in
    start)
        start_cluster
        ;;
    stop)
        stop_cluster
        ;;
    status)
        show_status
        ;;
    help)
        show_usage
        ;;
    *)
        log_error "Unknown command: ${1:-}"
        show_usage
        exit 1
        ;;
esac