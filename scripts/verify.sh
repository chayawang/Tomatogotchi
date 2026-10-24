#!/bin/bash
# Canonical automated gate. Native interaction checks remain explicitly pending.
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/verify-device.sh
python3 scripts/check-app-icon.py
python3 scripts/check-live-presentation.py

python3 scripts/check-extra-pets.py
