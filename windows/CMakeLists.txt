# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "clipboard_monitor")
project(${PROJECT_NAME} LANGUAGES CXX)

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# This value is used when generating builds using this plugin, so it must
# not be changed.
set(PLUGIN_NAME "clipboard_monitor_plugin")

add_library(${PLUGIN_NAME} SHARED
  "clipboard_monitor_plugin.cpp"
  "clipboard_monitor_plugin.h"
  "clipboard_monitor_plugin_c_api.cpp"
  "include/clipboard_monitor/clipboard_monitor_plugin_c_api.h"
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin user32 kernel32)

# List of absolute paths to libraries that should be bundled with the plugin.
set(clipboard_monitor_bundled_libraries
  ""
  PARENT_SCOPE
)
