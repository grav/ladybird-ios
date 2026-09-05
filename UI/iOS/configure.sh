#!/usr/bin/env bash

# Copyright (c) 2026-present, the Ladybird developers.
# SPDX-License-Identifier: BSD-2-Clause

set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
vcpkg_root="${VCPKG_ROOT:-${source_dir}/Build/vcpkg}"
build_dir="${source_dir}/Build/ios-simulator"
export VCPKG_MAX_CONCURRENCY="${VCPKG_MAX_CONCURRENCY:-2}"

if [[ ! -x "${vcpkg_root}/vcpkg" ]]; then
    echo "Bootstrap vcpkg first with: python3 Meta/Utils/build_vcpkg.py" >&2
    exit 1
fi

cmake -S "${source_dir}" -B "${build_dir}" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="${vcpkg_root}/scripts/buildsystems/vcpkg.cmake" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_SYSTEM_PROCESSOR=arm64 \
    -DCMAKE_OSX_SYSROOT=iphonesimulator \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 \
    -DCMAKE_MACOSX_BUNDLE=OFF \
    '-DCMAKE_CROSSCOMPILING_EMULATOR=xcrun;simctl;spawn;booted' \
    -DCMAKE_BUILD_TYPE=Release \
    -DVCPKG_TARGET_TRIPLET=arm64-ios-simulator \
    -DVCPKG_OVERLAY_TRIPLETS="${source_dir}/UI/iOS" \
    -DRUST_TARGET_TRIPLE=aarch64-apple-ios-sim \
    -DENABLE_CRANELIFT_JIT=OFF \
    -DENABLE_LTO_FOR_RELEASE=OFF \
    -DENABLE_INSTALL_HEADERS=OFF \
    -DENABLE_CLANG_PLUGINS=OFF \
    "$@"
