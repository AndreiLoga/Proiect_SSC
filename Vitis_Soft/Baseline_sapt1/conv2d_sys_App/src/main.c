/*
 * Baseline software: convolutie 2D (Gaussian 3x3, zero padding) pe ARM,
 * bare-metal, Zybo Z7-20.
 *
 * Pentru fiecare imagine de test:
 *   1. genereaza imaginea cu make_image (acelasi LCG ca pe PC),
 *   2. ruleaza conv_image de "reps" ori si masoara timpul cu timerul
 *      global al ARM (XTime_GetTime),
 *   3. compara amprentele FNV-1a (intrare si iesire) cu cele de pe PC
 *      (Cod_C/ref/checksums.txt) si scrie PASS sau FAIL.
 *
 * Rezultatele se vad prin UART (115200 baud).
 */

#include <stdio.h>
#include <stdint.h>
#include "platform.h"
#include "xil_printf.h"
#include "xiltimer.h"   /* COUNTS_PER_SECOND (BSP cu xiltimer) */
#include "xil_io.h"
#include "xparameters.h"
#include "conv2d.h"

#define MAX_N (512 * 512)

/* Timerul global al Cortex-A9 (numarator crescator pe 64 de biti, la
   frecventa CPU/2). Il citim direct, pentru ca XTime_GetTime din xiltimer
   citeste timerul privat SCU, care e descrescator si ramane pe 0 daca nu
   a rulat inainte un usleep (de aceea primele masuratori dadeau 0). */
#define GTC_BASE      XPAR_PS7_GLOBALTIMER_0_BASEADDR
#define GTC_COUNT_LO  (GTC_BASE + 0x00u)
#define GTC_COUNT_HI  (GTC_BASE + 0x04u)
#define GTC_CTRL      (GTC_BASE + 0x08u)

static void gtc_start(void)
{
    Xil_Out32(GTC_CTRL, Xil_In32(GTC_CTRL) | 1u);   /* bit 0 = timer enable */
}

static uint64_t gtc_now(void)
{
    uint32_t hi, lo, hi2;
    do {   /* citire sigura: reia daca partea superioara se schimba */
        hi  = Xil_In32(GTC_COUNT_HI);
        lo  = Xil_In32(GTC_COUNT_LO);
        hi2 = Xil_In32(GTC_COUNT_HI);
    } while (hi != hi2);
    return ((uint64_t)hi << 32) | lo;
}

static uint8_t in_buf[MAX_N];
static uint8_t out_buf[MAX_N];

typedef struct {
    int size;           /* latura imaginii (imagine patrata) */
    int mode;           /* 0 = gradient, 1 = pseudo-aleator */
    int reps;           /* de cate ori se repeta convolutia pentru medie */
    uint32_t exp_in;    /* amprenta asteptata a intrarii (de pe PC) */
    uint32_t exp_out;   /* amprenta asteptata a iesirii (de pe PC) */
} test_case;

/* amprentele sunt cele din docs/PROGRESS.md (verificate cu gcc si MSVC) */
static const test_case cases[] = {
    {   8, 0, 1000, 0xeaa1ffc5u, 0x585b0b81u },
    {   8, 1, 1000, 0xac219a97u, 0xc8eef4f8u },
    {  16, 0, 1000, 0xbe5e25c5u, 0xf14dbccdu },
    {  16, 1, 1000, 0x564bfd47u, 0x047678fau },
    { 128, 1,   20, 0xf446ee5eu, 0x9607334au },
    { 256, 1,   10, 0x69a207b5u, 0xa9986e0bu },
    { 512, 1,    5, 0xc4a9261du, 0x26681436u }
};

#define N_CASES ((int)(sizeof(cases) / sizeof(cases[0])))

int main()
{
    int i, k;
    int passed = 0;
    /* COUNTS_PER_SECOND e definit fara paranteze in BSP (FREQ/2), deci il
       copiem intr-o variabila ca sa nu se strice ordinea operatiilor */
    const uint64_t counts_per_sec = (uint64_t)(COUNTS_PER_SECOND);

    init_platform();
    gtc_start();

    printf("\r\n=== Baseline ARM: convolutie 2D Gaussian 3x3 ===\r\n");
    printf("Timer global: %u Hz\r\n", (unsigned)counts_per_sec);
    printf("size       mode reps  us/imagine  ns/pixel  amprente (in / out)       status\r\n");

    for (i = 0; i < N_CASES; i++) {
        const test_case* t = &cases[i];
        int n = t->size * t->size;
        uint64_t t0, t1, ticks;
        uint32_t us_per_img, ns_per_pix, chk_in, chk_out;
        int ok;

        make_image(in_buf, t->size, t->size, t->mode);
        chk_in = checksum(in_buf, n);

        /* o rulare de incalzire (cache), netinuta in calcul */
        conv_image(in_buf, out_buf, t->size, t->size);

        t0 = gtc_now();
        for (k = 0; k < t->reps; k++) {
            conv_image(in_buf, out_buf, t->size, t->size);
        }
        t1 = gtc_now();

        chk_out = checksum(out_buf, n);

        /* un tic dureaza ~3 ns; ticks * 1e9 incape pe 64 de biti pana la ~55 s */
        ticks = t1 - t0;
        us_per_img = (uint32_t)(ticks * 1000000ull / counts_per_sec / (uint64_t)t->reps);
        ns_per_pix = (uint32_t)(ticks * 1000000000ull / counts_per_sec
                                / ((uint64_t)t->reps * (uint64_t)n));

        ok = (chk_in == t->exp_in) && (chk_out == t->exp_out);
        if (ok) passed++;

        printf("%4dx%-4d  %-4s %4d  %10u  %8u  %08x / %08x  %s\r\n",
               t->size, t->size, (t->mode == 0) ? "grad" : "rand",
               t->reps, (unsigned)us_per_img, (unsigned)ns_per_pix,
               (unsigned)chk_in, (unsigned)chk_out, ok ? "PASS" : "FAIL");
    }

    printf("Rezultat: %d / %d PASS\r\n", passed, N_CASES);

    cleanup_platform();
    return 0;
}
