#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT_DIR/build/domain-routing"
archive="$ROOT_DIR/build/socket_vmnet-1.2.2-arm64.tar.gz"
if [[ ! -f "$archive" ]]; then
  curl -fL --connect-timeout 10 --max-time 120 \
    https://github.com/lima-vm/socket_vmnet/releases/download/v1.2.2/socket_vmnet-1.2.2-arm64.tar.gz \
    -o "$archive.download"
  mv "$archive.download" "$archive"
fi
[[ "$(shasum -a 256 "$archive" | awk '{print $1}')" == c7bf62308fbcfdc29bdfb8373c9b1951f7ac2396446e4390919796a94972e6dc ]]
python3 -m pip download --no-deps --only-binary=:all: \
  --dest "$ROOT_DIR/build/domain-routing" dnslib==0.9.26
wheel="$ROOT_DIR/build/domain-routing/dnslib-0.9.26-py3-none-any.whl"
[[ "$(shasum -a 256 "$wheel" | awk '{print $1}')" == e68719e633d761747c7e91bd241019ef5a2b61a63f56025939e144c841a70e0d ]]
python3 - "$wheel" "$ROOT_DIR/build/domain-routing/vendor" <<'PY'
import sys
import zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    archive.extractall(sys.argv[2])
PY
echo 'Dependencies downloaded and checksums verified. No system settings changed.'
