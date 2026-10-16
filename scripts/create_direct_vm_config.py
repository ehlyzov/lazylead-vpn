#!/usr/bin/env python3
"""Generate a Lima template without modifying or starting any existing VM."""
import argparse
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, default=root / 'build/lima-direct.yaml')
parser.add_argument('--downloads', type=Path, default=Path.home() / 'Downloads')
args = parser.parse_args()
if args.output.exists():
    parser.error('Output already exists; choose a new --output path')
script = (root / 'scripts/vm_direct_network.sh').read_text()
config = '''minimumLimaVersion: 2.0.0
images:
  - location: https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-24.04-server-cloudimg-arm64.img
    arch: aarch64
cpus: 2
memory: 2GiB
disk: 20GiB
vmType: vz
mountType: virtiofs
mounts:
  - location: DOWNLOADS
    mountPoint: /mnt/mac-downloads
    writable: true
networks:
  - vzNAT: true
  - socket: /private/var/run/lazylead-direct.sock
    interface: direct0
containerd:
  user: false
  system: false
portForwards:
  - guestIP: 127.0.0.1
    guestPort: 9091
    hostIP: 127.0.0.1
    hostPort: 9092
  - guestPort: 51413
    ignore: true
provision:
  - mode: system
    script: |
'''.replace('DOWNLOADS', json.dumps(str(args.downloads.expanduser().resolve())))
config += ''.join('      ' + line + '\n' for line in script.splitlines())
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(config)
print(args.output)
