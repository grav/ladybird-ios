set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME iOS)
set(VCPKG_OSX_SYSROOT iphonesimulator)
set(VCPKG_OSX_DEPLOYMENT_TARGET 18.0)
set(VCPKG_BUILD_TYPE release)
# Dependency command-line tools must not become iOS application bundles.
set(VCPKG_CMAKE_CONFIGURE_OPTIONS -DCMAKE_MACOSX_BUNDLE=OFF)
# Autoconf must distinguish the iOS 18 (Darwin 24) target from the Mac host,
# even though both use arm64. Otherwise ICU tries to execute simulator binaries.
set(VCPKG_MAKE_BUILD_TRIPLET --host=aarch64-apple-darwin24)
