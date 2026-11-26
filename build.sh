#!/bin/zsh
# Builds IceBall.app with the Swift compiler alone (Command Line Tools are enough).
# The Xcode project builds the same sources; this script exists for machines without Xcode.
set -euo pipefail

cd "${0:A:h}"
CONFIG=${1:-release}
OUT=build/$CONFIG
APP=$OUT/IceBall.app

rm -rf "$APP" "$OUT/IceBall.dSYM"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

OPT=(-O)
[[ $CONFIG == debug ]] && OPT=(-Onone -g -D DEBUG)

swiftc "${OPT[@]}" \
  -target arm64-apple-macos26.0 \
  -swift-version 6 \
  -default-isolation MainActor \
  -module-name IceBall \
  -o "$APP/Contents/MacOS/IceBall" \
  IceBall/**/*.swift

# swiftc -g drops the dSYM next to the binary; keep it out of the bundle.
[[ -d "$APP/Contents/MacOS/IceBall.dSYM" ]] && mv "$APP/Contents/MacOS/IceBall.dSYM" "$OUT/"
cp IceBall/Info.plist "$APP/Contents/Info.plist"
# SIGN_IDENTITY names a code signing certificate. With the default ad-hoc signature ("-"),
# macOS ties permissions to this exact binary, so every rebuild needs them granted again;
# with a certificate they survive rebuilds.
codesign --force --sign "${SIGN_IDENTITY:--}" --options runtime "$APP"
echo "Built $APP"
