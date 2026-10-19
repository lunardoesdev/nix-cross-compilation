/*
 * A minimal Android NativeActivity.
 *
 * It is a normal shared library (`libmain.so`) exporting ANativeActivity_onCreate.
 * The manifest points NativeActivity at lib "main"; the framework calls our
 * onCreate, we set an onStart callback, log the score computed by libmul (which
 * uses libadd), and finish.
 *
 * The point of the chapter is the *packaging* (APK, signing, AAB), not the UI.
 */
#include <android/native_activity.h>
#include <android/log.h>

#include <stddef.h>

#include "add.h"
#include "mul.h"

#define LOG_TAG "cdemo"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

static void on_start(ANativeActivity *activity)
{
    int score = mul(6, 7);
    LOGI("cdemo: add(6, 7) = %d", add(6, 7));
    LOGI("cdemo: mul(6, 7) = %d", score);

    /* Nothing to draw: show the activity briefly, then close it. */
    ANativeActivity_finish(activity);
}

void ANativeActivity_onCreate(ANativeActivity *activity,
                              void *saved_state, size_t saved_state_size)
{
    (void)saved_state;
    (void)saved_state_size;

    LOGI("cdemo: NativeActivity created");

    /* The callbacks struct is allocated by the framework; we only fill it in. */
    activity->callbacks->onStart = on_start;
}
