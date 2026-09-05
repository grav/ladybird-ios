add_executable(ladybird MACOSX_BUNDLE main.mm)
set_target_properties(ladybird PROPERTIES
    OUTPUT_NAME Ladybird
    OBJCXX_STANDARD 23
    OBJCXX_STANDARD_REQUIRED YES
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist"
    MACOSX_BUNDLE_GUI_IDENTIFIER org.ladybird.ios-demo
    MACOSX_BUNDLE_BUNDLE_VERSION 1
    MACOSX_BUNDLE_SHORT_VERSION_STRING 0.1
    XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
)
target_compile_options(ladybird PRIVATE -fobjc-arc
    -Wno-unqualified-std-cast-call -Wno-user-defined-literals
    -Wno-unknown-warning-option -Wno-invalid-offsetof)
target_link_libraries(ladybird PRIVATE AK LibCore LibGfx LibJS LibWeb LibURL
    "-framework UIKit" "-framework CoreGraphics" "-framework CoreText")

add_custom_command(TARGET ladybird POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_directory
        "${LADYBIRD_SOURCE_DIR}/Base/res"
        "$<TARGET_BUNDLE_DIR:ladybird>/res"
)
