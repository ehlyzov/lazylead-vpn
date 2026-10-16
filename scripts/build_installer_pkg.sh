#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export VERSION="${VERSION:-$(cat "${ROOT_DIR}/VERSION")}"
APP_NAME="Lazylead VPN.app"
APP_DIR="${ROOT_DIR}/build/${APP_NAME}"
PKG_ROOT="${ROOT_DIR}/build/pkgroot"
PKG_WORK="${ROOT_DIR}/build/pkgwork"
PKG_SCRIPTS="${ROOT_DIR}/build/pkgscripts"
DIST_DIR="${ROOT_DIR}/dist"
COMPONENT_PKG="${PKG_WORK}/LazyleadVPN-component.pkg"
FINAL_PKG="${DIST_DIR}/LazyleadVPN-${VERSION}-arm64.pkg"

cd "${ROOT_DIR}"

"${ROOT_DIR}/scripts/build_app_bundle.sh" >/dev/null

rm -rf "${PKG_ROOT}" "${PKG_WORK}" "${PKG_SCRIPTS}"
mkdir -p "${PKG_ROOT}/Applications" "${PKG_WORK}" "${PKG_SCRIPTS}" "${DIST_DIR}"
COPYFILE_DISABLE=1 ditto --norsrc "${APP_DIR}" "${PKG_ROOT}/Applications/${APP_NAME}"
cp "${ROOT_DIR}/packaging/scripts/postinstall" "${PKG_SCRIPTS}/postinstall"
chmod +x "${PKG_SCRIPTS}/postinstall"

find "${PKG_ROOT}" -name '._*' -delete
xattr -cr "${PKG_ROOT}" 2>/dev/null || true

COPYFILE_DISABLE=1 pkgbuild \
  --root "${PKG_ROOT}" \
  --scripts "${PKG_SCRIPTS}" \
  --identifier "io.lazylead.vpn" \
  --version "${VERSION}" \
  --install-location "/" \
  "${COMPONENT_PKG}"

productbuild \
  --package "${COMPONENT_PKG}" \
  "${FINAL_PKG}"

echo "${FINAL_PKG}"
