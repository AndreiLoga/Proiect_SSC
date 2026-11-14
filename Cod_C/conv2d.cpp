#include "conv2d.h"

/* Nucleul Gaussian 3x3 (suma = 16) */
static const int8_t kern[3][3] = {
    { 1, 2, 1 },
    { 2, 4, 2 },
    { 1, 2, 1 }
};

/* Imaginea este un vector de w*h octeti, rand dupa rand.
   Pixelul de la (r, c) se afla la indexul r * w + c. */

void make_image(uint8_t* im, int w, int h, int mode)
{
    uint32_t s = 12345;
    for (int r = 0; r < h; r++) {
        for (int c = 0; c < w; c++) {
            if (mode == 0) {
                im[r * w + c] = (uint8_t)(4 * (r * w + c));
            }
            else {
                s = s * 1103515245u + 12345u;
                im[r * w + c] = (uint8_t)(s >> 16);
            }
        }
    }
}

uint8_t saturate(int v)
{
    if (v < 0) return 0;
    if (v > 255) return 255;
    return (uint8_t)v;
}

int get_pixel(const uint8_t* im, int w, int h, int r, int c)
{
    if (r < 0 || r >= h || c < 0 || c >= w) {
        return 0;
    }
    return im[r * w + c];
}

int conv_pixel(const uint8_t* im, int w, int h, int r, int c)
{
    int acc = 0;
    for (int m = 0; m < 3; m++) {
        for (int n = 0; n < 3; n++) {
            acc += kern[m][n] * get_pixel(im, w, h, r + m - 1, c + n - 1);
        }
    }
    return acc >> 4;
}

void conv_image(const uint8_t* in, uint8_t* out, int w, int h)
{
    for (int r = 0; r < h; r++) {
        for (int c = 0; c < w; c++) {
            out[r * w + c] = saturate(conv_pixel(in, w, h, r, c));
        }
    }
}

uint32_t checksum(const uint8_t* im, int n)
{
    uint32_t hsh = 2166136261u;
    for (int i = 0; i < n; i++) {
        hsh ^= im[i];
        hsh *= 16777619u;
    }
    return hsh;
}
