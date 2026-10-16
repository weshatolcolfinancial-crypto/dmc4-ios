cmake_minimum_required(VERSION 3.25)
project(DMC4iOS LANGUAGES C CXX OBJC OBJCXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD 11)

if(NOT IOS)
    message(STATUS "Configuring for iOS target...")
    set(IOS TRUE)
endif()

# Build Options
option(DMC4_ENABLE_PROMOTION "Enable ProMotion 120Hz display refresh support" ON)
option(DMC4_ENABLE_TOUCH "Enable custom DMC combat touch controls" ON)
option(DMC4_ENABLE_MOLTENVK "Use MoltenVK Vulkan-to-Metal translation layer" ON)
option(DMC4_BUILD_IPA "Automatically package .ipa payload on build" ON)

if(DMC4_ENABLE_PROMOTION)
    add_compile_definitions(DMC4_PROMOTION_ENABLED=1)
endif()

if(DMC4_ENABLE_TOUCH)
    add_compile_definitions(DMC4_TOUCH_ENABLED=1)
endif()

# Set up include directories
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/renderer
    ${CMAKE_CURRENT_SOURCE_DIR}/ios/src
)

# Compiler flags for Apple Silicon ARM64 iOS
set(CMAKE_XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH NO)
set(CMAKE_XCODE_ATTRIBUTE_ENABLE_BITCODE NO)
set(CMAKE_XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET "16.0")

add_compile_options(
    -Wall
    -Wextra
    -Wno-unused-parameter
    -Wno-unused-variable
    -fvisibility=hidden
    -ffast-math
)

# Add subdirectories
add_subdirectory(ios)
