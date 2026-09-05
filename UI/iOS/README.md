# Experimental iOS LibWeb demo

This minimal embedding demo builds and runs in the iOS Simulator. The complete
engine build and live example.com rendering have been verified on an iPhone 16
simulator running iOS 18.1, using the iOS 18.2 SDK and LLVM 21.

The demo currently fetches `https://www.dr.dk/` with `NSURLSession`, parses and lays out
the response with LibWeb, and replays its display list into a software bitmap
shown by UIKit. Rendering happens locally on iOS at the screen's native scale
and renders again when the view changes size. CoreText discovers installed font
directories, which are loaded through Skia/FreeType. Generic families use
Helvetica, Times New Roman, and Courier New, with bundled SerenitySans only as
an emergency fallback. The layout-test font override is disabled.

The address field at the top loads a new page when you press Go. Bare hostnames
default to HTTPS. Only HTTP and HTTPS URLs are accepted; iOS transport security
may block plain HTTP. Starting another load cancels the previous request and
returns to the top. Drag the page to scroll; the address field stays fixed.
UIKit provides scrolling and inertia while LibWeb repaints a viewport-sized
bitmap at the current offset, rather than allocating a full-page image.

The initial scope is one static page. There is no JavaScript execution, link
navigation via page links, external subresource loader, GPU compositor, or browser
helper process. The default LibWeb `PageClient` implementations are used for
unimplemented browser callbacks. This is an embedding experiment, not a browser
for arbitrary sites.

DR's HTML renders in the simulator, but without its external stylesheets, images,
or scripts. Expect unstyled navigation and oversized inline icons, not the full
DR homepage. The original example.com smoke test uses inline CSS and needs no
external resources.

## Build

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

A physical device build is not wired up. It would need a device triplet, signing,
and a different way to execute the target layout generator.

## Port details

The iOS build selects the UIKit demo in place of the desktop UI and service
executables. ANGLE supplies headers only; FFmpeg has a reduced feature set.
Skia uses FreeType for system and bundled fonts. Desktop-only CoreServices, AppKit,
and IOKit integrations are excluded on iOS.

To check rendering after changes, launch the app and capture the simulator:

```sh
xcrun simctl io booted screenshot Build/ios-simulator/dr-dk.png
```

Check that the image shows DR navigation and page content, not just
the native loading label. CSS layout and scroll offsets remain in points while
the display list and bitmap use device pixels, preserving page size at Retina
resolution. Text is rasterized by Skia/FreeType, not CoreText.
