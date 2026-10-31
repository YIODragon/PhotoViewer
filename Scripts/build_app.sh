#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="PhotoViewer"
CONFIGURATION="release"
APP_PATH="dist/${APP_NAME}.app"

echo "==> Building ${APP_NAME} (${CONFIGURATION})"
swift build -c "${CONFIGURATION}" "$@"

echo "==> Assembling ${APP_PATH}"
rm -rf "${APP_PATH}"
mkdir -p "${APP_PATH}/Contents/MacOS" "${APP_PATH}/Contents/Resources"

cp ".build/${CONFIGURATION}/${APP_NAME}" "${APP_PATH}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP_PATH}/Contents/Info.plist"
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${APP_PATH}/Contents/Resources/AppIcon.icns"
    chmod 644 "${APP_PATH}/Contents/Resources/AppIcon.icns"
fi
chmod 755 "${APP_PATH}/Contents/MacOS/${APP_NAME}"
chmod 644 "${APP_PATH}/Contents/Info.plist"

/usr/bin/plutil -lint "${APP_PATH}/Contents/Info.plist" >/dev/null

# Ad-hoc signature is enough for local use. Distribution requires a Developer ID
# certificate and notarization.
/usr/bin/codesign --force --deep --sign - "${APP_PATH}" >/dev/null 2>&1

echo "==> Done: ${APP_PATH}"
echo "    open \"${APP_PATH}\""
