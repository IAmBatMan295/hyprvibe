cmake_minimum_required(VERSION 3.20)
project(hyprvibe_launcher LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml DBus)
find_package(PkgConfig REQUIRED)
pkg_check_modules(PULSE REQUIRED IMPORTED_TARGET libpulse)

qt_add_library(hyprvibelauncher SHARED
  LauncherModel.hpp
  LauncherModel.cpp
  PulseEngine.hpp
  PulseEngine.cpp
  DBusEngine.hpp
  DBusEngine.cpp
  SystemCore.hpp
  SystemCore.cpp
  Plugin.cpp
)

set_target_properties(hyprvibelauncher PROPERTIES
  PREFIX "lib"
  OUTPUT_NAME "hyprvibelauncher"
  LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../HyprVibeLauncher"
)

target_link_libraries(hyprvibelauncher PRIVATE
  Qt6::Core
  Qt6::Gui
  Qt6::Qml
  Qt6::DBus
  PkgConfig::PULSE
)

add_executable(hyprvibe-dmenu hyprvibe-dmenu.cpp)

add_executable(hyprvibe-core-tests
  CoreTests.cpp
  LauncherModel.hpp
  LauncherModel.cpp
  PulseEngine.hpp
  PulseEngine.cpp
  DBusEngine.hpp
  DBusEngine.cpp
  SystemCore.hpp
  SystemCore.cpp
)
target_link_libraries(hyprvibe-core-tests PRIVATE
  Qt6::Core
  Qt6::Gui
  Qt6::Qml
  Qt6::DBus
  PkgConfig::PULSE
)
