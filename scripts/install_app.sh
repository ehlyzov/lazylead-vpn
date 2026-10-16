#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_app="$ROOT_DIR/build/Lazylead VPN.app"
destination='/Applications/Lazylead VPN.app'
[[ -x "$source_app/Contents/MacOS/LazyleadVPN" ]] || {
  echo 'Build the app first: ./scripts/build_app_bundle.sh' >&2; exit 1;
}
codesign --verify --strict "$source_app"
[[ -w /Applications && ( ! -e "$destination" || -w "$destination" ) ]] || {
  echo 'The current user cannot update /Applications/Lazylead VPN.app.' >&2; exit 1;
}
[[ ! -L "$destination" ]] || { echo 'Refusing a symlinked app destination.' >&2; exit 1; }
staging="$(mktemp -d /Applications/.lazylead-install.XXXXXX)"
trap 'rm -rf "$staging"' EXIT
ditto "$source_app" "$staging/Lazylead VPN.app"
codesign --verify --strict "$staging/Lazylead VPN.app"
if [[ -d "$destination" ]]; then
  backup="$ROOT_DIR/build/Lazylead VPN.before-$(date +%Y%m%d-%H%M%S).app"
  ditto "$destination" "$backup"
  echo "Previous version: $backup"
fi
# Only terminate this user's installed menu-bar process. The VM keeps running.
running="$(pgrep -u "$(id -u)" -f '^/Applications/Lazylead VPN[.]app/Contents/MacOS/LazyleadVPN$' || true)"
if [[ -n "$running" ]]; then
  kill -TERM $running
  for attempt in {1..30}; do
    pgrep -u "$(id -u)" -f '^/Applications/Lazylead VPN[.]app/Contents/MacOS/LazyleadVPN$' >/dev/null || break
    sleep 0.1
  done
  if pgrep -u "$(id -u)" -f '^/Applications/Lazylead VPN[.]app/Contents/MacOS/LazyleadVPN$' >/dev/null; then
    echo 'The app did not quit. Installation was not changed.' >&2; exit 1
  fi
fi
if [[ -d "$destination" ]]; then
  mv "$destination" "$staging/previous.app"
fi
if ! mv "$staging/Lazylead VPN.app" "$destination"; then
  [[ ! -d "$staging/previous.app" ]] || mv "$staging/previous.app" "$destination"
  exit 1
fi
open "$destination"
echo "Installed: $destination"
