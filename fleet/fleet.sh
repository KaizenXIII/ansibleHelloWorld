#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
SAVED_STATES_DIR="${SCRIPT_DIR}/saved-states"
INVENTORY_FILE="${SCRIPT_DIR}/../inventory/fleet_hosts.yml"
FLEET_CONTAINERS=(fleet-web-01 fleet-web-02 fleet-app-01 fleet-app-02 fleet-db-01 fleet-lb-01)

# Map containers to their group
get_group() {
  case "$1" in
    fleet-web-*)  echo "fleet_web" ;;
    fleet-app-*)  echo "fleet_app" ;;
    fleet-db-*)   echo "fleet_db" ;;
    fleet-lb-*)   echo "fleet_lb" ;;
    *)            echo "fleet" ;;
  esac
}

# Map containers to their host SSH port
get_ssh_port() {
  case "$1" in
    fleet-web-01) echo "2201" ;;
    fleet-web-02) echo "2202" ;;
    fleet-app-01) echo "2203" ;;
    fleet-app-02) echo "2204" ;;
    fleet-db-01)  echo "2205" ;;
    fleet-lb-01)  echo "2206" ;;
    *)            echo "" ;;
  esac
}

get_ip() {
  docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$1" 2>/dev/null
}

get_kind_ip() {
  docker inspect -f '{{(index .NetworkSettings.Networks "kind").IPAddress}}' "$1" 2>/dev/null
}

cmd_up() {
  echo "=== Building and starting fleet ==="
  docker compose -f "${COMPOSE_FILE}" up -d --build
  echo ""
  echo "Waiting for containers to be ready..."
  sleep 3
  cmd_status
  echo ""
  echo "Generating Ansible inventory..."
  cmd_inventory
  echo ""
  echo "Fleet is ready."
}

cmd_down() {
  echo "=== Stopping fleet ==="
  docker compose -f "${COMPOSE_FILE}" down
  echo "Fleet stopped."
}

cmd_destroy() {
  echo "=== Destroying fleet (containers, images, volumes) ==="
  docker compose -f "${COMPOSE_FILE}" down --rmi all --volumes --remove-orphans
  # Remove override file if it exists
  rm -f "${SCRIPT_DIR}/docker-compose.override.yml"
  echo "Fleet destroyed."
}

cmd_status() {
  echo "=== Fleet Status ==="
  printf "%-20s %-12s %-10s %-16s %-10s\n" "CONTAINER" "ROLE" "SSH" "INTERNAL IP" "STATUS"
  printf "%-20s %-12s %-10s %-16s %-10s\n" "---" "---" "---" "---" "---"
  for container in "${FLEET_CONTAINERS[@]}"; do
    local status kind_ip group ssh_port
    status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || echo "not found")
    kind_ip=$(get_kind_ip "$container" 2>/dev/null || echo "-")
    group=$(get_group "$container")
    ssh_port=$(get_ssh_port "$container")
    printf "%-20s %-12s %-10s %-16s %-10s\n" "$container" "$group" ":${ssh_port}" "${kind_ip:-"-"}" "$status"
  done
}

cmd_ssh() {
  local target="$1"
  if [ -z "$target" ]; then
    echo "Usage: fleet.sh ssh <container-name>"
    echo "Available: ${FLEET_CONTAINERS[*]}"
    exit 1
  fi
  local port
  port=$(get_ssh_port "$target")
  if [ -z "$port" ]; then
    echo "Error: Unknown container '$target'"
    echo "Available: ${FLEET_CONTAINERS[*]}"
    exit 1
  fi
  echo "Connecting to ${target} (127.0.0.1:${port})..."
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "$port" root@127.0.0.1
}

cmd_save() {
  local tag="${1:-$(date +%Y%m%d-%H%M%S)}"
  local tarball="${SAVED_STATES_DIR}/fleet-${tag}.tar.gz"

  echo "=== Saving fleet state: ${tag} ==="
  mkdir -p "${SAVED_STATES_DIR}"

  local snapshot_images=()
  for container in "${FLEET_CONTAINERS[@]}"; do
    local status
    status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || echo "")
    if [ "$status" != "running" ]; then
      echo "  SKIP: ${container} (not running)"
      continue
    fi
    local snapshot="fleet-snapshot/${container}:${tag}"
    echo "  Committing ${container} -> ${snapshot}"
    docker commit "$container" "$snapshot" > /dev/null
    snapshot_images+=("$snapshot")
  done

  if [ ${#snapshot_images[@]} -eq 0 ]; then
    echo "Error: No running fleet containers to save"
    exit 1
  fi

  echo "  Saving ${#snapshot_images[@]} images to ${tarball}..."
  docker save "${snapshot_images[@]}" | gzip > "$tarball"

  # Update latest symlink
  ln -sf "fleet-${tag}.tar.gz" "${SAVED_STATES_DIR}/latest.tar.gz"

  # Clean up committed images (they're in the tarball now)
  for img in "${snapshot_images[@]}"; do
    docker rmi "$img" > /dev/null 2>&1 || true
  done

  local size
  size=$(du -h "$tarball" | cut -f1)
  echo ""
  echo "Saved: ${tarball} (${size})"
}

cmd_restore() {
  local target="$1"
  if [ -z "$target" ]; then
    echo "Usage: fleet.sh restore <tag|latest>"
    echo ""
    cmd_list_saves
    exit 1
  fi

  local tarball
  if [ "$target" = "latest" ]; then
    tarball="${SAVED_STATES_DIR}/latest.tar.gz"
  elif [ -f "$target" ]; then
    tarball="$target"
  else
    tarball="${SAVED_STATES_DIR}/fleet-${target}.tar.gz"
  fi

  if [ ! -f "$tarball" ]; then
    echo "Error: Snapshot not found: ${tarball}"
    exit 1
  fi

  # Resolve symlinks for display
  local real_tarball
  real_tarball=$(readlink -f "$tarball" 2>/dev/null || realpath "$tarball")

  echo "=== Restoring fleet from: $(basename "$real_tarball") ==="

  # Stop existing fleet
  echo "  Stopping existing fleet..."
  docker compose -f "${COMPOSE_FILE}" down 2>/dev/null || true

  # Load snapshot images
  echo "  Loading snapshot images..."
  docker load < "$tarball"

  # Extract tag from tarball name
  local snap_tag
  snap_tag=$(basename "$real_tarball" .tar.gz | sed 's/^fleet-//')

  # Generate override file to use snapshot images
  echo "  Generating docker-compose.override.yml..."
  cat > "${SCRIPT_DIR}/docker-compose.override.yml" << YAML
services:
YAML

  for container in "${FLEET_CONTAINERS[@]}"; do
    local img="fleet-snapshot/${container}:${snap_tag}"
    if docker image inspect "$img" > /dev/null 2>&1; then
      cat >> "${SCRIPT_DIR}/docker-compose.override.yml" << YAML
  ${container}:
    image: ${img}
    build: !reset null
YAML
    fi
  done

  # Bring up from snapshots
  echo "  Starting fleet from snapshots..."
  docker compose -f "${COMPOSE_FILE}" -f "${SCRIPT_DIR}/docker-compose.override.yml" up -d

  sleep 3
  cmd_status
  echo ""
  echo "Generating Ansible inventory..."
  cmd_inventory
  echo ""
  echo "Fleet restored from: $(basename "$real_tarball")"
}

cmd_list_saves() {
  echo "=== Saved Fleet States ==="
  if [ ! -d "$SAVED_STATES_DIR" ] || [ -z "$(ls -A "$SAVED_STATES_DIR" 2>/dev/null | grep -v .gitkeep)" ]; then
    echo "  No saved states found."
    return
  fi
  printf "%-30s %-10s %-20s\n" "FILE" "SIZE" "DATE"
  printf "%-30s %-10s %-20s\n" "---" "---" "---"
  for f in "${SAVED_STATES_DIR}"/fleet-*.tar.gz; do
    [ -f "$f" ] || continue
    [ -L "$f" ] && continue  # skip symlinks
    local name size date
    name=$(basename "$f")
    size=$(du -h "$f" | cut -f1)
    date=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$f" 2>/dev/null || stat -c "%y" "$f" 2>/dev/null | cut -d. -f1)
    printf "%-30s %-10s %-20s\n" "$name" "$size" "$date"
  done
  echo ""
  local latest
  latest=$(readlink "${SAVED_STATES_DIR}/latest.tar.gz" 2>/dev/null || echo "none")
  echo "Latest: ${latest}"
}

cmd_inventory() {
  echo "  Writing inventory to ${INVENTORY_FILE}"

  local groups=(fleet_web fleet_app fleet_db fleet_lb)

  cat > "$INVENTORY_FILE" << 'HEADER'
# Auto-generated by fleet.sh — do not edit manually
all:
  children:
    fleet:
      vars:
        ansible_user: root
        ansible_connection: ssh
        ansible_ssh_common_args: "-o StrictHostKeyChecking=no"
        ansible_ssh_pass: awxtarget
      children:
HEADER

  for group in "${groups[@]}"; do
    echo "        ${group}:" >> "$INVENTORY_FILE"
    echo "          hosts:" >> "$INVENTORY_FILE"
    for container in "${FLEET_CONTAINERS[@]}"; do
      local cgroup
      cgroup=$(get_group "$container")
      if [ "$cgroup" = "$group" ]; then
        local port kind_ip
        port=$(get_ssh_port "$container")
        kind_ip=$(get_kind_ip "$container" 2>/dev/null || echo "")
        echo "            ${container}:" >> "$INVENTORY_FILE"
        echo "              ansible_host: 127.0.0.1" >> "$INVENTORY_FILE"
        echo "              ansible_port: ${port}" >> "$INVENTORY_FILE"
        if [ -n "$kind_ip" ]; then
          echo "              kind_ip: ${kind_ip}" >> "$INVENTORY_FILE"
        fi
      fi
    done
  done

  echo "  Inventory generated with $(grep 'ansible_host' "$INVENTORY_FILE" | wc -l | tr -d ' ') hosts"
}

cmd_ips() {
  echo "=== Fleet IPs ==="
  for container in "${FLEET_CONTAINERS[@]}"; do
    local ip
    ip=$(get_ip "$container" 2>/dev/null || echo "not running")
    echo "  ${container}: ${ip}"
  done
}

usage() {
  cat << EOF
Usage: fleet.sh <command> [args]

Fleet Management Commands:
  up                Build and start all fleet nodes
  down              Stop and remove fleet containers
  destroy           Stop, remove containers, images, and volumes
  status            Show fleet container status with IPs
  ssh <node>        SSH into a fleet node
  ips               Show container name -> IP mapping

State Management:
  save [tag]        Snapshot all containers (default tag: timestamp)
  restore <tag>     Restore fleet from a saved snapshot
  list-saves        List available saved states

Ansible Integration:
  inventory         Generate/refresh the Ansible inventory file
EOF
}

# Main dispatch
case "${1:-}" in
  up)          cmd_up ;;
  down)        cmd_down ;;
  destroy)     cmd_destroy ;;
  status)      cmd_status ;;
  ssh)         cmd_ssh "$2" ;;
  save)        cmd_save "$2" ;;
  restore)     cmd_restore "$2" ;;
  list-saves)  cmd_list_saves ;;
  inventory)   cmd_inventory ;;
  ips)         cmd_ips ;;
  *)           usage ;;
esac
