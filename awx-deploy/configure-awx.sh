#!/bin/bash
set -e

AWX_URL="http://127.0.0.1:30080"
AWX_USER="admin"
AWX_PASS="8W8I84tpYzcL9JKdRJBiqe1i87Xcf84N"
TARGET_IP="172.19.0.4"
GIT_REPO="https://github.com/KaizenXIII/ansibleHelloWorld.git"

awx_api() {
  local method=$1 endpoint=$2 data=$3
  curl -s -X "$method" \
    -u "${AWX_USER}:${AWX_PASS}" \
    -H "Content-Type: application/json" \
    ${data:+-d "$data"} \
    "${AWX_URL}/api/v2${endpoint}"
}

echo "=== Configuring AWX ==="

# 1. Create Project (SCM-based from GitHub)
echo "Creating project..."
PROJECT=$(awx_api POST /projects/ '{
  "name": "Ansible Hello World",
  "description": "CI/CD managed Ansible project",
  "organization": 1,
  "scm_type": "git",
  "scm_url": "'"${GIT_REPO}"'",
  "scm_branch": "main",
  "scm_update_on_launch": true
}')
PROJECT_ID=$(echo "$PROJECT" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
echo "  Project ID: ${PROJECT_ID}"

# 2. Create Machine Credential (SSH password for target node)
echo "Creating SSH credential..."
CRED=$(awx_api POST /credentials/ '{
  "name": "Docker Node SSH",
  "description": "SSH credential for Docker target nodes",
  "organization": 1,
  "credential_type": 1,
  "inputs": {
    "username": "root",
    "password": "awxtarget"
  }
}')
CRED_ID=$(echo "$CRED" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
echo "  Credential ID: ${CRED_ID}"

# 3. Create Inventory
echo "Creating inventory..."
INV=$(awx_api POST /inventories/ '{
  "name": "Docker Nodes",
  "description": "Docker container targets",
  "organization": 1
}')
INV_ID=$(echo "$INV" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
echo "  Inventory ID: ${INV_ID}"

# 4. Create Host in Inventory
echo "Adding host to inventory..."
HOST=$(awx_api POST "/inventories/${INV_ID}/hosts/" '{
  "name": "awx-target-node",
  "description": "Docker target node with SSH",
  "variables": "ansible_host: '"${TARGET_IP}"'\nansible_user: root\nansible_connection: ssh\nansible_ssh_common_args: \"-o StrictHostKeyChecking=no\""
}')
HOST_ID=$(echo "$HOST" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
echo "  Host ID: ${HOST_ID}"

# 5. Create Group and add host
echo "Creating host group..."
GROUP=$(awx_api POST "/inventories/${INV_ID}/groups/" '{
  "name": "docker_nodes",
  "description": "Docker container nodes"
}')
GROUP_ID=$(echo "$GROUP" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
awx_api POST "/groups/${GROUP_ID}/hosts/" '{"id": '"${HOST_ID}"'}' > /dev/null
echo "  Group ID: ${GROUP_ID}"

# 6. Wait for project sync
echo "Waiting for project sync..."
for i in $(seq 1 30); do
  STATUS=$(awx_api GET "/projects/${PROJECT_ID}/" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','unknown'))")
  if [ "$STATUS" = "successful" ]; then
    echo "  Project sync complete"
    break
  elif [ "$STATUS" = "failed" ] || [ "$STATUS" = "error" ]; then
    echo "  WARNING: Project sync failed (status: ${STATUS}), continuing anyway..."
    break
  fi
  sleep 5
done

# 7. Create Job Template
echo "Creating job template..."
JT=$(awx_api POST /job_templates/ '{
  "name": "Configure Docker Node",
  "description": "Configures Docker target nodes via SSH",
  "organization": 1,
  "project": '"${PROJECT_ID}"',
  "playbook": "playbooks/configure_node.yml",
  "inventory": '"${INV_ID}"',
  "ask_variables_on_launch": true
}')
JT_ID=$(echo "$JT" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
echo "  Job Template ID: ${JT_ID}"

# 8. Associate credential with job template
echo "Associating credential..."
awx_api POST "/job_templates/${JT_ID}/credentials/" '{"id": '"${CRED_ID}"'}' > /dev/null
echo "  Credential associated"

echo ""
echo "=== AWX Configuration Complete ==="
echo "  Project:      ${PROJECT_ID} - Ansible Hello World"
echo "  Credential:   ${CRED_ID} - Docker Node SSH"
echo "  Inventory:    ${INV_ID} - Docker Nodes"
echo "  Job Template: ${JT_ID} - Configure Docker Node"
echo ""
echo "You can now launch the job template from the AWX UI or API:"
echo "  curl -s -u admin:${AWX_PASS} -X POST ${AWX_URL}/api/v2/job_templates/${JT_ID}/launch/ -H 'Content-Type: application/json'"
