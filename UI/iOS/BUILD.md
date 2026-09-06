# Building and testing the iOS demo

## Simulator build

The current build path targets an **arm64 iOS 18+ Simulator on an Apple Silicon
Mac**. Xcode must include the iOS Simulator SDK, and a simulator must be booted
during the build: LibJS's C++ layout generator executes there so its offsets
match the target ABI. The Rust code generators run on the Mac.

Install the normal Ladybird build prerequisites, including CMake, Ninja, LLVM 21, and
the Rust version specified by `rust-toolchain.toml`. With rustup installed, add
the target standard library from the repository root:

```sh
rustup target add aarch64-apple-ios-sim
python3 Meta/Utils/build_vcpkg.py
open -a Simulator
ios_llvm_prefix="$(brew --prefix llvm@21)"
bash UI/iOS/configure.sh \
    -DCMAKE_C_COMPILER="${ios_llvm_prefix}/bin/clang" \
    -DCMAKE_CXX_COMPILER="${ios_llvm_prefix}/bin/clang++" \
    -DCMAKE_OBJCXX_COMPILER="${ios_llvm_prefix}/bin/clang++" \
    -DCMAKE_ASM_COMPILER="${ios_llvm_prefix}/bin/clang"
cmake --build Build/ios-simulator --target ladybird -j2
```

`VCPKG_ROOT` can select a separate bootstrapped checkout at this repository's
pinned vcpkg baseline. Extra arguments to `configure.sh` are passed to CMake,
including `-DRUST_CARGO=...` and `-DRUST_RUSTC=...` for a standalone Rust install.
Dependencies and build outputs go under `Build/ios-simulator`.

After a successful build, install and launch the bundle:

```sh
xcrun simctl install booted Build/ios-simulator/bin/Ladybird.app
xcrun simctl launch booted org.ladybird.ios-demo
```

## Physical device and ad-hoc distribution

Keep an ARM64 simulator booted for the device build too: it runs the temporary
copy of the device-compiled layout probe described in [README.md](README.md).

The device target uses a separate build tree and `iphoneos` dependencies. Install
the `aarch64-apple-ios` Rust target, then use the same compiler arguments as above
with `IOS_TARGET=device`:

```sh
rustup target add aarch64-apple-ios
IOS_TARGET=device bash UI/iOS/configure.sh \
    -DCMAKE_C_COMPILER="${ios_llvm_prefix}/bin/clang" \
    -DCMAKE_CXX_COMPILER="${ios_llvm_prefix}/bin/clang++" \
    -DCMAKE_OBJCXX_COMPILER="${ios_llvm_prefix}/bin/clang++" \
    -DCMAKE_ASM_COMPILER="${ios_llvm_prefix}/bin/clang"
bash UI/iOS/build-ad-hoc.sh
```

XcodeGen is required for packaging. The script follows Radarvejr's automatic
Xcode archive/export workflow using team `A6AAKKNUW9` and bundle identifier
`dk.klokke.ladybird`. Change these settings in `Distribution/` for another team.
Xcode must have access to that developer account and the destination device must
be included in the ad-hoc provisioning profile. Each run keeps its archive and
IPA in a fresh directory under `Build/ios-distribution`, printing the IPA path.
Nothing is submitted to the App Store or TestFlight.

The app uses PNG icons derived from the existing 1024px logo in
`UI/Icons/macos/app_icon.iconset`. They are bundled directly using
`CFBundleIcons`, without requiring an asset-catalog compiler or a matching
simulator runtime during packaging.

If distribution signing is unavailable but a local development profile includes
the phone, explicitly choose development signing instead:

```sh
EXPORT_OPTIONS_PLIST="$PWD/UI/iOS/Distribution/DevelopmentExportOptions.plist" \
    bash UI/iOS/build-ad-hoc.sh
```

This produces a development-signed IPA, not an ad-hoc distribution IPA. It needs
Developer Mode enabled on the phone. The script does not silently downgrade
the signing method when an ad-hoc export fails.

For a paired phone, install the exported IPA without a debugger using:

```sh
uv run UI/iOS/install-ipa.py --udid DEVICE_UDID /path/to/Ladybird.ipa
```

Add `--developer` for a development-signed IPA. The native transport uses macOS's
existing device connection and closes it explicitly after checking that the app
is installed. Select the iPhone's UDID explicitly rather than allowing a tool to
choose another attached device. App installation and debugger/device-image
support are separate checks.

## Resource-loading smoke test

Run `python3 UI/iOS/Tests/server.py` in another terminal, then:

```sh
xcrun simctl terminate booted org.ladybird.ios-demo
xcrun simctl launch booted org.ladybird.ios-demo -URL http://localhost:8765/
xcrun simctl io booted screenshot Build/ios-simulator/resources.png
```

The linked CSS box must be green, the imported CSS box blue, and the wrong-MIME
paragraph visible. Both the image and CSS background must show red on the left
and blue on the right; invalid PNG data must show the broken-image fallback.
A missing stylesheet must not block rendering. The fixture's
`/requests` endpoint lists received requests to verify the redirect and import.
These checks and live Hacker News stylesheet rendering passed on the simulator.
`-URL` is an optional launch argument for choosing a test page without editing code.

The `/links` fixture tests nested text in a relative link under a base URL and a
second link below the fold. Both must load `/destination`, including after
scrolling. Blank page taps must leave the address unchanged.
For history, follow the scrolled link, go Back, check the restored offset, and go
Forward. Then go Back and enter a different address: Forward must be disabled.

The `/fonts` fixture verifies same-origin TTF, cross-origin allowed/denied TTF,
invalid-font fallback, and WOFF2 Ethiopic glyphs. The first two samples must use
the distinctive bundled test font fetched over HTTP; CORS-denied and invalid
samples must remain in Helvetica. No font CORS bypass is used.
