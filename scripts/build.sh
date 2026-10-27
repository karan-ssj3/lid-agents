#!/bin/bash
# Builds build/LidAgents.app (universal, ad-hoc signed) and dist/lid-agents.tar.gz.
#   scripts/build.sh [version]     version defaults to the VERSION file
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(cat VERSION)}"
VERSION="${VERSION#v}"
APP="build/LidAgents.app"

rm -rf build dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj build/AppIcon.iconset dist

echo "==> Compiling (arm64 + x86_64)"
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" -o "build/obj/LidAgents-$arch" app/LidAgents.swift
done
lipo -create -output "$APP/Contents/MacOS/LidAgents" build/obj/LidAgents-arm64 build/obj/LidAgents-x86_64

echo "==> Bundling $VERSION"
sed "s/__VERSION__/$VERSION/g" app/Info.plist > "$APP/Contents/Info.plist"
sed "s/^AGENTS_VERSION=.*/AGENTS_VERSION=\"$VERSION\"/" bin/agents > "$APP/Contents/Resources/agents"
chmod 755 "$APP/Contents/Resources/agents"

echo "==> Icon"
swift assets/make_icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Signing (ad hoc)"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"

COPYFILE_DISABLE=1 tar --no-mac-metadata -C build -czf dist/lid-agents.tar.gz LidAgents.app
echo "==> dist/lid-agents.tar.gz ($(du -h dist/lid-agents.tar.gz | cut -f1))"
