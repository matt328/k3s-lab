#!/usr/bin/env bash
# Prepare a Fedora remote libvirt host for this lab.
#
# Run from the remote host itself. Creating or moving a wired NIC into br0 will
# briefly drop networking, so prefer a local console.
set -euo pipefail

BRIDGE=""
IFACE=""
TARGET_USER="${SUDO_USER:-${USER:-}}"
DNS_SERVERS=""
DNS_SEARCH=""
ENV_PREFIX="${REMOTE_LIBVIRT_ENV_PREFIX:-REMOTE}"
IGNORE_AUTO_DNS=false
INSTALL_VAGRANT=false
SKIP_BRIDGE=false
YES=false
ALLOW_SSH=false

usage() {
  cat <<'EOF'
Usage:
  scripts/setup-remote-libvirt-host.sh --iface IFACE [options]

Options:
  --iface IFACE          Wired NIC to enslave to the bridge, e.g. enp0s31f6.
                         If omitted, the script auto-detects exactly one
                         connected ethernet device.
  --bridge NAME          Bridge interface/connection name. Default: br0, or
                         <ENV_PREFIX>_LAB_BRIDGE if set.
  --user USER            User Vagrant will SSH as on this remote host. Default:
                         the sudo-invoking user.
  --env-prefix PREFIX    Prefix for the .env.local output snippet. Default:
                         REMOTE. Use CITADEL when preparing the citadel host.
  --dns "SERVERS"        Optional space-separated DNS servers for the bridge.
  --dns-search DOMAIN    Optional DNS search domain for the bridge.
  --ignore-auto-dns      Ignore DHCP-provided DNS on the bridge.
  --install-vagrant      Also install vagrant and vagrant-libvirt on this host.
                         Not required when this host is only a remote hypervisor.
  --skip-bridge          Install/configure libvirt only; do not touch networking.
  --allow-ssh            Permit bridge changes while connected over SSH. Risky.
  -y, --yes              Do not prompt before changing network configuration.
  -h, --help             Show this help.

Examples:
  scripts/setup-remote-libvirt-host.sh --iface enp0s31f6 --bridge br0
  scripts/setup-remote-libvirt-host.sh --iface enp0s31f6 --bridge br0 \
    --env-prefix CITADEL
  scripts/setup-remote-libvirt-host.sh --iface enp0s31f6 --dns "192.168.50.210" \
    --dns-search lab.home --ignore-auto-dns
EOF
}

log() {
  printf '==> %s\n' "$*"
}

warn() {
  printf 'WARNING: %s\n' "$*" >&2
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

as_target_user() {
  sudo -u "$TARGET_USER" "$@"
}

unit_exists() {
  systemctl list-unit-files --type=service --no-legend "$1" 2>/dev/null \
    | grep -Fq "$1"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --iface)
      IFACE="${2:-}"
      [ -n "$IFACE" ] || die "--iface requires a value"
      shift 2
      ;;
    --bridge)
      BRIDGE="${2:-}"
      [ -n "$BRIDGE" ] || die "--bridge requires a value"
      shift 2
      ;;
    --user)
      TARGET_USER="${2:-}"
      [ -n "$TARGET_USER" ] || die "--user requires a value"
      shift 2
      ;;
    --env-prefix)
      ENV_PREFIX="${2:-}"
      [ -n "$ENV_PREFIX" ] || die "--env-prefix requires a value"
      shift 2
      ;;
    --dns)
      DNS_SERVERS="${2:-}"
      [ -n "$DNS_SERVERS" ] || die "--dns requires a value"
      shift 2
      ;;
    --dns-search)
      DNS_SEARCH="${2:-}"
      [ -n "$DNS_SEARCH" ] || die "--dns-search requires a value"
      shift 2
      ;;
    --ignore-auto-dns)
      IGNORE_AUTO_DNS=true
      shift
      ;;
    --install-vagrant)
      INSTALL_VAGRANT=true
      shift
      ;;
    --skip-bridge)
      SKIP_BRIDGE=true
      shift
      ;;
    --allow-ssh)
      ALLOW_SSH=true
      shift
      ;;
    -y|--yes)
      YES=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

[ -n "$TARGET_USER" ] || die "could not determine target user; pass --user"
[[ "$ENV_PREFIX" =~ ^[A-Z][A-Z0-9_]*$ ]] || die "--env-prefix must be uppercase letters, numbers, or underscores"

if [ -z "$BRIDGE" ]; then
  BRIDGE="$(printenv "${ENV_PREFIX}_LAB_BRIDGE" 2>/dev/null || true)"
  BRIDGE="${BRIDGE:-br0}"
fi

detect_iface() {
  local candidates=()
  mapfile -t candidates < <(
    nmcli -t -f DEVICE,TYPE,STATE device \
      | awk -F: '$2 == "ethernet" && $3 == "connected" { print $1 }'
  )

  case "${#candidates[@]}" in
    0)
      die "no connected ethernet device found; pass --iface"
      ;;
    1)
      IFACE="${candidates[0]}"
      ;;
    *)
      printf 'Connected ethernet devices:\n' >&2
      printf '  %s\n' "${candidates[@]}" >&2
      die "multiple connected ethernet devices found; pass --iface"
      ;;
  esac
}

install_packages() {
  local packages=(
    @virtualization
    libvirt-client
    libvirt-daemon-config-network
    openssh-server
    qemu-img
    virt-install
  )

  if [ "$INSTALL_VAGRANT" = true ]; then
    packages+=(vagrant vagrant-libvirt)
  fi

  log "Installing Fedora virtualization packages"
  as_root dnf install -y "${packages[@]}"
}

enable_services() {
  log "Enabling SSH and libvirt services"
  as_root systemctl enable --now sshd.service

  if unit_exists libvirtd.service; then
    as_root systemctl enable --now libvirtd.service
  else
    for service in virtqemud.service virtstoraged.service virtnetworkd.service; do
      if unit_exists "$service"; then
        as_root systemctl enable --now "$service"
      fi
    done
  fi
}

configure_user_access() {
  getent passwd "$TARGET_USER" >/dev/null || die "user does not exist: $TARGET_USER"
  getent group libvirt >/dev/null || die "libvirt group does not exist after package install"

  if id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx libvirt; then
    log "User $TARGET_USER is already in the libvirt group"
  else
    log "Adding $TARGET_USER to the libvirt group"
    as_root usermod -aG libvirt "$TARGET_USER"
    warn "$TARGET_USER must log out and back in before the new libvirt group membership is active."
  fi
}

libvirt_pool_running() {
  local state
  state="$(
    as_root virsh -c qemu:///system pool-info default 2>/dev/null \
      | awk -F: '$1 == "State" { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2 }'
  )"
  [ "$state" = "running" ]
}

libvirt_network_active() {
  local active
  active="$(
    as_root virsh -c qemu:///system net-info default 2>/dev/null \
      | awk -F: '$1 == "Active" { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2 }'
  )"
  [ "$active" = "yes" ]
}

ensure_default_storage_pool() {
  log "Ensuring the default libvirt storage pool exists and autostarts"
  as_root mkdir -p /var/lib/libvirt/images

  if ! as_root virsh -c qemu:///system pool-info default >/dev/null 2>&1; then
    as_root virsh -c qemu:///system pool-define-as default dir --target /var/lib/libvirt/images
  fi

  as_root virsh -c qemu:///system pool-autostart default >/dev/null
  if ! libvirt_pool_running; then
    as_root virsh -c qemu:///system pool-start default >/dev/null
  fi
}

ensure_default_network() {
  if as_root virsh -c qemu:///system net-info default >/dev/null 2>&1; then
    log "Ensuring the default libvirt network autostarts"
    as_root virsh -c qemu:///system net-autostart default >/dev/null
    if ! libvirt_network_active; then
      as_root virsh -c qemu:///system net-start default >/dev/null
    fi
  elif [ -f /usr/share/libvirt/networks/default.xml ]; then
    log "Defining and starting the default libvirt network"
    as_root virsh -c qemu:///system net-define /usr/share/libvirt/networks/default.xml >/dev/null
    as_root virsh -c qemu:///system net-autostart default >/dev/null
    as_root virsh -c qemu:///system net-start default >/dev/null
  else
    warn "No default libvirt network definition found; Vagrant may create its own management network."
  fi
}

confirm_bridge_change() {
  if [ -n "${SSH_CONNECTION:-}" ] && [ "$ALLOW_SSH" != true ]; then
    die "refusing to change bridge networking over SSH; use a local console or pass --allow-ssh"
  fi

  if [ "$YES" = true ]; then
    return
  fi

  cat <<EOF
This will configure bridge '$BRIDGE' and enslave wired NIC '$IFACE'.
The network connection on '$IFACE' may briefly drop.

Type 'yes' to continue:
EOF
  local answer
  read -r answer
  [ "$answer" = "yes" ] || die "aborted"
}

nm_connection_exists() {
  nmcli connection show "$1" >/dev/null 2>&1
}

configure_bridge() {
  [ -n "$IFACE" ] || detect_iface
  nmcli device status | awk '{ print $1 }' | grep -qx "$IFACE" \
    || die "network device does not exist: $IFACE"

  confirm_bridge_change

  log "Configuring NetworkManager bridge $BRIDGE on $IFACE"
  if nm_connection_exists "$BRIDGE"; then
    local bridge_type
    bridge_type="$(nmcli -g connection.type connection show "$BRIDGE")"
    [ "$bridge_type" = "bridge" ] || die "connection '$BRIDGE' exists but is type '$bridge_type', not bridge"
    as_root nmcli connection modify "$BRIDGE" \
      connection.interface-name "$BRIDGE" \
      connection.autoconnect yes \
      bridge.stp no \
      ipv4.method auto \
      ipv6.method auto
  else
    as_root nmcli connection add type bridge ifname "$BRIDGE" con-name "$BRIDGE" \
      bridge.stp no ipv4.method auto ipv6.method auto
  fi

  if [ -n "$DNS_SERVERS" ]; then
    as_root nmcli connection modify "$BRIDGE" ipv4.dns "$DNS_SERVERS"
  fi
  if [ -n "$DNS_SEARCH" ]; then
    as_root nmcli connection modify "$BRIDGE" ipv4.dns-search "$DNS_SEARCH"
  fi
  if [ "$IGNORE_AUTO_DNS" = true ]; then
    as_root nmcli connection modify "$BRIDGE" ipv4.ignore-auto-dns yes
  fi

  local slave_connection="${BRIDGE}-slave-${IFACE}"
  if nm_connection_exists "$slave_connection"; then
    as_root nmcli connection modify "$slave_connection" \
      connection.interface-name "$IFACE" \
      connection.autoconnect yes \
      connection.controller "$BRIDGE" \
      connection.port-type bridge
  else
    as_root nmcli connection add type ethernet ifname "$IFACE" con-name "$slave_connection"
    as_root nmcli connection modify "$slave_connection" \
      connection.controller "$BRIDGE" \
      connection.port-type bridge \
      connection.autoconnect yes
  fi

  local active_connection
  active_connection="$(nmcli -g GENERAL.CONNECTION device show "$IFACE" | head -n1 || true)"
  if [ -n "$active_connection" ] \
    && [ "$active_connection" != "--" ] \
    && [ "$active_connection" != "$slave_connection" ]; then
    log "Disabling autoconnect on existing NIC connection: $active_connection"
    as_root nmcli connection modify "$active_connection" connection.autoconnect no
    if ! as_root nmcli connection down "$active_connection" >/dev/null; then
      warn "Could not bring down '$active_connection'; continuing with bridge activation."
    fi
  fi

  as_root nmcli connection up "$slave_connection" >/dev/null
  as_root nmcli connection up "$BRIDGE" >/dev/null
}

verify_setup() {
  log "Verifying remote libvirt host setup"

  printf '\nActive NetworkManager connections:\n'
  nmcli -t -f NAME,DEVICE,TYPE connection show --active | grep -E "(^${BRIDGE}:|bridge|ethernet)" || true

  if [ "$SKIP_BRIDGE" != true ]; then
    printf '\nBridge address:\n'
    ip -br addr show "$BRIDGE" || true

    printf '\nBridge members:\n'
    bridge link | grep -E "master ${BRIDGE}|${BRIDGE}" || true
  fi

  printf '\nLibvirt default storage pool:\n'
  as_root virsh -c qemu:///system pool-info default

  printf '\nLibvirt URI access check:\n'
  as_root virsh -c qemu:///system uri

  printf '\nLibvirt URI access as %s:\n' "$TARGET_USER"
  as_target_user virsh -c qemu:///system uri
}

if ! grep -Eq '(vmx|svm)' /proc/cpuinfo; then
  warn "CPU virtualization flags were not detected; check BIOS/UEFI virtualization settings."
fi

install_packages
enable_services
configure_user_access
ensure_default_storage_pool
ensure_default_network

if [ "$SKIP_BRIDGE" = true ]; then
  log "Skipping bridge configuration"
else
  configure_bridge
fi

verify_setup

cat <<EOF

Remote libvirt host setup complete.

Use these values in .env.local on the control machine:
  ${ENV_PREFIX}_LIBVIRT_URI=qemu+ssh://${TARGET_USER}@<remote-host>/system
  ${ENV_PREFIX}_LIBVIRT_SSH_PROXY_COMMAND="ssh -W %h:%p ${TARGET_USER}@<remote-host>"
  ${ENV_PREFIX}_LAB_BRIDGE=${BRIDGE}
EOF
