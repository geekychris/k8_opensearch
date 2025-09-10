#!/bin/bash

# Troubleshooting script for certificate generation timeouts
# Usage: ./troubleshoot-certs.sh

echo "=== OpenSearch Certificate Generation Troubleshooting ==="
echo "Date: $(date)"
echo ""

echo "1. Checking Kubernetes cluster status..."
kubectl cluster-info --request-timeout=10s
if [ $? -ne 0 ]; then
    echo "❌ Kubernetes cluster is not accessible"
    exit 1
fi
echo "✅ Kubernetes cluster is accessible"
echo ""

echo "2. Checking for existing certificate generation jobs..."
kubectl get jobs -l app=generate-certificates 2>/dev/null || echo "No existing jobs found"
kubectl get jobs | grep -i cert || echo "No certificate-related jobs found"
echo ""

echo "3. Checking PVC status..."
kubectl get pvc certificates-pvc
if [ $? -ne 0 ]; then
    echo "❌ certificates-pvc not found - this must be created first"
    echo "Run: kubectl apply -f certificates-pvc.yaml"
    exit 1
fi
echo ""

echo "4. Checking node resources..."
kubectl top nodes 2>/dev/null || echo "Metrics server not available - cannot check resource usage"
echo ""

echo "5. Checking network connectivity (testing with a simple pod)..."
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: network-test
spec:
  containers:
  - name: test
    image: alpine:3.18
    command: ['sh', '-c', 'wget -T 10 -O /dev/null https://archive.ubuntu.com/ && echo "Network OK" || echo "Network FAILED"']
  restartPolicy: Never
EOF

echo "Waiting for network test to complete..."
sleep 10
kubectl logs network-test 2>/dev/null || echo "Network test pod not ready yet"
kubectl delete pod network-test --ignore-not-found=true
echo ""

echo "6. Checking for failed certificate generation attempts..."
for pod in $(kubectl get pods -l job-name --no-headers 2>/dev/null | grep generate-cert | awk '{print $1}'); do
    echo "Logs for $pod:"
    kubectl logs $pod --tail=20
    echo "---"
done
echo ""

echo "=== Recommendations ==="
echo ""
echo "If experiencing timeouts, try these solutions in order:"
echo ""
echo "🚀 SOLUTION 1 - Use the Alpine-based job (fastest, no network dependencies):"
echo "   kubectl delete job generate-certificates generate-certificates-v2 --ignore-not-found=true"
echo "   kubectl apply -f generate-certs-job-alpine.yaml"
echo ""
echo "🔄 SOLUTION 2 - Use the improved Ubuntu job with timeouts:"
echo "   kubectl delete job generate-certificates generate-certificates-alpine --ignore-not-found=true"
echo "   kubectl apply -f generate-certs-job-improved.yaml"
echo ""
echo "🔍 SOLUTION 3 - Monitor job progress:"
echo "   kubectl get jobs -w"
echo "   kubectl logs -f job/generate-certificates-alpine"
echo ""
echo "⚠️  If still failing, check:"
echo "   - Network connectivity to package repositories"
echo "   - Available disk space on nodes"
echo "   - Resource constraints (CPU/Memory)"
echo "   - Firewall/proxy settings blocking outbound connections"
echo ""
echo "=== End Troubleshooting ==="
