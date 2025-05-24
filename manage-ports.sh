#!/bin/bash

# Default port configurations
OS_LOCAL_PORT=29201
OS_REMOTE_PORT=9200
KIBANA_LOCAL_PORT=25602
KIBANA_REMOTE_PORT=5601

# Function to display usage
usage() {
    echo "Usage: $0 [start|stop|status]"
    echo
    echo "Commands:"
    echo "  start   - Start port forwarding for OpenSearch and Kibana"
    echo "  stop    - Stop all port forwarding processes"
    echo "  status  - Show current port forwarding status"
    echo
    echo "Port Mappings:"
    echo "  OpenSearch: localhost:${OS_LOCAL_PORT} -> ${OS_REMOTE_PORT}"
    echo "  Kibana:     localhost:${KIBANA_LOCAL_PORT} -> ${KIBANA_REMOTE_PORT}"
}

# Function to check if a port is in use
is_port_in_use() {
    local port=$1
    if lsof -i :${port} > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to start port forwarding
start_forwarding() {
    echo "Starting port forwarding..."
    
    # Check if ports are already in use
    if is_port_in_use ${OS_LOCAL_PORT}; then
        echo "Port ${OS_LOCAL_PORT} is already in use. Please stop existing port forwards first."
        return 1
    fi
    
    if is_port_in_use ${KIBANA_LOCAL_PORT}; then
        echo "Port ${KIBANA_LOCAL_PORT} is already in use. Please stop existing port forwards first."
        return 1
    fi
    
    # Start OpenSearch port forwarding
    kubectl port-forward service/os01 ${OS_LOCAL_PORT}:${OS_REMOTE_PORT} > /dev/null 2>&1 &
    OS_PID=$!
    echo "OpenSearch port forwarding started (PID: ${OS_PID})"
    
    # Start Kibana port forwarding
    kubectl port-forward service/kibana ${KIBANA_LOCAL_PORT}:${KIBANA_REMOTE_PORT} > /dev/null 2>&1 &
    KIBANA_PID=$!
    echo "Kibana port forwarding started (PID: ${KIBANA_PID})"
    
    # Wait a moment to ensure ports are ready
    sleep 2
    
    echo
    echo "Port forwarding is active:"
    echo "OpenSearch: http://localhost:${OS_LOCAL_PORT}"
    echo "Kibana:     http://localhost:${KIBANA_LOCAL_PORT}"
}

# Function to stop port forwarding
stop_forwarding() {
    echo "Stopping port forwarding..."
    pkill -f "kubectl port-forward"
    sleep 2
    # Double check and force kill if necessary
    if pgrep -f "kubectl port-forward" > /dev/null; then
        pkill -9 -f "kubectl port-forward"
    fi
    echo "All port forwarding processes have been stopped"
}

# Function to show port forwarding status
show_status() {
    echo "Current port forwarding status:"
    echo
    if is_port_in_use ${OS_LOCAL_PORT}; then
        echo "OpenSearch: ACTIVE (http://localhost:${OS_LOCAL_PORT})"
        curl -s "http://localhost:${OS_LOCAL_PORT}/_cluster/health" > /dev/null 2>&1 && echo "           Cluster is responding"
    else
        echo "OpenSearch: INACTIVE"
    fi
    
    if is_port_in_use ${KIBANA_LOCAL_PORT}; then
        echo "Kibana: ACTIVE (http://localhost:${KIBANA_LOCAL_PORT})"
    else
        echo "Kibana: INACTIVE"
    fi
}

# Main script logic
case "$1" in
    start)
        stop_forwarding  # Always stop existing forwards before starting
        sleep 2
        start_forwarding
        ;;
    stop)
        stop_forwarding
        ;;
    status)
        show_status
        ;;
    *)
        usage
        exit 1
        ;;
esac

exit 0
