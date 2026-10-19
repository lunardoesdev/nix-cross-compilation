cmake_minimum_required(VERSION 3.20)
project(sdl3-triangle VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# SDL3 ships a CMake package config, so use find_package for it...
find_package(SDL3 REQUIRED)              # -> SDL3::SDL3

# ...and pkg-config for our own libraries and for libepoxy.
find_package(PkgConfig REQUIRED)
pkg_check_modules(LIBMUL REQUIRED IMPORTED_TARGET libmul)   # pulls libadd in
pkg_check_modules(EPOXY REQUIRED IMPORTED_TARGET epoxy)

add_executable(sdl3-triangle main.cpp)
target_link_libraries(sdl3-triangle PRIVATE
  SDL3::SDL3
  PkgConfig::LIBMUL
  PkgConfig::EPOXY)

install(TARGETS sdl3-triangle RUNTIME DESTINATION bin)
