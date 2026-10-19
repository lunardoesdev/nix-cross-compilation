/*
 * sdl3-game - a deliberately tiny SDL3 game loop.
 *
 * It opens a 640x480 window, renders a colour that shifts every frame, and
 * exits after `--frames N` frames (default 120).  The score uses libmul (which
 * uses libadd), so the binary exercises both demo libraries.
 *
 * On Emscripten the frame callback is driven by the browser instead of a
 * blocking loop.
 */
#include <SDL3/SDL.h>

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#endif

#include "mul.h"

typedef struct {
    SDL_Window   *window;
    SDL_Renderer *renderer;
    int           frame;
    int           frames;
} App;

static void draw_frame(void *userdata)
{
    App *app = userdata;
    SDL_Event event;

    while (SDL_PollEvent(&event)) {
        if (event.type == SDL_EVENT_QUIT)
            app->frame = app->frames;
    }

    SDL_SetRenderDrawColor(app->renderer,
                           (Uint8)((app->frame * 4) % 256), 64, 160, 255);
    SDL_RenderClear(app->renderer);
    SDL_RenderPresent(app->renderer);

    app->frame++;

#ifdef __EMSCRIPTEN__
    if (app->frame >= app->frames)
        emscripten_cancel_main_loop();
#endif
}

static int parse_frames(int argc, char **argv)
{
    int i;
    int frames = 120;

    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--frames") == 0 && i + 1 < argc)
            frames = atoi(argv[++i]);
    }

    return frames;
}

/* SDL logs an error if XDG_RUNTIME_DIR is unset (a clean/bare environment does
 * not set it).  Provide a private fallback before SDL_Init. */
static void ensure_xdg_runtime_dir(void)
{
    char dir[4096];
    const char *tmp;

    if (getenv("XDG_RUNTIME_DIR") != NULL)
        return;

    tmp = getenv("TMPDIR");
    if (tmp == NULL || *tmp == '\0')
        tmp = "/tmp";

    snprintf(dir, sizeof(dir), "%s/sdl3-runtime-%u", tmp, (unsigned)getuid());
    if (mkdir(dir, 0700) != 0 && errno != EEXIST)
        return; /* leave it unset; SDL will only warn */
    setenv("XDG_RUNTIME_DIR", dir, 1);
}

int main(int argc, char **argv)
{
    App app;
    int frames = parse_frames(argc, argv);

    ensure_xdg_runtime_dir();

    if (!SDL_Init(SDL_INIT_VIDEO)) {
        fprintf(stderr, "sdl3-game: SDL_Init failed: %s\n", SDL_GetError());
        return 1;
    }

    app.window = SDL_CreateWindow("Nix cross-compilation demo", 640, 480, 0);
    if (app.window == NULL) {
        fprintf(stderr, "sdl3-game: SDL_CreateWindow failed: %s\n",
                SDL_GetError());
        SDL_Quit();
        return 1;
    }

    app.renderer = SDL_CreateRenderer(app.window, NULL);
    if (app.renderer == NULL) {
        fprintf(stderr, "sdl3-game: SDL_CreateRenderer failed: %s\n",
                SDL_GetError());
        SDL_DestroyWindow(app.window);
        SDL_Quit();
        return 1;
    }

    app.frame = 0;
    app.frames = frames;

    printf("sdl3-game: video driver = %s\n", SDL_GetCurrentVideoDriver());
    printf("sdl3-game: score = mul(3, 14) = %d\n", mul(3, 14));

#ifdef __EMSCRIPTEN__
    emscripten_set_main_loop_arg(draw_frame, &app, 0, 1);
#else
    while (app.frame < app.frames) {
        draw_frame(&app);
        SDL_Delay(16);
    }
    printf("sdl3-game: rendered %d frame(s)\n", app.frame);
#endif

    SDL_DestroyRenderer(app.renderer);
    SDL_DestroyWindow(app.window);
    SDL_Quit();

    return 0;
}
