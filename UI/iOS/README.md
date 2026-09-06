# Experimental iOS LibWeb demo

A small UIKit browser powered by Ladybird's own LibWeb engine, not a WebKit
wrapper. It opens Hacker News by default and supports a URL bar, scrolling,
links, back/forward history, CSS, images, and web fonts. It runs in the simulator
and has been confirmed working on a physical iPhone. JavaScript, forms, and
full browser navigation are not implemented.

## What made the port difficult

### Cross-compiling the engine and its dependencies

Building only a small UI still means building much of Ladybird's engine.
The port uses LLVM 21 for the required C++ features, Xcode's iOS SDKs, and Rust
with separate simulator and device targets. Custom vcpkg triplets keep
`iphonesimulator` and `iphoneos` dependencies in separate build trees:
sharing the ARM64 architecture does not make their binaries interchangeable.

Desktop UI and helper-process targets had to be excluded, along with macOS-only
AppKit, CoreServices, and IOKit integrations. ANGLE supplies headers only,
FFmpeg uses a reduced feature set, and Skia renders in software.

### Running code generators while cross-compiling

LibJS generates interpreter assembly using field offsets measured by a C++
layout probe. Running that probe as a normal Mac executable would not establish
the target ABI. The simulator build runs it inside a booted ARM64 simulator.

For the device build, the probe is compiled for the device ABI. A temporary copy
has its Mach-O platform metadata changed so this small, Foundation-free tool can
run in the simulator. The shipped app and libraries are never retargeted this
way. Rust code generators run on the Mac.

The interpreter also assumed Apple ARM targets supported FEAT_JSCVT, which the
generic iOS assembler target did not enable. iOS now uses the existing portable
numeric conversion sequence instead.

### Replacing desktop browser services

The minimal app has no separate networking, decoding, or compositor processes.
An in-process `NSURLSession` transport supplies resources to LibWeb, while image
decoding runs locally. UIKit displays Skia's software bitmap and handles
scrolling; a display link pumps engine tasks and repaints as resources arrive.

Fonts needed separate attention: CoreText discovers installed font files,
Skia/FreeType loads them, and the layout-test font override is disabled.
Layout stays in points while rendering uses device pixels for Retina output.

### Getting past device-only startup crashes

A successful simulator build did not guarantee a working iPhone app. Crash
reports revealed two virtual-address reservations that were too large:

- Primitive storage reserved 4 TiB; the iOS limit is now 256 MiB.
- The generic ARM64 GC heap reserved 128 GiB, temporarily doubled for alignment.
  iOS now uses a 1 GiB region with a temporary 2 GiB alignment reservation.

These reserve address space, not that much physical RAM. Both C++ and generated
interpreter masks derive from the respective limits, keeping pointer encoding
and bounds consistent.

The next crash came from creating the theme's anonymous buffer. POSIX
shared-memory backing was replaced on iOS with immediately unlinked files in
the app's private temporary directory. Shared mappings and snapshots remain
supported; all 11 anonymous-buffer tests passed in the simulator.

### Signing and installing a CMake-built app

CMake builds the real executable; a small XcodeGen project packages it. Its
mandatory build phase replaces a placeholder with the device executable and
resources, rejects simulator binaries, and lets Xcode sign and export the app.

Ad-hoc export initially reported command-line credential errors, so the working
device installs used an explicitly selected development profile. Installation
was another separate hurdle: Xcode's developer disk image did not support the
phone, but installation without a debugger worked through macOS's native device
connection using `pymobiledevice3`.

## Building and testing

See [BUILD.md](BUILD.md) for prerequisites, simulator and device builds, IPA
export, installation, and smoke-test fixtures.
