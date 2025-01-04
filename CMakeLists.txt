cmake_minimum_required(VERSION 3.12)

# Project name
project(EGPreviewActivator)

# Set C++ standard to C++17
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Specify the source file
set(SOURCE_FILES
    EGPreviewActivator.mm
)

# Find the necessary frameworks
find_library(APPKIT_FRAMEWORK AppKit)
find_library(IOKIT_FRAMEWORK IOKit)

# Specify additional include directories
include_directories(
    ${PROJECT_SOURCE_DIR}/capture-device-support/Library
)

# Add the executable target
add_executable(EGPreviewActivator ${SOURCE_FILES})

# Link the necessary frameworks and libraries
target_link_libraries(EGPreviewActivator
    ${APPKIT_FRAMEWORK}
    ${IOKIT_FRAMEWORK}
    ${PROJECT_SOURCE_DIR}/capture-device-support/libEGAVHIDLib.a
)

# Add the path to the external library
link_directories(${PROJECT_SOURCE_DIR}/capture-device-support)

