#!/usr/bin/env bash

# Copyright (c) 2026-present, the Ladybird developers.
# SPDX-License-Identifier: BSD-2-Clause

set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
vcpkg_root="${VCPKG_ROOT:-${source_dir}/Build/vcpkg}"
ios_target="${IOS_TARGET:-simulator}"
case "$ios_target" in
    simulator)
        ios_sdk=iphonesimulator
        ios_rust_target=aarch64-apple-ios-sim
        ios_emulator='xcrun;simctl;spawn;booted'
        ;;
    device)
        ios_sdk=iphoneos
        ios_rust_target=aarch64-apple-ios
        ios_emulator="bash;${source_dir}/UI/iOS/run-device-generator.sh"
        ;;
    *) echo "IOS_TARGET must be simulator or device" >&2; exit 1 ;;
esac
build_dir="${source_dir}/Build/ios-${ios_target}"
export VCPKG_MAX_CONCURRENCY="${VCPKG_MAX_CONCURRENCY:-2}"

if [[ ! -x "${vcpkg_root}/vcpkg" ]]; then
    echo "Bootstrap vcpkg first with: python3 Meta/Utils/build_vcpkg.py" >&2
    exit 1
fi

cmake -S "${source_dir}" -B "${build_dir}" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="${vcpkg_root}/scripts/buildsystems/vcpkg.cmake" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_SYSTEM_PROCESSOR=arm64 \
    -DCMAKE_OSX_SYSROOT="${ios_sdk}" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 \
    -DCMAKE_MACOSX_BUNDLE=OFF \
    -DCMAKE_CROSSCOMPILING_EMULATOR="${ios_emulator}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DVCPKG_TARGET_TRIPLET="arm64-ios-${ios_target}" \
    -DVCPKG_OVERLAY_TRIPLETS="${source_dir}/UI/iOS" \
    -DRUST_TARGET_TRIPLE="${ios_rust_target}" \
    -DENABLE_CRANELIFT_JIT=OFF \
    -DENABLE_LTO_FOR_RELEASE=OFF \
    -DENABLE_INSTALL_HEADERS=OFF \
    -DENABLE_CLANG_PLUGINS=OFF \
    "$@"
