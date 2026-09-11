#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/visual-regression
swiftc Sources/MacDuo/BlurOverlay.swift scripts/visual-regression/main.swift -o .build/visual-regression/BlurRegression
.build/visual-regression/BlurRegression
