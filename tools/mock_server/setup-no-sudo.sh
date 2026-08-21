#!/bin/bash
# One-time privileged setup so the mock rig never needs sudo again.
#
# The cameras answer on port 80 (tools/mock_server/README.md explains why),
# which the kernel normally reserves for root. This script lifts that
# reservation for low loopback ports -- once, with sudo, right now -- so
# every later `run.py` / `dev.sh --cameras` runs unprivileged.
#
# Safe in general: it does not open anything to the network. It only tells
# the kernel that ports in this range no longer require root to *bind*;
# nothing remote can reach 127.0.0.0/8 regardless.
#
#   ./tools/mock_server/setup-no-sudo.sh           apply now + try to persist
#   ./tools/mock_server/setup-no-sudo.sh --revert  restore the OS default

set -euo pipefail

REVERT=0
[[ "${1:-}" == "--revert" ]] && REVERT=1

case "$(uname -s)" in
  Linux)
    KEY="net.ipv4.ip_unprivileged_port_start"
    VALUE=$([[ $REVERT == 1 ]] && echo 1024 || echo 80)
    echo "Linux: setting $KEY=$VALUE (sudo needed for this one command)"
    sudo sysctl -w "$KEY=$VALUE"

    PERSIST_FILE=/etc/sysctl.d/99-mock-rig-unprivileged-ports.conf
    if [[ $REVERT == 1 ]]; then
      sudo rm -f "$PERSIST_FILE"
      echo "Removed $PERSIST_FILE"
    else
      echo "$KEY = $VALUE" | sudo tee "$PERSIST_FILE" >/dev/null
      echo "Persisted to $PERSIST_FILE (survives reboot)"
    fi
    ;;

  Darwin)
    KEY="net.inet.ip.portrange.reservedhigh"
    VALUE=$([[ $REVERT == 1 ]] && echo 1023 || echo 79)
    echo "macOS: setting $KEY=$VALUE (sudo needed for this one command)"
    sudo sysctl -w "$KEY=$VALUE"
    echo "Note: this does not survive reboot on macOS without a LaunchDaemon;" \
         "re-run this script after a restart if binding port 80 needs sudo again."

    if [[ $REVERT == 0 ]]; then
      echo
      echo "Also pre-creating the camera loopback aliases, so those are"
      echo "adopted (not re-created) by future non-sudo runs:"
      for ip in 127.0.0.2 127.0.0.3 127.0.0.4; do
        sudo ifconfig lo0 alias "$ip" 255.255.255.255
        echo "  added $ip"
      done
      echo "These also do not survive reboot; re-run this script if needed."
    fi
    ;;

  *)
    echo "No unprivileged-port mechanism known for $(uname -s)." >&2
    echo "You'll need sudo for cameras on this OS -- see tools/mock_server/README.md." >&2
    exit 1
    ;;
esac

echo
echo "Done. tools/mock_server/run.py (and dev.sh --cameras) no longer need sudo."
