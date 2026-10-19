project('libadd', 'c',
  version : '1.0.0',
  default_options : ['warning_level=2', 'c_std=c11'])

# A normal shared library.  Meson installs it as libadd.so.<version> with the
# usual SONAME symlinks, and `pkg.generate` writes libadd.pc -- which is what
# consumers use to find it.  No compiler flags are written by hand anywhere.
libadd = library('add', 'add.c',
  version : meson.project_version(),
  install : true)

install_headers('add.h')

pkg = import('pkgconfig')
pkg.generate(libadd,
  name : 'libadd',
  description : 'add() demo library',
  version : meson.project_version())
