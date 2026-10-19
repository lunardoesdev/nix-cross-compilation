/*
 * A small program that uses libpng (which itself uses zlib) to encode and then
 * decode a 2x2 image entirely in memory.  Nothing is read from disk.
 *
 * The point is the dependency chain: buildInputs = [ libpng ] must supply
 * libpng *and* its zlib dependency for every target we build for.
 */
#include <png.h>
#include <zlib.h>

#include <stdio.h>
#include <string.h>

int main(void)
{
    png_image image;
    unsigned char pixels[2 * 2 * 3] = {
        255, 0, 0,   0, 255, 0,
        0, 0, 255,   255, 255, 0,
    };
    unsigned char pngbuf[4096];
    png_image out;

    memset(&image, 0, sizeof(image));
    image.version = PNG_IMAGE_VERSION;
    image.width = 2;
    image.height = 2;
    image.format = PNG_FORMAT_RGB;

    size_t size = sizeof(pngbuf);
    if (!png_image_write_to_memory(&image, pngbuf, &size, 0, pixels, 0, NULL)) {
        fprintf(stderr, "png write failed: %s\n", image.message);
        return 1;
    }

    memset(&out, 0, sizeof(out));
    out.version = PNG_IMAGE_VERSION;
    if (!png_image_begin_read_from_memory(&out, pngbuf, size)) {
        fprintf(stderr, "png read failed: %s\n", out.message);
        return 1;
    }

    printf("png-demo: libpng %s / zlib %s\n",
           png_get_libpng_ver(NULL), zlibVersion());
    printf("png-demo: round-trip %ux%u ok (%zu bytes)\n",
           out.width, out.height, size);

    png_image_free(&out);
    return 0;
}
