# OpenSearch Kubernetes Deployment

This repository contains Kubernetes configurations for deploying OpenSearch cluster with OpenSearch Dashboards (formerly Kibana).

## Prerequisites

- Kubernetes cluster (tested with Rancher Desktop)
- kubectl command-line tool
- At least 4GB of available memory for the cluster
- Node with vm.max_map_count=262144 (can be set using `sudo sysctl -w vm.max_map_count=262144`)

## Quick Start

1. Clone this repository:
```bash
git clone [repository-url]
cd opensearch-docker-compose
```

2. Set required system settings:
```bash
# On Linux/macOS
sudo sysctl -w vm.max_map_count=262144
```

## Deployment Management

### Starting the Cluster

1. Create required persistent volumes and configmaps:
```bash
kubectl apply -f pv-volume.yaml
kubectl apply -f certificates-pvc.yaml
kubectl apply -f os-data-pvc.yaml
kubectl apply -f os-configmap.yaml
```

2. Deploy OpenSearch nodes and Kibana:
```bash
kubectl apply -f os01-deployment.yaml
kubectl apply -f os02-deployment.yaml
kubectl apply -f os03-deployment.yaml
kubectl apply -f kibana-deployment.yaml
```

3. Monitor the deployment:
```bash
kubectl get pods -w
```

### Port Forwarding

The `manage-ports.sh` script handles port forwarding for accessing OpenSearch and Kibana:

```bash
# Start port forwarding
./manage-ports.sh start

# Check port forwarding status
./manage-ports.sh status

# Stop port forwarding
./manage-ports.sh stop
```

### Service Access

Once port forwarding is active, services are available at:
- OpenSearch API: http://localhost:29201
- Kibana Dashboard: http://localhost:25602

### Stopping the Cluster

1. Stop port forwarding:
```bash
./manage-ports.sh stop
```

2. Delete the deployments:
```bash
kubectl delete -f os01-deployment.yaml
kubectl delete -f os02-deployment.yaml
kubectl delete -f os03-deployment.yaml
kubectl delete -f kibana-deployment.yaml
```

3. Optionally, delete persistent volumes and configs:
```bash
kubectl delete -f os-configmap.yaml
kubectl delete -f os-data-pvc.yaml
kubectl delete -f certificates-pvc.yaml
kubectl delete -f pv-volume.yaml
```

## Cluster Architecture

The deployment consists of:
- 3 OpenSearch nodes (os01, os02, os03) in a cluster
- 1 Kibana instance
- Persistent storage for data and certificates
- Internal services for cluster communication

### Port Configuration

| Service    | Internal Port | Forwarded Port | Description |
|------------|--------------|----------------|-------------|
| OpenSearch | 9200         | 29201          | REST API endpoint |
| OpenSearch | 9300         | -              | Inter-node communication |
| Kibana     | 5601         | 25602          | Dashboard interface |

## Maintenance

### Checking Cluster Health

```bash
# Using curl through port forward
curl http://localhost:29201/_cluster/health

# Using kubectl directly
kubectl exec -it $(kubectl get pod -l io.kompose.service=os01 -o name) -- curl -s http://localhost:9200/_cluster/health
```

### Viewing Logs

```bash
# OpenSearch node logs
kubectl logs -f $(kubectl get pod -l io.kompose.service=os01 -o name)

# Kibana logs
kubectl logs -f $(kubectl get pod -l io.kompose.service=kibana -o name)
```

## Security Notes

- Current deployment has security plugin disabled for development purposes
- For production deployment, enable security plugin and configure proper authentication
- Use proper resource limits based on your environment

## Troubleshooting

### Common Issues

1. Pods not starting:
   - Check system resources
   - Verify vm.max_map_count setting
   - Check pod logs using `kubectl logs`

2. Port forwarding issues:
   - Use `manage-ports.sh status` to check current status
   - Stop and restart port forwarding
   - Check for port conflicts with other services

### Getting Help

For issues:
1. Check pod logs
2. Check cluster health
3. Verify port forwarding status
4. Review Kubernetes events: `kubectl get events --sort-by='.metadata.creationTimestamp'`

