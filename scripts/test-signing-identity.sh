#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d "$PWD/.build/signing-regression.XXXXXX")
trap 'rm -rf "$work"' EXIT
cp -R dist/MacDuo.app "$work/First.app"
cp -R dist/MacDuo.app "$work/Updated.app"
scripts/sign-app.sh "$work/First.app"
codesign -d -r- "$work/First.app" 2>&1 | sed -n 's/^#* *designated => //p' > "$work/original.req"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 999' "$work/Updated.app/Contents/Info.plist"
scripts/sign-app.sh "$work/Updated.app"
if codesign --verify --strict -R "$work/original.req" "$work/Updated.app"; then
    echo 'PASS: updated app satisfies the original identity; authorization can survive rebuilding'
else
    echo 'FAIL: rebuilding changes the app identity; previous authorization no longer matches'
    exit 1
fi
