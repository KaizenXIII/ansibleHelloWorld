# Ansible Hello World

A hands-on Ansible project that demonstrates core automation patterns — role-based task execution, Jinja2 templating, multi-inventory targeting, and a full AWX (Ansible Tower) deployment pipeline with GitHub Actions CI/CD integration.

## Features

- `hello_world` Ansible role that prints a greeting, gathers system facts, and generates a config file from a Jinja2 template
- Multiple inventory targets: localhost, a Docker SSH node, and a Kind Kubernetes node
- Full AWX deployment stack on a local Kind cluster using the AWX Operator (v2.19.1)
- GitHub Actions workflow that triggers an AWX job template on every push to `main` that touches playbooks, roles, or inventory
- Docker target-node image (Ubuntu 22.04 + SSH) for use as a managed node in AWX

## Prerequisites

| Tool | Purpose |
|------|---------|
| `ansible` >= 2.14 | Run playbooks directly |
| `docker` | Build the target-node image and run containers |
| `kind` | Create the local Kubernetes cluster for AWX |
| `kubectl` | Manage the Kind cluster |
| `kustomize` | Render the AWX Operator manifests |

### macOS (Homebrew)

```bash
brew install ansible kind kustomize kubectl
```

## Quick Start

```bash
# Clone the repository
git clone https://github.com/KaizenXIII/ansibleHelloWorld.git
cd ansibleHelloWorld

# Run the Hello World playbook locally
ansible-playbook playbooks/site.yml

# Override the greeting message
ansible-playbook playbooks/site.yml -e "hello_message='Hello from my machine!'"
```

## Usage

### Run against a Kind Kubernetes node

```bash
ansible-playbook playbooks/k8s_info.yml -i inventory/k8s_hosts.yml
```

### Configure a Docker target node

```bash
ansible-playbook playbooks/configure_node.yml -i inventory/docker_hosts.yml
```

## AWX Deployment

```bash
cd awx-deploy

# Deploy AWX on a local Kind cluster
./deploy.sh

# Wait for pods to be ready (~5-10 minutes)
kubectl -n awx get pods -w

# Get the admin password
kubectl -n awx get secret awx-admin-password -o jsonpath='{.data.password}' | base64 -d; echo

# Configure AWX objects via API
./configure-awx.sh
```

Access the UI at **http://localhost:30080** (username: `admin`).

## CI/CD — GitHub Actions

The workflow at `.github/workflows/trigger-awx.yml` fires on pushes to `main` that modify `playbooks/`, `roles/`, or `inventory/`.

Required repository secrets:

| Secret | Description |
|--------|-------------|
| `AWX_URL` | Base URL of the AWX instance |
| `AWX_TOKEN` | AWX personal access token |
| `AWX_JOB_TEMPLATE_ID` | Numeric ID of the job template to launch |

## Project Structure

```
ansibleHelloWorld/
├── ansible.cfg                        # Default inventory, roles path, connection settings
├── requirements.yml                   # Galaxy roles/collections
├── inventory/
│   ├── hosts.yml                      # Default: localhost in "dev" group
│   ├── docker_hosts.yml               # Docker SSH node
│   ├── k8s_hosts.yml                  # Kind K8s node
│   └── group_vars/
│       ├── all.yml                    # Global vars
│       └── k8s_nodes/main.yml         # K8s node vars
├── playbooks/
│   ├── site.yml                       # Main playbook: runs hello_world role
│   ├── k8s_info.yml                   # Gathers facts from Kind node
│   └── configure_node.yml            # Configures Docker target node
├── roles/
│   └── hello_world/
│       ├── defaults/main.yml
│       ├── vars/main.yml
│       ├── tasks/main.yml
│       ├── handlers/main.yml
│       └── templates/hello.conf.j2
├── awx-deploy/
│   ├── deploy.sh
│   ├── configure-awx.sh
│   ├── kind-config.yaml
│   ├── kustomization.yaml
│   ├── awx-instance.yaml
│   └── Dockerfile.target-node
└── .github/workflows/
    └── trigger-awx.yml
```

## Playbooks

| Playbook | Description |
|---|---|
| `site.yml` | Hello World role demo (localhost) |
| `k8s_info.yml` | Gathers OS, memory, CPU, pod, and disk info from K8s nodes |
| `configure_node.yml` | Configures Docker nodes via SSH (MOTD, packages, users, timezone) |

## License

No license file is present in this repository.
