# Ansible Hello World

A general-purpose Ansible starter template with example roles, playbooks, and a full CI/CD pipeline using AWX and GitHub Actions to manage Docker nodes via SSH.

## Prerequisites

- **Ansible**: [Install Ansible](https://docs.ansible.com/ansible/latest/installation_guide/)
- **Docker**: [Install Docker Desktop](https://docs.docker.com/get-docker/)
- **kubectl**: [Install kubectl](https://kubernetes.io/docs/tasks/tools/)
- **kind**: [Install kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- **kustomize**: [Install kustomize](https://kubectl.docs.kubernetes.io/installation/kustomize/)

### macOS Installation

```bash
brew install ansible kind kustomize kubectl
```

## Project Structure

```
ansibleHelloWorld/
├── ansible.cfg                          # Ansible configuration
├── inventory/
│   ├── hosts.yml                        # Localhost inventory
│   ├── k8s_hosts.yml                    # K8s node inventory (Docker connection)
│   ├── docker_hosts.yml                 # Docker node inventory (SSH connection)
│   └── group_vars/
│       └── all.yml                      # Shared variables
├── playbooks/
│   ├── site.yml                         # Hello World playbook
│   ├── k8s_info.yml                     # K8s node info gathering
│   ├── configure_node.yml               # Docker node configuration via SSH
│   └── test_hello_world.yml             # Test file deployment
├── roles/
│   └── hello_world/                     # Example role
├── awx-deploy/
│   ├── deploy.sh                        # AWX cluster deployment script
│   ├── configure-awx.sh                 # AWX API configuration script
│   ├── kind-config.yaml                 # Kind cluster config
│   ├── kustomization.yaml               # AWX Operator kustomization
│   ├── awx-instance.yaml                # AWX instance definition
│   └── Dockerfile.target-node           # SSH-enabled target node image
├── .github/workflows/
│   └── trigger-awx.yml                  # CI/CD: trigger AWX on push
├── requirements.yml                     # Galaxy dependencies
└── README.md
```

## Quick Start

```bash
# Run the Hello World playbook
ansible-playbook playbooks/site.yml

# Run with verbose output
ansible-playbook playbooks/site.yml -v

# Check mode (dry run)
ansible-playbook playbooks/site.yml --check

# Override variables
ansible-playbook playbooks/site.yml -e "hello_message='Hi there!'"
```

## AWX Setup

See [docs/awx-setup.md](docs/awx-setup.md) for full AWX deployment instructions.

```bash
# Deploy AWX on a local kind cluster
./awx-deploy/deploy.sh

# Configure AWX (project, inventory, credentials, job template)
./awx-deploy/configure-awx.sh
```

## CI/CD Pipeline

See [docs/cicd-pipeline.md](docs/cicd-pipeline.md) for pipeline details.

```
GitHub Push → GitHub Actions → AWX API → SSH → Docker Container
```

The pipeline triggers automatically when changes are pushed to `playbooks/`, `roles/`, or `inventory/` on the `main` branch.

## Playbooks

| Playbook | Description |
|---|---|
| `site.yml` | Hello World role demo (localhost) |
| `k8s_info.yml` | Gathers OS, memory, CPU, pod, and disk info from K8s nodes |
| `configure_node.yml` | Configures Docker nodes via SSH (MOTD, packages, users, timezone) |
| `test_hello_world.yml` | Deploys a test file to Docker node for pipeline validation |

## Common Commands

```bash
# List inventory hosts
ansible-inventory --list

# Ping all hosts
ansible all -m ping

# Syntax check
ansible-playbook playbooks/site.yml --syntax-check

# List tasks
ansible-playbook playbooks/site.yml --list-tasks

# Check AWX target node
docker exec awx-target-node cat /home/ops/TestHelloWorld

# SSH into target node
docker exec -it awx-target-node bash
```

## License

MIT
