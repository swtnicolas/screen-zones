#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
node --test tests/geometry.test.mjs tests/store.test.mjs
