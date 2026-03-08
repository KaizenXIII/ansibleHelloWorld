# CI/CD Pipeline

## Overview

The CI/CD pipeline uses GitHub Actions to trigger AWX job templates when Ansible code changes are pushed to the `main` branch.

```
GitHub Push → GitHub Actions → AWX API → SSH → Docker Container
```

## Pipeline Flow

1. Developer pushes changes to `playbooks/`, `roles/`, or `inventory/`
2. GitHub Actions workflow (`.github/workflows/trigger-awx.yml`) triggers
3. Workflow calls the AWX API to launch a job template
4. AWX syncs the project from GitHub (picks up latest code)
5. AWX runs the playbook over SSH against the Docker target node
6. Workflow polls for job completion and reports status

## GitHub Actions Workflow

The workflow is defined in `.github/workflows/trigger-awx.yml`.

### Triggers

- **Push** to `main` branch when files change in `playbooks/`, `roles/`, or `inventory/`
- **Manual** via `workflow_dispatch` from the GitHub Actions tab

### Required Secrets

Configure these in your GitHub repo under **Settings > Secrets and variables > Actions**:

| Secret | Description | Example |
|---|---|---|
| `AWX_URL` | AWX instance URL | `http://127.0.0.1:30080` |
| `AWX_TOKEN` | AWX API bearer token | (generated via AWX API) |
| `AWX_JOB_TEMPLATE_ID` | Job template ID to launch | `9` |

### Runner

The workflow uses `self-hosted` runner since AWX runs locally. To set up a self-hosted runner:

1. Go to your GitHub repo **Settings > Actions > Runners**
2. Click **New self-hosted runner**
3. Follow the setup instructions for macOS

Alternatively, for a remote AWX instance, change `runs-on` to `ubuntu-latest`.

## Generating an AWX API Token

```bash
AWX_PASS=$(kubectl -n awx get secret awx-admin-password -o jsonpath='{.data.password}' | base64 -d)

curl -s -u "admin:${AWX_PASS}" -X POST \
  -H "Content-Type: application/json" \
  -d '{"description": "GitHub Actions CI/CD", "scope": "write"}' \
  http://127.0.0.1:30080/api/v2/users/1/personal_tokens/
```

## Manual Trigger via API

You can trigger the pipeline directly without GitHub Actions:

```bash
# Launch job template
curl -s -X POST \
  -H "Authorization: Bearer <AWX_TOKEN>" \
  -H "Content-Type: application/json" \
  http://127.0.0.1:30080/api/v2/job_templates/9/launch/

# Launch with extra variables
curl -s -X POST \
  -H "Authorization: Bearer <AWX_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"extra_vars": {"hello_message": "Custom message"}}' \
  http://127.0.0.1:30080/api/v2/job_templates/9/launch/
```

## Job Templates

| ID | Name | Playbook | Description |
|---|---|---|---|
| 9 | Configure Docker Node | `configure_node.yml` | Full node setup (MOTD, packages, users) |
| 10 | Test Hello World File | `test_hello_world.yml` | Deploys test file for validation |

## Verifying Pipeline Results

```bash
# Check the file deployed by the test playbook
docker exec awx-target-node cat /home/ops/TestHelloWorld

# Check MOTD set by the configure playbook
docker exec awx-target-node cat /etc/motd

# SSH into the target to inspect
docker exec -it awx-target-node bash
```
