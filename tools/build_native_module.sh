#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
artifact_dir="${1:?Pass a NEW output directory for the native module}"
if [ -e "$artifact_dir" ]; then
    echo "Output already exists; choose a new directory." >&2
    exit 1
fi
mkdir -p "$artifact_dir/iphoneos" "$artifact_dir/iphonesimulator"
for native_platform in iphoneos iphonesimulator; do
    sdk_path="$(xcrun --sdk "$native_platform" --show-sdk-path)"
    if [ "$native_platform" = iphoneos ]; then
        native_target=arm64-apple-ios17.0
    else
        native_target=arm64-apple-ios17.0-simulator
    fi
    xcrun --sdk "$native_platform" clang++ -target "$native_target" -isysroot "$sdk_path" \
        -std=c++17 -O2 -Wall -Wextra -Werror -I "$project_root/native/include" \
        -c "$project_root/native/EHRHostCore.cpp" -o "$artifact_dir/$native_platform/EHRHostCore.o"
    xcrun libtool -static -o "$artifact_dir/$native_platform/libEHRHostCore.a" \
        "$artifact_dir/$native_platform/EHRHostCore.o"
done
xcodebuild -create-xcframework \
    -library "$artifact_dir/iphoneos/libEHRHostCore.a" -headers "$project_root/native/include" \
    -library "$artifact_dir/iphonesimulator/libEHRHostCore.a" -headers "$project_root/native/include" \
    -output "$artifact_dir/EHRHostCore.xcframework"
echo "Static native rule module built. No Among Us adapter is included."
