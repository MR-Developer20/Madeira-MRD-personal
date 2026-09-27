#!/bin/bash
# Build Madeira.app and package it as an IPA for sideloading.
#
#   ./scripts/make-ipa.sh                    # Debug, ad-hoc signed -> dist/Madeira.ipa
#   CONFIGURATION=Release ./scripts/make-ipa.sh
#   IDENTITY="Apple Development: ..." ./scripts/make-ipa.sh
#
# The build runs with Xcode signing disabled, so it needs no Apple account or
# provisioning profile. Every Mach-O in the bundle is then signed with IDENTITY
# (ad-hoc, "-", by default) and the app itself with Madeira.entitlements. An
# ad-hoc IPA does not install as-is: a sideloading tool (AltStore, SideStore,
# Sideloadly, ...) re-signs it with your Apple ID. It is signed anyway because
# dyld refuses a dylib with no signature at all (scripts/deploy-vm.sh).
#
# Debug is the default because Release builds have crashed the guest
# (docs/BUILDING.md).
set -euo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Debug}"
IDENTITY="${IDENTITY:--}"
OUT="${OUT:-$R/dist}"
SYMROOT="$OUT/build"
ENTITLEMENTS="$R/app/Madeira/Madeira.entitlements"

"$R/build/stage-licenses.sh"
"$R/scripts/check-ipa-inputs.sh"

xcodebuild -project "$R/app/Madeira.xcodeproj" -target Madeira \
  -configuration "$CONFIGURATION" -sdk iphoneos \
  SYMROOT="$SYMROOT" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build

APP="$SYMROOT/$CONFIGURATION-iphoneos/Madeira.app"
[ -d "$APP" ] || { echo "error: $APP was not produced"; exit 1; }

# Nested code first, the app bundle last (its seal covers the nested files).
while IFS= read -r -d '' f; do
  if file -b "$f" | grep -q "Mach-O" && [ "$f" != "$APP/Madeira" ]; then
    codesign --force --sign "$IDENTITY" --timestamp=none "$f"
  fi
done < <(find "$APP" -type f -print0)
codesign --force --sign "$IDENTITY" --timestamp=none \
  --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --deep --strict "$APP"

STAGE="$OUT/ipa"
rm -rf "$STAGE" && mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/"
rm -f "$OUT/Madeira.ipa"
(cd "$STAGE" && zip -qry -X "$OUT/Madeira.ipa" Payload)
rm -rf "$STAGE"
echo "IPA: $OUT/Madeira.ipa ($(du -h "$OUT/Madeira.ipa" | cut -f1))"
