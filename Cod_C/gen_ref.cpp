#define _CRT_SECURE_NO_WARNINGS

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include "conv2d.h"


/* scrie imaginea in fisier text: un pixel pe linie, 2 cifre hex. */
static int write_hex(const char* path, const uint8_t* im, int n)
{
    FILE* f = fopen(path, "w");
    if (!f) {
        printf("nu pot deschide %s\n", path);
        return -1;
    }
    for (int i = 0; i < n; i++) {
        fprintf(f, "%02X\n", im[i]);
    }
    fclose(f);
    return 0;
}

/* genereaza imaginea de intrare, calculeaza convolutia si scrie
   fisierele in_*.hex si out_*.hex in folderul dir. */
static int make_case(const char* dir, int size, int mode, FILE* sums)
{
    int n = size * size;
    uint8_t* in = (uint8_t*)malloc(n);
    uint8_t* out = (uint8_t*)malloc(n);
    if (!in || !out) return -1;

    make_image(in, size, size, mode);
    conv_image(in, out, size, size);

    const char* name = (mode == 0) ? "grad" : "rand";
    char p[256];
    snprintf(p, sizeof p, "%s/in_%dx%d_%s.hex", dir, size, size, name);
    write_hex(p, in, n);
    snprintf(p, sizeof p, "%s/out_%dx%d_%s.hex", dir, size, size, name);
    write_hex(p, out, n);

    printf("%4dx%-4d %-4s in=%08x out=%08x\n", size, size, name,
           checksum(in, n), checksum(out, n));
    fprintf(sums, "%dx%d %s in=%08x out=%08x\n", size, size, name,
            checksum(in, n), checksum(out, n));
    free(in);
    free(out);
    return 0;
}

int main(int argc, char** argv)
{
    const char* dir = (argc > 1) ? argv[1] : ".";
    char p[256];
    snprintf(p, sizeof p, "%s/checksums.txt", dir);
    FILE* sums = fopen(p, "w");
    if (!sums) return 1;

    make_case(dir, 8, 0, sums);
    make_case(dir, 8, 1, sums);
    make_case(dir, 16, 0, sums);
    make_case(dir, 16, 1, sums);
    make_case(dir, 128, 1, sums);
    make_case(dir, 256, 1, sums);
    make_case(dir, 512, 1, sums);

    fclose(sums);
    return 0;
}
