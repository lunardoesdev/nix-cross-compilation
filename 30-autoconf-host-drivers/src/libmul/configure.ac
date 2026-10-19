AC_INIT([libmul], [1.0.0], [], [libmul])
AC_CONFIG_SRCDIR([mul.c])
AC_CONFIG_AUX_DIR([build-aux])
AM_INIT_AUTOMAKE([foreign subdir-objects])

LT_INIT
AC_PROG_CC
AC_PROG_INSTALL

# libadd is discovered through pkg-config.  In a Nix build
# `buildInputs = [ libadd ]` puts its lib/pkgconfig on PKG_CONFIG_PATH, so this
# macro is all that is needed.
PKG_CHECK_MODULES([LIBADD], [libadd])

AC_CONFIG_FILES([Makefile libmul.pc])
AC_OUTPUT
