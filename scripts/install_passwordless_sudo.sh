#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIBEXEC_DIR="/usr/local/libexec/lazylead-vpn"
SUDOERS_FILE="/etc/sudoers.d/lazylead-vpn"
TMP_SUDOERS="$(mktemp)"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run with sudo." >&2
  exit 1
fi

mkdir -p "${LIBEXEC_DIR}"
install -o root -g wheel -m 0755 "${ROOT_DIR}/host_checkpoint_gateway_route.sh" "${LIBEXEC_DIR}/host_checkpoint_gateway_route.sh"
install -o root -g wheel -m 0755 "${ROOT_DIR}/host_corporate_routes.sh" "${LIBEXEC_DIR}/host_corporate_routes.sh"
install -o root -g wheel -m 0755 "${ROOT_DIR}/vm_corporate_router.sh" "${LIBEXEC_DIR}/vm_corporate_router.sh"

cat > "${TMP_SUDOERS}" <<'SUDOERS'
# Lazylead VPN allows members of the local admin group to run only the
# route/DNS commands required by the menu bar app without repeated prompts.
%admin ALL=(root) NOPASSWD: /usr/local/libexec/lazylead-vpn/host_checkpoint_gateway_route.sh install
%admin ALL=(root) NOPASSWD: /usr/local/libexec/lazylead-vpn/host_checkpoint_gateway_route.sh remove
%admin ALL=(root) NOPASSWD: /usr/local/libexec/lazylead-vpn/host_corporate_routes.sh install 192.168.64.2
%admin ALL=(root) NOPASSWD: /usr/local/libexec/lazylead-vpn/host_corporate_routes.sh remove 192.168.64.2
SUDOERS

chmod 0440 "${TMP_SUDOERS}"
visudo -cf "${TMP_SUDOERS}" >/dev/null
install -o root -g wheel -m 0440 "${TMP_SUDOERS}" "${SUDOERS_FILE}"
rm -f "${TMP_SUDOERS}"

echo "Installed ${LIBEXEC_DIR}"
echo "Installed ${SUDOERS_FILE}"
