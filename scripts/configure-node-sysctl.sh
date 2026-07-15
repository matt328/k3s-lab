#!/usr/bin/env bash
# Configure node-level kernel limits needed by k3s and observability agents.
set -euo pipefail

INOTIFY_MAX_USER_WATCHES="${INOTIFY_MAX_USER_WATCHES:-1048576}"
INOTIFY_MAX_USER_INSTANCES="${INOTIFY_MAX_USER_INSTANCES:-1024}"
INOTIFY_MAX_QUEUED_EVENTS="${INOTIFY_MAX_QUEUED_EVENTS:-32768}"

cat >/etc/sysctl.d/99-k3s-lab-inotify.conf <<EOF
# Managed by scripts/configure-node-sysctl.sh.
fs.inotify.max_user_watches = ${INOTIFY_MAX_USER_WATCHES}
fs.inotify.max_user_instances = ${INOTIFY_MAX_USER_INSTANCES}
fs.inotify.max_queued_events = ${INOTIFY_MAX_QUEUED_EVENTS}
EOF

sysctl --system >/dev/null

printf 'inotify limits: watches=%s instances=%s queued_events=%s\n' \
  "$(cat /proc/sys/fs/inotify/max_user_watches)" \
  "$(cat /proc/sys/fs/inotify/max_user_instances)" \
  "$(cat /proc/sys/fs/inotify/max_queued_events)"
