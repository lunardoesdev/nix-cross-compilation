project('sdl3-triangle', 'cpp',
  version : '1.0.0',
  default_options : ['warning_level=2', 'cpp_std=c++17'])

# Every dependency is discovered by name; Meson (via pkg-config, and via the Nix
# build inputs) supplies the include paths and libraries.  Nothing is hard-coded.
sdl3  = dependency('sdl3')
epoxy = dependency('epoxy')
libmul = dependency('libmul')   # pulls in libadd transitively

executable('sdl3-triangle', 'main.cpp',
  dependencies : [sdl3, epoxy, libmul],
  install : true)
