#!/bin/bash
# Full local regression for the device/survival revision. Uses isolated fixtures.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
bash scripts/check.sh > .build/validation-device-checks.log 2>&1
bash scripts/build-app.sh > .build/validation-device-build.log 2>&1
python3 scripts/check-device-render.py > .build/validation-device-render.log 2>&1
python3 scripts/check-pet-render.py > .build/validation-device-pet-render.log 2>&1
python3 scripts/check-window-contracts.py > .build/validation-build10-window-contracts.log 2>&1
python3 scripts/check-window-motion.py > .build/validation-device-motion.log 2>&1
python3 scripts/check-app-session.py > .build/validation-device-session.log 2>&1
codesign --verify --deep --strict build/Tomatogotchi.app
printf 'PASS: device/survival regression, Release, rendering, isolated processes and signature. Logs: .build/validation-device-*.log\n'
