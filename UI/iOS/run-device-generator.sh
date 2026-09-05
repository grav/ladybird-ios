#!/usr/bin/env bash
# Copyright (c) 2026-present, the Ladybird developers.
# SPDX-License-Identifier: BSD-2-Clause
set -euo pipefail

# Run the arm64 device-compiled, Foundation-free layout probe in an arm64
# simulator. Only its Mach-O platform metadata changes: the code and constants
# still reflect the device compiler's ABI. Never apply this to the shipped app.
generator_copy="$(mktemp "${TMPDIR:-/tmp}/ladybird-layout.XXXXXX")"
trap 'rm -f -- "$generator_copy"' EXIT
xcrun vtool -set-build-version iossim 18.0 18.2 -replace -output "$generator_copy" "$1" >&2
chmod +x "$generator_copy"
codesign --force --sign - "$generator_copy" >&2
shift
xcrun simctl spawn booted "$generator_copy" "$@"
