project('uselib2', 'c',
  version : '1.0.0',
  default_options : ['warning_level=2', 'c_std=c11'])

# libmul (and, transitively, libadd) are found by name; no flags are written.
libmul = dependency('libmul')

executable('uselib2', 'main.c', dependencies : [libmul], install : true)
