#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
app="$PWD/dist/MacDuo.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/MacDuo "$app/Contents/MacOS/MacDuo"
cp Resources/Info.plist "$app/Contents/Info.plist"
./scripts/sign-app.sh "$app"
printf '\nBuilt: %s\n' "$app"
