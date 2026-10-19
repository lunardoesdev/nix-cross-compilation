project('libmul', 'c',
  version : '1.0.0',
  default_options : ['warning_level=2', 'c_std=c11'])

# libadd is found through pkg-config.  In a Nix build, `buildInputs = [ libadd ]`
# makes libadd's lib/pkgconfig appear on PKG_CONFIG_PATH automatically, so this
# line is all that is needed -- no -I, no -L, no -ladd.
libadd_dep = dependency('libadd')

libmul = library('mul', 'mul.c',
  dependencies : libadd_dep,
  version : meson.project_version(),
  install : true)

install_headers('mul.h')

# Advertise libadd as a requirement, so anything that links libmul also gets
# libadd's flags and libraries -- ordinary transitive dependency management.
pkg = import('pkgconfig')
pkg.generate(libmul,
  name : 'libmul',
  description : 'mul() demo library',
  version : meson.project_version(),
  requires : libadd_dep)
