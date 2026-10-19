cmake_minimum_required(VERSION 3.20)
project(libadd VERSION 1.0.0 LANGUAGES C)

add_library(add add.c)
set_target_properties(add PROPERTIES
  VERSION ${PROJECT_VERSION}
  SOVERSION ${PROJECT_VERSION_MAJOR}
  PUBLIC_HEADER add.h)

include(GNUInstallDirs)
install(TARGETS add
  LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
  ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
  PUBLIC_HEADER DESTINATION ${CMAKE_INSTALL_INCLUDEDIR})

# A pkg-config file, so consumers find libadd by name (no -I/-L/-l anywhere).
configure_file(libadd.pc.in ${CMAKE_CURRENT_BINARY_DIR}/libadd.pc @ONLY)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/libadd.pc
  DESTINATION ${CMAKE_INSTALL_LIBDIR}/pkgconfig)
