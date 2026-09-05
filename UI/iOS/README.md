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

Tap HTML links to load their targets in the current view. LibWeb hit testing
handles nested link content, scroll offsets, and relative URLs (including base
URLs). Downloads and non-HTTP(S) links are ignored. This is URL navigation, not
full pointer-event dispatch; forms, new windows, and fragment scrolling are not
implemented yet.

Back and Forward buttons maintain in-memory URL history. Successful loads add
entries; failed or cancelled loads do not. Back/forward refetch the HTML and
restore the saved scroll offset (allowing up to three seconds for asynchronous
layout growth). Dragging cancels pending scroll restoration. Navigating to a new
URL after going back removes the forward entries. This is not a back/forward
document cache, and history does not persist across app launches.

There is no JavaScript execution, GPU compositor, or browser
helper process. The default LibWeb `PageClient` implementations are used for
unimplemented browser callbacks. This is an embedding experiment, not a browser
for arbitrary sites.

External stylesheets (including CSS imports) load through an optional in-process
ResourceLoader transport backed by NSURLSession. LibWeb handles redirects and
stylesheet MIME checks. A display link pumps engine tasks and repaints after
asynchronous updates. External images, CSS backgrounds, and downloaded
`@font-face` fonts also load; scripts are not enabled yet. This remains an incomplete rendering of
sites such as DR.

Font requests use LibWeb's existing font parsing and CORS checks. Same-origin
fonts and cross-origin fonts with appropriate response headers are supported;
blocked or malformed fonts fall back to the selected system family. TTF and
WOFF2 loading have been verified with the local fixture.

Raster images use Ladybird's LibImageDecoders in-process on the engine thread;
SVG images use LibWeb's SVG support. The demo displays only the first frame of
animated images, rejects raster dimensions above 16 megapixels, and preserves
decoded color profiles and premultiplied alpha. There is no isolated decoder
process, and large decodes can temporarily block the UI.

The transport currently supports GET requests only, buffers each response, and
rejects bodies over 16 MiB after download. It uses an ephemeral session with no
automatic cookies or credential storage. Navigation cancels outstanding resource
tasks; individual Fetch cancellation, cache transfers, and detailed network
timings are not implemented. The initial HTML load is still a simplified native
fetch rather than full LibWeb navigation (including response-header policies).

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
