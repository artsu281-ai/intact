#!/bin/bash
# Собирает Intact.app и ставит его в /Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Intact"
BUNDLE="build/$APP_NAME.app"
DEST="/Applications/$APP_NAME.app"

echo "==> swift build -c release"
swift build -c release

echo "==> сборка бандла"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp ".build/release/$APP_NAME" "$BUNDLE/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
cp Resources/* "$BUNDLE/Contents/Resources/" 2>/dev/null || true
xattr -cr "$BUNDLE"
xattr -cr Resources/ 2>/dev/null || true

# Стабильная подпись: designated requirement привязывается к сертификату,
# а не к хешу сборки, поэтому выданные системные разрешения переживают пересборку.
# Ad-hoc оставлен запасным вариантом — с ним права слетают после каждой сборки.
IDENTITY="VoiceInput Local Signing"
if ! security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  IDENTITY="Intact Local Signing"
fi

if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  echo "==> подпись сертификатом «${IDENTITY}»"
  codesign --force --deep --sign "$IDENTITY" \
    --entitlements Resources/Intact.entitlements "$BUNDLE"
else
  echo "==> ad-hoc подпись (разрешения слетят после сборки)"
  codesign --force --deep --sign - \
    --entitlements Resources/Intact.entitlements "$BUNDLE" 2>/dev/null \
    || codesign --force --deep --sign - "$BUNDLE"
fi

echo "==> установка в /Applications"
pkill -x "VoiceInput" 2>/dev/null || true
pkill -x "Intact" 2>/dev/null || true
pkill -9 -f "whisper-server" 2>/dev/null || true
sleep 1
rm -rf "$DEST"
cp -R "$BUNDLE" "$DEST"

echo "==> готово: $DEST"
