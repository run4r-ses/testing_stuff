#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "* Starting optimizations"

bash "$SCRIPT_DIR/skip_setup.sh"
bash "$SCRIPT_DIR/display.sh"
bash "$SCRIPT_DIR/ui.sh"
bash "$SCRIPT_DIR/services.sh"

echo "* Optimizations completed successfully"