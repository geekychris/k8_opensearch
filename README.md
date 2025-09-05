# OpenSearch Kubernetes Deployment

This directory contains a complete OpenSearch cluster deployment for Kubernetes with a 3-node setup and OpenSearch Dashboards.

## 🚀 Quick Start

### Deploy the Cluster
```bash
./deploy-opensearch-minimal.sh
```

### Shutdown the Cluster
```bash
./shutdown-opensearch.sh
```

## 📋 Services and Access Points

All services are exposed to your host computer via NodePort services:

### 🔍 **OpenSearch API**
- **URL**: `http://localhost:30920`
- **Service**: `os01` (primary node)
- **Ports**: 
  - `9200` (HTTP API) → `30920`
  - `9300` (Transport) → `31160` 
  - `9600` (Performance) → `32447`

**Quick Tests:**
```bash
# Cluster health
curl http://localhost:30920/_cluster/health

# Cluster info
curl http://localhost:30920/

# List indices
curl http://localhost:30920/_cat/indices
```

### 📊 **OpenSearch Dashboards**
- **URL**: `http://localhost:30561`
- **Service**: `kibana` (OpenSearch Dashboards)
- **Port**: `5601` → `30561`
- **Authentication**: None (security plugin disabled)

**Access:** Simply visit `http://localhost:30561` in your browser

> **Note**: This is **OpenSearch Dashboards** (not traditional Kibana). It provides the same functionality as Kibana but is specifically designed for OpenSearch. It has the same UI, features, and capabilities you'd expect from Kibana.

### 🗄️ **Additional Services Available**
Your Kubernetes cluster also has these other services available:

- **Redis**: `localhost:31379`
- **MySQL**: `localhost:30306` 
- **Kafka**: `localhost:31992` (primary), `31994` (SSL)
- **Zookeeper**: `localhost:31181`

## 🏗️ Architecture

### **Cluster Configuration**
- **Nodes**: 3 (os01, os02, os03)
- **Replication**: Each node can serve as master, data, and ingest node
- **Security**: Disabled for development (no SSL/TLS)
- **Memory**: 2GB per node with 1GB heap
- **Storage**: Persistent volumes for data

### **Network Setup**
- **Internal**: Nodes communicate via ClusterIP services on port 9300
- **External**: os01 exposed via NodePort for API access
- **Dashboards**: OpenSearch Dashboards connects to all three nodes

## 🔧 Configuration Details

### **kubectl Detection**
The deployment scripts automatically detect and use the appropriate kubectl command:
- **Standard Kubernetes**: Uses `kubectl` command
- **MicroK8s**: Uses `microk8s.kubectl` command
- **Automatic**: No manual configuration needed

When you run the scripts, you'll see:
```bash
./deploy-opensearch-minimal.sh
# Output: Using kubectl command
# OR: Using microk8s.kubectl command
```

### **OpenSearch Configuration**
- **Security Plugin**: Disabled (`DISABLE_SECURITY_PLUGIN=true`)
- **Demo Config**: Disabled (`DISABLE_INSTALL_DEMO_CONFIG=true`)
- **Memory Lock**: Disabled for Kubernetes compatibility
- **Discovery**: Uses service names for cluster formation

### **OpenSearch Dashboards Configuration**
- **Connection**: HTTP (no SSL) to all OpenSearch nodes
- **Authentication**: Disabled (matches OpenSearch security settings)
- **UI**: Full OpenSearch Dashboards functionality available

## 📁 Important Files

### **Deployment Scripts**
- `deploy-opensearch-minimal.sh` - Main deployment script
- `shutdown-opensearch.sh` - Clean shutdown script

### **OpenSearch Node Deployments**
- `os01-deployment.yaml` - Primary node (exposed externally)
- `os02-deployment.yaml` - Secondary node  
- `os03-deployment.yaml` - Tertiary node

### **Services**
- `os01-service.yaml` - NodePort service (external access)
- `os02-service.yaml` - ClusterIP service (internal only)
- `os03-service.yaml` - ClusterIP service (internal only)
- `kibana-service.yaml` - NodePort service for Dashboards

### **Configuration**
- `os01-cm0-configmap.yaml` - OpenSearch node configuration
- `os02-cm0-configmap.yaml` - OpenSearch node configuration  
- `os03-cm0-configmap.yaml` - OpenSearch node configuration
- `kibana-cm1-configmap.yaml` - OpenSearch Dashboards configuration

## 🎯 Usage Examples

### **Basic Data Operations**
```bash
# Create an index
curl -X PUT "http://localhost:30920/my-index"

# Index a document
curl -X POST "http://localhost:30920/my-index/_doc" \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello OpenSearch!", "timestamp": "2025-09-05"}'

# Search documents
curl "http://localhost:30920/my-index/_search"
```

### **Cluster Management**
```bash
# Check cluster health
curl "http://localhost:30920/_cluster/health?pretty"

# View cluster settings  
curl "http://localhost:30920/_cluster/settings?pretty"

# List all nodes
curl "http://localhost:30920/_cat/nodes?v"
```

## 🛠️ Troubleshooting

### **Common Issues**

1. **Pods in CrashLoopBackOff**
   - Check memory limits and requests
   - Verify persistent volume availability
   - Check init container logs

2. **Can't Access Services**
   - Verify NodePort services: `kubectl get svc`
   - Check pod status: `kubectl get pods`
   - Ensure ports aren't blocked by firewall

3. **OpenSearch Dashboards Connection Issues**
   - Verify OpenSearch is healthy: `curl http://localhost:30920/_cluster/health`
   - Check Dashboards logs: `kubectl logs -l io.kompose.service=kibana`

### **Useful Commands**
```bash
# Check all services and their ports
kubectl get svc

# Check all pods status
kubectl get pods -o wide

# View logs for specific service
kubectl logs -l io.kompose.service=os01
kubectl logs -l io.kompose.service=kibana

# Alternative port forward (if needed)
kubectl port-forward svc/os01 9200:9200
kubectl port-forward svc/kibana 5601:5601
```

## ⚠️ Important Notes

### **OpenSearch Dashboards vs Kibana**
This deployment uses **OpenSearch Dashboards**, which is:
- A fork of Kibana specifically designed for OpenSearch
- Provides identical functionality to Kibana (same UI, features, capabilities)
- Compatible with OpenSearch (traditional Kibana 7.13+ cannot connect to OpenSearch)
- Accessible at `http://localhost:30561`

### **Development vs Production**
This setup is configured for **development and testing**:
- Security is disabled
- Single replicas (no high availability)
- Simplified networking
- Basic resource allocation

For **production**, you should:
- Enable security and authentication
- Use StatefulSets instead of Deployments
- Configure proper resource limits and requests
- Set up monitoring and alerting
- Use LoadBalancer or Ingress instead of NodePort
- Enable backup and restore procedures

### **Data Persistence**
- Data is stored in persistent volumes
- Running `./shutdown-opensearch.sh` **WILL DELETE** all data
- For data retention, backup indices before shutdown

### **Compatibility**
- **OpenSearch**: Version 3.0.0
- **OpenSearch Dashboards**: Version 3.0.0 (Kibana-compatible interface)
- **Kubernetes**: Tested on K3s v1.30.6, MicroK8s, and standard Kubernetes
- **kubectl**: Automatically detects `kubectl` or `microk8s.kubectl`
- **Platform**: macOS with Rancher Desktop (also works on Linux with MicroK8s)

---

## 🎉 Ready to Use!

Your OpenSearch cluster is now fully operational with external access:

1. **OpenSearch API**: `http://localhost:30920`
2. **OpenSearch Dashboards**: `http://localhost:30561`

Visit the Dashboards URL in your browser to start exploring and visualizing your data with the full power of the Kibana-compatible interface!
