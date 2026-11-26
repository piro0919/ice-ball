#!/bin/zsh
# Releases one version of Ice Ball: builds it, makes the DMG, signs the update feed,
# and puts all three on GitHub Releases.
#
#   ./release.sh 0.1.1
#
# The Sparkle signing key is in the login keychain and is shared with the other kkweb Mac apps.
# Losing it means copies already installed can never be updated again.
set -euo pipefail

cd "${0:A:h}"

VERSION=${1:-}
REPO="piro0919/ice-ball"
APP="build/release/IceBall.app"
DMG="IceBall-${VERSION}.dmg"
ZIP="IceBall-${VERSION}.zip"

fail() {
  echo "error: $*" >&2
  exit 1
}

# Check everything first; build nothing if any check fails.
[[ $VERSION =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || fail "usage: ./release.sh <version>, e.g. ./release.sh 0.1.1"

# With a dirty tree, what ships would not be in any commit.
if [[ -n $(git status --porcelain) ]]; then
  git status --short >&2
  fail "the working tree has uncommitted changes"
fi

# The tag goes on this commit, which therefore has to be on GitHub already.
HEAD_SHA=$(git rev-parse HEAD)
git fetch -q origin main
git merge-base --is-ancestor "$HEAD_SHA" origin/main || fail "HEAD (${HEAD_SHA:0:7}) is not on origin/main; push first"
if git rev-parse -q --verify "refs/tags/v${VERSION}" >/dev/null ||
  git ls-remote --exit-code --tags origin "refs/tags/v${VERSION}" >/dev/null; then
  fail "tag v${VERSION} already exists"
fi

# Release notes come from this version's section of CHANGELOG.md.
# --generate-notes would skip commits pushed straight to main.
NOTES_FILE=$(mktemp)
trap 'rm -f "$NOTES_FILE"' EXIT
awk -v head="## [${VERSION}]" '
  /^## / { if (found) exit; if (index($0, head) == 1) { found = 1; next } }
  found { print }
' CHANGELOG.md >"$NOTES_FILE"
grep -q '[^[:space:]]' "$NOTES_FILE" || fail "CHANGELOG.md has no (or an empty) \"## [${VERSION}]\" section"

./test.sh
ICEBALL_VERSION=$VERSION ICEBALL_REQUIRE_IDENTITY=1 ./build.sh

BUILT_VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
[[ $BUILT_VERSION == "$VERSION" ]] || fail "the app says ${BUILT_VERSION}, expected ${VERSION}"
codesign --verify --deep --strict "$APP" || fail "the app's signature is broken"
# An ad-hoc build would drop the user's permissions on every update.
SIGN_IDENTITY=${SIGN_IDENTITY:-Okigae Dev}
codesign -dvv "$APP" 2>&1 | grep -qx "Authority=${SIGN_IDENTITY}" || fail "not signed with \"${SIGN_IDENTITY}\""

rm -rf dist
# generate_appcast stops when it sees two archives of one version, so the zip and the DMG
# are kept in separate directories.
mkdir -p dist/update
# Updates are delivered as a zip, which Sparkle takes as is.
ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/update/$ZIP"

# First installs use the DMG: drag the app onto Applications.
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Ice Ball" -srcfolder "$STAGE" -ov -format UDZO "dist/$DMG"
rm -rf "$STAGE"

# Signs the feed with the key in the login keychain; the first run asks for access.
./Vendor/bin/generate_appcast \
  --download-url-prefix "https://github.com/${REPO}/releases/download/v${VERSION}/" \
  dist/update

gh release create "v${VERSION}" \
  --repo "$REPO" \
  --title "v${VERSION}" \
  --target "$HEAD_SHA" \
  --notes-file "$NOTES_FILE" \
  "dist/${DMG}" "dist/update/${ZIP}" "dist/update/appcast.xml"

echo "Done: https://github.com/${REPO}/releases/tag/v${VERSION}"
