#!/bin/bash
set -euo pipefail
python3 "$(dirname "$0")/sign_app.py" "$1"
