#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLUSTER_NAME="awx-cluster"

echo "=== AWX Deployment Script ==="

# Step 1: Create kind cluster
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "Kind cluster '${CLUSTER_NAME}' already exists, skipping creation."
else
  echo "Creating kind cluster '${CLUSTER_NAME}'..."
  kind create cluster --name "${CLUSTER_NAME}" --config "${SCRIPT_DIR}/kind-config.yaml"
fi

# Step 2: Create AWX namespace
echo "Creating awx namespace..."
kubectl create namespace awx --dry-run=client -o yaml | kubectl apply -f -

# Step 3: Deploy AWX Operator and AWX instance
echo "Deploying AWX Operator (this downloads from GitHub, may take a moment)..."
cd "${SCRIPT_DIR}"
kustomize build . | kubectl apply -f -

echo ""
echo "=== Deployment initiated ==="
echo "AWX is now being deployed. This takes 5-10 minutes for all pods to be ready."
echo ""
echo "Monitor progress with:"
echo "  kubectl -n awx get pods -w"
echo ""
echo "Once the 'awx-web' and 'awx-task' pods are Running, get the admin password:"
echo "  kubectl -n awx get secret awx-admin-password -o jsonpath='{.data.password}' | base64 -d; echo"
echo ""
echo "Access AWX at: http://localhost:30080"
echo "Username: admin"
