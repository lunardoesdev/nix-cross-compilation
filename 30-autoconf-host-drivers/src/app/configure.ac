AC_INIT([sdl3-triangle], [1.0.0], [], [sdl3-triangle])
AC_CONFIG_SRCDIR([main.cpp])
AC_CONFIG_AUX_DIR([build-aux])
AM_INIT_AUTOMAKE([foreign subdir-objects])

AC_PROG_CXX
AC_PROG_INSTALL
AC_LANG([C++])

# Every dependency is discovered by name; PKG_CHECK_MODULES supplies the flags.
PKG_CHECK_MODULES([SDL3],  [sdl3])
PKG_CHECK_MODULES([EPOXY], [epoxy])
PKG_CHECK_MODULES([LIBMUL], [libmul])   # pulls libadd in transitively

AC_CONFIG_FILES([Makefile])
AC_OUTPUT
