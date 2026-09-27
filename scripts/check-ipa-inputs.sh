#!/bin/bash
# List the build inputs app/Madeira.xcodeproj links or bundles that are not
# tracked in the repository (see docs/BUILDING.md, "Inputs that are not in the
# repository"). Exits non-zero if any required one is missing, so a build that
# cannot link stops here with the full list instead of at the first ld error.
#
#   ./scripts/check-ipa-inputs.sh
#
# When GITHUB_STEP_SUMMARY is set (GitHub Actions) the result is also written
# there as a table.
set -u
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FEXLIB="FEX/build-ios"

# path | how to produce it
REQUIRED=(
  "app/Madeira/libntdll_unix.a|build/ntdll-unix/build.sh (needs a configured wine/build-macos tree)"
  "app/Madeira/libwineserver.a|build/wineserver/build.sh (needs an existing base libwineserver.a)"
  "app/Madeira/libwin32u_unix.a|build/win32u-unix/build.sh (needs a configured wine/build-macos tree)"
  "app/Madeira/libdxmt_combined.a|build/dxmt-ios/build.sh (needs toolchains/llvm-ios-build)"
  "$FEXLIB/FEXCore/Source/libFEXCore.a|build/fex-ios/build.sh"
  "$FEXLIB/FEXCore/Source/libFEXCore_Base.a|build/fex-ios/build.sh"
  "$FEXLIB/FEXCore/Source/libJemallocLibs.a|build/fex-ios/build.sh"
  "$FEXLIB/External/fmt/libfmt.a|build/fex-ios/build.sh"
  "$FEXLIB/External/cephes/libcephes_128bit.a|build/fex-ios/build.sh"
  "$FEXLIB/External/xxhash/cmake_unofficial/libxxhash.a|build/fex-ios/build.sh"
  "$FEXLIB/External/SoftFloat-3e/libsoftfloat_3e.a|build/fex-ios/build.sh"
)

missing=0
rows=""
for entry in "${REQUIRED[@]}"; do
  path="${entry%%|*}"; how="${entry#*|}"
  if [ -f "$R/$path" ]; then
    echo "  ok       $path"
    rows+="| \`$path\` | ok | |"$'\n'
  else
    echo "  MISSING  $path  <- $how"
    rows+="| \`$path\` | **missing** | $how |"$'\n'
    missing=$((missing + 1))
  fi
done

# The project references this folder; Xcode fails if it does not exist. Its
# contents are Microsoft redistributables supplied by the builder
# (tools/fetch-vcruntime.md), so an empty folder is allowed with a warning.
VC="app/Madeira/x86_64-vcruntime"
if ! ls "$R/$VC"/*.dll >/dev/null 2>&1; then
  mkdir -p "$R/$VC"
  echo "  WARNING  $VC has no DLLs; created it empty (see tools/fetch-vcruntime.md)"
  rows+="| \`$VC/\` | empty (warning) | tools/fetch-vcruntime.md |"$'\n'
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### IPA build inputs"
    echo
    echo "| Input | Status | Produced by |"
    echo "|---|---|---|"
    printf "%s" "$rows"
  } >> "$GITHUB_STEP_SUMMARY"
fi

if [ "$missing" -ne 0 ]; then
  echo "$missing required input(s) missing; the app cannot link without them."
  exit 1
fi
echo "all required inputs present"
