# Ansible Hello World

A general-purpose Ansible starter template with an example role, inventory, and playbook.

## Prerequisites

- **Ansible**: [Install Ansible](https://docs.ansible.com/ansible/latest/installation_guide/)

### macOS Installation

```bash
brew install ansible
```

## Project Structure

```
ansibleHelloWorld/
├── ansible.cfg              # Ansible configuration
├── inventory/
│   ├── hosts.yml            # Inventory (localhost)
│   └── group_vars/
│       └── all.yml          # Shared variables
├── playbooks/
│   └── site.yml             # Main playbook
├── roles/
│   └── hello_world/
│       ├── tasks/main.yml   # Role tasks
│       ├── handlers/main.yml
│       ├── templates/hello.conf.j2
│       ├── vars/main.yml
│       └── defaults/main.yml
├── requirements.yml         # Galaxy dependencies
└── README.md
```

## Quick Start

```bash
# Run the playbook
ansible-playbook playbooks/site.yml

# Run with verbose output
ansible-playbook playbooks/site.yml -v

# Check mode (dry run)
ansible-playbook playbooks/site.yml --check

# Override variables
ansible-playbook playbooks/site.yml -e "hello_message='Hi there!'"
```

## Common Commands

```bash
# List inventory hosts
ansible-inventory --list

# Ping all hosts
ansible all -m ping

# Run ad-hoc command
ansible localhost -m command -a "uptime"

# Syntax check
ansible-playbook playbooks/site.yml --syntax-check

# List tasks
ansible-playbook playbooks/site.yml --list-tasks
```

## Customization

- Edit `inventory/group_vars/all.yml` to change global variables
- Edit `roles/hello_world/defaults/main.yml` to change role defaults
- Add new roles under `roles/`
- Add new playbooks under `playbooks/`
- Add Galaxy dependencies to `requirements.yml`

## License

MIT
