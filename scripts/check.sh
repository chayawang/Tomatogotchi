#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFT_MODULECACHE_PATH="$PWD/.build/module-cache"
swift run --disable-sandbox CoreChecks
swift run --disable-sandbox FlowChecks
swift run --disable-sandbox DesktopChecks
swift run --disable-sandbox CareChecks
swift run --disable-sandbox GrowthChecks
swift run --disable-sandbox ReminderChecks
swift run --disable-sandbox SessionChecks
swift run --disable-sandbox CareFlowChecks

swift run --disable-sandbox SurvivalChecks

swift run --disable-sandbox PresentationChecks

swift run --disable-sandbox MemorialChecks
