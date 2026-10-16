# iOS App Target & IPA Packaging
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/Info.plist.in
    ${CMAKE_CURRENT_BINARY_DIR}/Info.plist
    @ONLY
)

set(IOS_SOURCES
    src/main.mm
    src/AppDelegate.mm
    src/GameViewController.mm
    src/DMCAssetManager.mm
    src/DisplayLinkManager.mm
    src/TouchOverlayView.mm
    src/ControllerManager.mm
    src/DMCBootTrace.mm
    ../src/dmc4_hooks.cpp
    ../src/lzx/lzxd.c
    ../src/lzx/lzx_decompress.cpp
    ../renderer/vulkan_metal_bridge.mm
    ${DMC4_GAME_SOURCES}
)

set(IOS_HEADERS
    src/AppDelegate.h
    src/GameViewController.h
    src/DMCAssetManager.h
    src/DisplayLinkManager.h
    src/TouchOverlayView.h
    src/ControllerManager.h
    src/DMCBootTrace.h
    ../src/dmc4_hooks.h
    ../src/lzx/lzx_decompress.h
    ../renderer/vulkan_metal_bridge.h
    ../src/recompiled/dmc4_recomp.h
)

add_executable(DMC4iOS
    ${IOS_SOURCES}
    ${IOS_HEADERS}
)

set_target_properties(DMC4iOS PROPERTIES
    MACOSX_BUNDLE TRUE
    MACOSX_BUNDLE_INFO_PLIST ${CMAKE_CURRENT_BINARY_DIR}/Info.plist
    XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "-"
    XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED "NO"
    XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO"
    XCODE_ATTRIBUTE_CODE_SIGN_ENTITLEMENTS "${CMAKE_CURRENT_SOURCE_DIR}/dmc4.entitlements"
    OUTPUT_NAME "DevilMayCry4"
)

# Frameworks
find_library(FOUNDATION_FRAMEWORK Foundation REQUIRED)
find_library(COREGRAPHICS_FRAMEWORK CoreGraphics REQUIRED)
find_library(UIKIT_FRAMEWORK UIKit REQUIRED)
find_library(METAL_FRAMEWORK Metal REQUIRED)
find_library(METALL_FRAMEWORK MetalKit REQUIRED)
find_library(QUARTZ_FRAMEWORK QuartzCore REQUIRED)
find_library(AVFOUNDATION_FRAMEWORK AVFoundation REQUIRED)
find_library(AUDIO_FRAMEWORK AudioToolbox REQUIRED)
find_library(GAMECONTROLLER_FRAMEWORK GameController REQUIRED)

target_link_libraries(DMC4iOS PRIVATE
    ${FOUNDATION_FRAMEWORK}
    ${COREGRAPHICS_FRAMEWORK}
    ${UIKIT_FRAMEWORK}
    ${METAL_FRAMEWORK}
    ${METALL_FRAMEWORK}
    ${QUARTZ_FRAMEWORK}
    ${AVFOUNDATION_FRAMEWORK}
    ${AUDIO_FRAMEWORK}
    ${GAMECONTROLLER_FRAMEWORK}
    "-lobjc"
    "-lz"
)

target_link_options(DMC4iOS PRIVATE
    "-fobjc-arc"
)

# Automatic IPA packaging target
if(DMC4_BUILD_IPA)
    add_custom_command(TARGET DMC4iOS POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E make_directory $<TARGET_FILE_DIR:DMC4iOS>/Payload
        COMMAND ${CMAKE_COMMAND} -E copy_directory $<TARGET_BUNDLE_DIR:DMC4iOS> $<TARGET_FILE_DIR:DMC4iOS>/Payload/DevilMayCry4.app
        COMMAND ${CMAKE_COMMAND} -E chdir $<TARGET_FILE_DIR:DMC4iOS> zip -r -y -q DevilMayCry4.ipa Payload
        COMMAND ${CMAKE_COMMAND} -E remove_directory $<TARGET_FILE_DIR:DMC4iOS>/Payload
        COMMENT "Packaging Devil May Cry 4 iOS IPA..."
    )
endif()
