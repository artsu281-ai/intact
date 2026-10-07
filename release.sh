#!/bin/bash
# Выпускает релиз на GitHub: ./release.sh 1.1
# Меняет версию в Info.plist, собирает, пакует Intact.zip, тегирует и заливает.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?Использование: ./release.sh <версия, например 1.1>}"
REPO="artsu281-ai/intact"

if [ -n "$(git status --porcelain)" ]; then
  echo "Есть незакоммиченные изменения — сначала закоммить." >&2; exit 1
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist
BUILD=$(( $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist) + 1 ))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" Resources/Info.plist

./build.sh

rm -f build/Intact.zip
ditto -ck --keepParent build/Intact.app build/Intact.zip

git add Resources/Info.plist
git commit -m "release: v$VERSION"
git tag "v$VERSION"
git push origin HEAD "v$VERSION"

gh release create "v$VERSION" build/Intact.zip --repo "$REPO" \
  --title "Intact $VERSION" --generate-notes
echo "==> релиз v$VERSION опубликован"
