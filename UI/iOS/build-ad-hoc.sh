#!/usr/bin/env bash
# Copyright (c) 2026-present, the Ladybird developers.
# SPDX-License-Identifier: BSD-2-Clause
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
device_app="${source_dir}/Build/ios-device/bin/Ladybird.app"
output_root="${OUTPUT_DIR:-${source_dir}/Build/ios-distribution}"
mkdir -p "$output_root"
# Each run is recoverable; do not delete an earlier archive or exported IPA.
output_dir="$(mktemp -d "${output_root}/ad-hoc.XXXXXX")"

cmake --build "${source_dir}/Build/ios-device" --target ladybird -j "${BUILD_JOBS:-4}"
xcrun vtool -show-build "$device_app/Ladybird" | rg -q 'platform IOS$'
ditto "${source_dir}/UI/iOS/Distribution" "$output_dir/Project"
ditto "${source_dir}/UI/iOS/Icons" "$output_dir/Project/Icons"
xcodegen generate --spec "$output_dir/Project/project.yml"
test -d "$output_dir/Project/LadybirdDistribution.xcodeproj"

xcodebuild archive \
    -project "$output_dir/Project/LadybirdDistribution.xcodeproj" \
    -scheme Ladybird -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$output_dir/Ladybird.xcarchive" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM=A6AAKKNUW9 \
    LADYBIRD_APP_PATH="$device_app"

xcodebuild -exportArchive \
    -archivePath "$output_dir/Ladybird.xcarchive" \
    -exportPath "$output_dir/export" \
    -exportOptionsPlist "${EXPORT_OPTIONS_PLIST:-${source_dir}/UI/iOS/Distribution/ExportOptions.plist}" \
    -allowProvisioningUpdates

test -f "$output_dir/export/Ladybird.ipa"
echo "IPA=$output_dir/export/Ladybird.ipa"
