#!/bin/bash
# Manual compatibility entrypoint for LittleRip iOS reset.
# It performs one foreground transaction and never schedules itself.

set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/scripts/littlerip-ios-reset.sh" "$@"
