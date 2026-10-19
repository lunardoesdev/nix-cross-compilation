lib_LTLIBRARIES = libadd.la
libadd_la_SOURCES = add.c
libadd_la_LDFLAGS = -version-info 1:0:0

include_HEADERS = add.h

# Install a pkg-config file so consumers find libadd by name.
pkgconfigdir = $(libdir)/pkgconfig
pkgconfig_DATA = libadd.pc
