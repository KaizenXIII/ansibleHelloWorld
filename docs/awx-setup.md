# AWX Setup Guide

## Overview

AWX is deployed on a local Kubernetes cluster using [kind](https://kind.sigs.k8s.io/) and the [AWX Operator](https://github.com/ansible/awx-operator).

## Architecture

```
kind cluster (awx-cluster)
├── awx namespace
│   ├── awx-operator-controller-manager   # AWX Operator
│   ├── awx-web                           # AWX Web UI
│   ├── awx-task                          # AWX Task Runner
│   └── awx-postgres-15                   # PostgreSQL database
└── Docker network (kind)
    └── awx-target-node                   # SSH-enabled target container
```

## Deployment

### 1. Deploy the Kind Cluster and AWX

```bash
./awx-deploy/deploy.sh
```

This script:
- Creates a kind cluster named `awx-cluster` with port 30080 mapped
- Creates the `awx` namespace
- Deploys AWX Operator v2.19.1 via kustomize
- Deploys the AWX instance with NodePort service on port 30080

### 2. Build and Run the Target Node

```bash
docker build -t awx-target-node -f awx-deploy/Dockerfile.target-node awx-deploy/
docker run -d --name awx-target-node --network kind --restart unless-stopped awx-target-node
```

The target node is an Ubuntu 22.04 container with:
- SSH server (port 22)
- Python 3 (required for Ansible)
- Root login enabled (password: `awxtarget`)

### 3. Configure AWX Resources

```bash
./awx-deploy/configure-awx.sh
```

This creates via the AWX API:
- **Project**: "Ansible Hello World" — synced from GitHub
- **Credential**: "Docker Node SSH" — root/awxtarget
- **Inventory**: "Docker Nodes" — with `awx-target-node` host
- **Job Template**: "Configure Docker Node" — runs `configure_node.yml`

## Access

- **URL**: http://localhost:30080
- **Username**: `admin`
- **Password**: Retrieve with:
  ```bash
  kubectl -n awx get secret awx-admin-password -o jsonpath='{.data.password}' | base64 -d; echo
  ```

## AWX API Examples

```bash
# Get admin password
AWX_PASS=$(kubectl -n awx get secret awx-admin-password -o jsonpath='{.data.password}' | base64 -d)

# List job templates
curl -s -u "admin:${AWX_PASS}" http://127.0.0.1:30080/api/v2/job_templates/ | python3 -m json.tool

# Launch a job template (by ID)
curl -s -u "admin:${AWX_PASS}" -X POST http://127.0.0.1:30080/api/v2/job_templates/9/launch/

# Check job status
curl -s -u "admin:${AWX_PASS}" http://127.0.0.1:30080/api/v2/jobs/<JOB_ID>/

# Get job output
curl -s -u "admin:${AWX_PASS}" "http://127.0.0.1:30080/api/v2/jobs/<JOB_ID>/stdout/?format=txt"

# Create an API token
curl -s -u "admin:${AWX_PASS}" -X POST -H "Content-Type: application/json" \
  -d '{"description": "CI/CD", "scope": "write"}' \
  http://127.0.0.1:30080/api/v2/users/1/personal_tokens/
```

## Monitoring

```bash
# Check all AWX pods
kubectl -n awx get pods

# View AWX task logs
kubectl -n awx logs -f deployment/awx-task -c awx-task

# View AWX web logs
kubectl -n awx logs -f deployment/awx-web -c awx-web
```

## Teardown

```bash
# Delete the kind cluster (removes everything)
kind delete cluster --name awx-cluster

# Remove the target node
docker rm -f awx-target-node
```
