#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build-drive.sh
node --test --test-concurrency=1 tests/e2e/run.mjs tests/e2e/displays.mjs tests/e2e/sides.mjs tests/e2e/menu.mjs tests/e2e/x11.mjs
