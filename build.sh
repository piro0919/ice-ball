#!/bin/zsh
# Builds IceBall.app with the Swift compiler alone (Command Line Tools are enough; Xcode is not needed).
#
#   ./build.sh            # release build → build/release/IceBall.app
#   ./build.sh debug      # debug build   → build/debug/IceBall.app
#
# Environment:
#   ICEBALL_VERSION           version written into Info.plist (release.sh passes it; local builds stay 0.0.0)
#   SIGN_IDENTITY             code signing certificate (default "Okigae Dev"; ad-hoc when it is missing)
#   ICEBALL_REQUIRE_IDENTITY  1 = stop instead of falling back to ad-hoc (release.sh sets it)
set -euo pipefail

cd "${0:A:h}"
CONFIG=${1:-release}
OUT=build/$CONFIG
APP=$OUT/IceBall.app
VERSION=${ICEBALL_VERSION:-0.0.0}

SPARKLE_VERSION="2.9.5"
# Checks the downloaded archive. Update together with the version; the value is the asset digest:
#   gh api repos/sparkle-project/Sparkle/releases/tags/<version> --jq '.assets[] | "\(.name) \(.digest)"'
SPARKLE_SHA256="015336b601493e05c237964954bff6191370003d94edefe663724c88840d73cc"

# An ad-hoc signature changes with every build, and macOS then drops the Accessibility
# permission. Use the local certificate when it exists. CI has none and falls back to ad-hoc.
SIGN_IDENTITY=${SIGN_IDENTITY:-Okigae Dev}
if ! security find-identity -v -p codesigning | grep -qF "\"${SIGN_IDENTITY}\""; then
  if [[ ${ICEBALL_REQUIRE_IDENTITY:-0} == 1 ]]; then
    echo "error: certificate \"${SIGN_IDENTITY}\" not found; an ad-hoc build cannot be released" >&2
    exit 1
  fi
  echo "warning: certificate \"${SIGN_IDENTITY}\" not found; signing ad-hoc (permissions will not survive rebuilds)" >&2
  SIGN_IDENTITY="-"
fi

# Sparkle is large, so it is not tracked: fetch it into Vendor/ when missing and verify it.
if [[ ! -d Vendor/Sparkle.framework ]]; then
  echo "Fetching Sparkle ${SPARKLE_VERSION}…"
  TMP=$(mktemp -d)
  curl -fsSL -o "$TMP/sparkle.tar.xz" \
    "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
  if ! echo "${SPARKLE_SHA256}  $TMP/sparkle.tar.xz" | shasum -a 256 -c - >/dev/null; then
    echo "error: SHA-256 of Sparkle ${SPARKLE_VERSION} does not match" >&2
    rm -rf "$TMP"
    exit 1
  fi
  tar xf "$TMP/sparkle.tar.xz" -C "$TMP"
  mkdir -p Vendor
  cp -R "$TMP/Sparkle.framework" "$TMP/bin" Vendor/
  rm -rf "$TMP"
fi

rm -rf "$APP" "$OUT/IceBall.dSYM"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp -R Vendor/Sparkle.framework "$APP/Contents/Frameworks/"

OPT=(-O)
[[ $CONFIG == debug ]] && OPT=(-Onone -g -D DEBUG)

swiftc "${OPT[@]}" \
  -target arm64-apple-macos26.0 \
  -swift-version 6 \
  -default-isolation MainActor \
  -module-name IceBall \
  -F Vendor \
  -framework Sparkle \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -o "$APP/Contents/MacOS/IceBall" \
  IceBall/**/*.swift

# swiftc -g drops the dSYM next to the binary; keep it out of the bundle.
[[ -d "$APP/Contents/MacOS/IceBall.dSYM" ]] && mv "$APP/Contents/MacOS/IceBall.dSYM" "$OUT/"

cp IceBall/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $VERSION" \
  "$APP/Contents/Info.plist"

# The app icon, built from the 1024 px master when it exists.
if [[ -f Resources/AppIcon.png ]]; then
  ICONSET=$OUT/AppIcon.iconset
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

# Sign from the inside out; signing the app first would be broken by signing its contents later.
SPARKLE=$APP/Contents/Frameworks/Sparkle.framework/Versions/B
for part in XPCServices/Downloader.xpc XPCServices/Installer.xpc Autoupdate Updater.app; do
  codesign --force --sign "$SIGN_IDENTITY" "$SPARKLE/$part"
done
codesign --force --sign "$SIGN_IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "$SIGN_IDENTITY" "$APP"
echo "Built $APP ($VERSION)"
