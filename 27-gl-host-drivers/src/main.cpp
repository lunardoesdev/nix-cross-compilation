/*
 * A tiny C++ SDL3 + OpenGL 3.3 (core profile) program.
 *
 * It opens a window, draws one RGB triangle, keeps it on screen for a few
 * seconds (default 3), then exits.  The point of the chapter is the *packaging*
 * (a portable sharun + uruntime bundle that also runs on musl systems), so the
 * graphics code is deliberately minimal.
 *
 * GL functions are loaded with libepoxy, so there is no hand-written
 * glGetProcAddress boilerplate and the code is portable across GL loaders.
 */
#include <SDL3/SDL.h>

#include <epoxy/gl.h>

#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

namespace {

constexpr const char *kVertSrc = R"glsl(
#version 330 core
layout(location = 0) in vec2 a_pos;
layout(location = 1) in vec3 a_color;
out vec3 v_color;
void main() {
    v_color = a_color;
    gl_Position = vec4(a_pos, 0.0, 1.0);
}
)glsl";

constexpr const char *kFragSrc = R"glsl(
#version 330 core
in vec3 v_color;
out vec4 f_color;
void main() {
    f_color = vec4(v_color, 1.0);
}
)glsl";

// Three vertices: x, y, r, g, b
constexpr float kTriangle[] = {
    // x      y      r    g    b
     0.0f,  0.6f,  1.0f, 0.2f, 0.2f,   // top     (red)
    -0.6f, -0.5f,  0.2f, 1.0f, 0.2f,   // left    (green)
     0.6f, -0.5f,  0.2f, 0.2f, 1.0f,   // right   (blue)
};

GLuint compile_shader(GLenum type, const char *src)
{
    GLuint shader = glCreateShader(type);
    glShaderSource(shader, 1, &src, nullptr);
    glCompileShader(shader);

    GLint ok = GL_FALSE;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (ok != GL_TRUE) {
        char log[1024] = {0};
        glGetShaderInfoLog(shader, sizeof(log) - 1, nullptr, log);
        std::fprintf(stderr, "shader compile failed: %s\n", log);
        std::exit(1);
    }
    return shader;
}

GLuint link_program()
{
    GLuint vs = compile_shader(GL_VERTEX_SHADER, kVertSrc);
    GLuint fs = compile_shader(GL_FRAGMENT_SHADER, kFragSrc);

    GLuint prog = glCreateProgram();
    glAttachShader(prog, vs);
    glAttachShader(prog, fs);
    glLinkProgram(prog);

    GLint ok = GL_FALSE;
    glGetProgramiv(prog, GL_LINK_STATUS, &ok);
    if (ok != GL_TRUE) {
        char log[1024] = {0};
        glGetProgramInfoLog(prog, sizeof(log) - 1, nullptr, log);
        std::fprintf(stderr, "program link failed: %s\n", log);
        std::exit(1);
    }

    glDeleteShader(vs);
    glDeleteShader(fs);
    return prog;
}

int parse_seconds(int argc, char **argv)
{
    int seconds = 3;
    for (int i = 1; i < argc; i++) {
        if (std::strcmp(argv[i], "--seconds") == 0 && i + 1 < argc)
            seconds = std::atoi(argv[++i]);
    }
    return seconds;
}

// SDL logs an error if XDG_RUNTIME_DIR is unset.  A normal desktop session sets
// it, but a bare/clean environment (a bundle run under `env -i`, a service, a
// container) does not, so provide a private fallback before SDL_Init.
void ensure_xdg_runtime_dir()
{
    if (std::getenv("XDG_RUNTIME_DIR") != nullptr)
        return;

    const char *tmp = std::getenv("TMPDIR");
    if (tmp == nullptr || *tmp == '\0')
        tmp = "/tmp";

    char dir[4096];
    std::snprintf(dir, sizeof(dir), "%s/sdl3-runtime-%u", tmp, (unsigned)::getuid());

    if (::mkdir(dir, 0700) != 0 && errno != EEXIST)
        return; // leave it unset; SDL will only warn

    ::setenv("XDG_RUNTIME_DIR", dir, 1);
}

} // namespace

int main(int argc, char **argv)
{
    const int seconds = parse_seconds(argc, argv);

    ensure_xdg_runtime_dir();

    // Ask for an OpenGL 3.3 core-profile context.
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);
    SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
    SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 24);

    if (!SDL_Init(SDL_INIT_VIDEO)) {
        std::fprintf(stderr, "SDL_Init failed: %s\n", SDL_GetError());
        return 1;
    }

    SDL_Window *window = SDL_CreateWindow(
        "SDL3 + OpenGL triangle", 800, 600, SDL_WINDOW_OPENGL | SDL_WINDOW_RESIZABLE);
    if (window == nullptr) {
        std::fprintf(stderr, "SDL_CreateWindow failed: %s\n", SDL_GetError());
        SDL_Quit();
        return 1;
    }

    SDL_GLContext ctx = SDL_GL_CreateContext(window);
    if (ctx == nullptr) {
        std::fprintf(stderr, "SDL_GL_CreateContext failed: %s\n", SDL_GetError());
        SDL_DestroyWindow(window);
        SDL_Quit();
        return 1;
    }

    std::printf("OpenGL %s | %s\n", glGetString(GL_VERSION), glGetString(GL_RENDERER));

    GLuint prog = link_program();

    GLuint vao = 0, vbo = 0;
    glGenVertexArrays(1, &vao);
    glBindVertexArray(vao);

    glGenBuffers(1, &vbo);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof(kTriangle), kTriangle, GL_STATIC_DRAW);

    const GLsizei stride = 5 * sizeof(float);
    glEnableVertexAttribArray(0); // position
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, stride, (void *)0);
    glEnableVertexAttribArray(1); // colour
    glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, stride, (void *)(2 * sizeof(float)));

    const Uint64 start = SDL_GetTicks();
    const Uint64 duration_ms = (Uint64)seconds * 1000;

    int frames = 0;
    bool running = true;
    while (running) {
        SDL_Event event;
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_EVENT_QUIT)
                running = false;
            if (event.type == SDL_EVENT_KEY_DOWN &&
                event.key.key == SDLK_ESCAPE)
                running = false;
        }

        int w = 0, h = 0;
        SDL_GetWindowSizeInPixels(window, &w, &h);
        glViewport(0, 0, w, h);

        glClearColor(0.05f, 0.06f, 0.09f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        glUseProgram(prog);
        glBindVertexArray(vao);
        glDrawArrays(GL_TRIANGLES, 0, 3);

        SDL_GL_SwapWindow(window);
        frames++;

        if (SDL_GetTicks() - start >= duration_ms)
            running = false;
    }

    std::printf("rendered %d frame(s) in ~%d second(s)\n", frames, seconds);

    glDeleteBuffers(1, &vbo);
    glDeleteVertexArrays(1, &vao);
    glDeleteProgram(prog);
    SDL_GL_DestroyContext(ctx);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 0;
}
