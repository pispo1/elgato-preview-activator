cmake_minimum_required(VERSION 3.12)

# Project name
project(EGPreviewActivator)

# Set C++ standard to C++17
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find the necessary frameworks
find_library(APPKIT_FRAMEWORK AppKit)
find_library(COCOA_FRAMEWORK Cocoa)
find_library(IOKIT_FRAMEWORK IOKit)
find_library(COREMEDIA_FRAMEWORK CoreMedia)
find_library(AVFOUNDATION_FRAMEWORK AVFoundation)
find_library(COREVIDEO_FRAMEWORK CoreVideo)

# Specify additional include directories
include_directories(
    ${PROJECT_SOURCE_DIR}/capture-device-support/Library
)

# Add the first executable target (EGPreviewActivator)
set(SOURCE_FILES_EG
    EGPreviewActivator.mm
)

add_executable(EGPreviewActivator ${SOURCE_FILES_EG})

# Link the necessary frameworks and libraries for EGPreviewActivator
target_link_libraries(EGPreviewActivator
    ${APPKIT_FRAMEWORK}
    ${IOKIT_FRAMEWORK}
    ${PROJECT_SOURCE_DIR}/capture-device-support/libEGAVHIDLib.a
)

# Add the second executable target (AVICapture)
set(SOURCE_FILES_AVI
    AVICapture.mm
)

add_executable(AVICapture ${SOURCE_FILES_AVI})

# Link the necessary frameworks and libraries for AVICapture
target_link_libraries(AVICapture
    ${APPKIT_FRAMEWORK}
    ${IOKIT_FRAMEWORK}
    ${COCOA_FRAMEWORK}
    ${COREMEDIA_FRAMEWORK}
    ${COREVIDEO_FRAMEWORK}
    ${AVFOUNDATION_FRAMEWORK}
)

# Add the path to the external library
link_directories(${PROJECT_SOURCE_DIR}/capture-device-support)
