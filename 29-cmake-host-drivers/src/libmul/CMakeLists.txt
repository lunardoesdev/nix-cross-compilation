cmake_minimum_required(VERSION 3.20)
project(libmul VERSION 1.0.0 LANGUAGES C)

# libadd is found through pkg-config.  In a Nix build `buildInputs = [ libadd ]`
# puts libadd's lib/pkgconfig on PKG_CONFIG_PATH, so no path is written here.
find_package(PkgConfig REQUIRED)
pkg_check_modules(LIBADD REQUIRED IMPORTED_TARGET libadd)

add_library(mul mul.c)
target_link_libraries(mul PUBLIC PkgConfig::LIBADD)
set_target_properties(mul PROPERTIES
  VERSION ${PROJECT_VERSION}
  SOVERSION ${PROJECT_VERSION_MAJOR}
  PUBLIC_HEADER mul.h)

include(GNUInstallDirs)
install(TARGETS mul
  LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
  ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
  PUBLIC_HEADER DESTINATION ${CMAKE_INSTALL_INCLUDEDIR})

# Advertise the transitive dependency so consumers of libmul get libadd too.
configure_file(libmul.pc.in ${CMAKE_CURRENT_BINARY_DIR}/libmul.pc @ONLY)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/libmul.pc
  DESTINATION ${CMAKE_INSTALL_LIBDIR}/pkgconfig)
