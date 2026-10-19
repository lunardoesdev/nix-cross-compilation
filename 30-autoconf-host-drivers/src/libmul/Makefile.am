lib_LTLIBRARIES = libmul.la
libmul_la_SOURCES = mul.c
libmul_la_CFLAGS = $(LIBADD_CFLAGS)
libmul_la_LIBADD = $(LIBADD_LIBS)
libmul_la_LDFLAGS = -version-info 1:0:0

include_HEADERS = mul.h

# Advertise the transitive dependency so consumers of libmul get libadd too.
pkgconfigdir = $(libdir)/pkgconfig
pkgconfig_DATA = libmul.pc
