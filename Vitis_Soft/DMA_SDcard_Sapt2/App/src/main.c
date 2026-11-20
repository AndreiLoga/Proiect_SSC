/* P1 - Accelerator de convolutie 2D pe FPGA (Zybo Z7-20).
 *
 * Aplicatie standalone pentru procesorul ARM. Pune o imagine in DDR,
 * o trimite prin AXI DMA catre acceleratorul top_conv2d (Gaussian 3x3),
 * primeste rezultatul inapoi in DDR si il compara cu convolutia software
 * de pe ARM (aceeasi functie ca in Cod_C).
 *
 * Comenzi de pe placa:
 *   SW0 = 1 : imaginea vine dintr-un generator (acelasi ca in Cod_C)
 *   SW1 = 1 : imaginea vine de pe cardul SD (img0.bmp .. img3.bmp)
 *   SW2,SW3 : alege imaginea 0..3 (SW3 SW2 in binar)
 *   BTN0    : START (switch-urile se citesc in momentul apasarii)
 *   SW0 = SW1 = 1 : invalid (LED3). SW0 = SW1 = 0 : nu se intampla nimic.
 *
 * LED-uri:
 *   LED0 : rezultat hardware identic cu cel software
 *   LED1 : (modul SD) REZULTAT.BMP salvat pe card
 *   LED2 : ocupat
 *   LED3 : eroare
 *
 * Imaginea de pe card: BMP grayscale 8 biti, necomprimat, cel mult
 * 512x512, randurile stocate de jos in sus (BMP obisnuit).
 * Bitstream-ul prelucreaza doar 512x512, deci o imagine mai mica se pune
 * in coltul stanga-sus al unui canvas 512x512 cu zero; zerourile din jur
 * se comporta ca zero padding, deci rezultatul din regiune este corect.
 */

#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "xparameters.h"
#include "xil_io.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "xstatus.h"
#include "sleep.h"
#include "xiltimer.h"
#include "xgpio.h"
#include "xaxidma.h"
#include "ff.h"
#include "conv2d.h"

/* Adresele din Address Editor (Vivado). Daca BSP-ul defineste deja
   numele XPAR_*, se folosesc acelea. */
#ifndef XPAR_DMA_BASEADDR
#define XPAR_DMA_BASEADDR 0x40400000
#endif
#ifndef XPAR_AXI_GPIO_BTN_BASEADDR
#define XPAR_AXI_GPIO_BTN_BASEADDR 0x41200000
#endif
#ifndef XPAR_AXI_GPIO_LED_BASEADDR
#define XPAR_AXI_GPIO_LED_BASEADDR 0x41210000
#endif
#ifndef XPAR_AXI_GPIO_SWS_BASEADDR
#define XPAR_AXI_GPIO_SWS_BASEADDR 0x41220000
#endif

/* Timerul global al Cortex-A9 (numarator crescator pe 64 de biti, la
   frecventa CPU/2). Il citim direct, ca in baseline: XTime_GetTime din
   xiltimer citeste timerul privat SCU si poate ramane pe 0. */
#define GTC_BASE XPAR_PS7_GLOBALTIMER_0_BASEADDR
#define GTC_COUNT_LO (GTC_BASE + 0x00u)
#define GTC_COUNT_HI (GTC_BASE + 0x04u)
#define GTC_CTRL (GTC_BASE + 0x08u)

/* COUNTS_PER_SECOND e definit fara paranteze in BSP (FREQ/2) */
static const uint64_t TICKS_PER_SEC_V = (uint64_t)(COUNTS_PER_SECOND);
#define TICKS_PER_SEC TICKS_PER_SEC_V

typedef uint64_t tick_t;

static void gtc_start(void)
{
    Xil_Out32(GTC_CTRL, Xil_In32(GTC_CTRL) | 1u);
}

static void tick_get(tick_t* t)
{
    uint32_t hi;
    uint32_t lo;
    uint32_t hi2;
    do {
        hi = Xil_In32(GTC_COUNT_HI);
        lo = Xil_In32(GTC_COUNT_LO);
        hi2 = Xil_In32(GTC_COUNT_HI);
    } while (hi != hi2);
    *t = ((tick_t)hi << 32) | lo;
}

#define SLCR_BASE 0xF8000000u

#define IMG_MAX 512
#define N_PIX (IMG_MAX * IMG_MAX)

#define LED0 0x1
#define LED1 0x2
#define LED2 0x4
#define LED3 0x8

/* in modul SD se aprinde LED0 si daca hardware == software (1) sau nu (0) */
#define SD_SHOW_MATCH 1

#define DMA_TIMEOUT_S 2

typedef struct {
    int w;
    int h;
    int mode;
    uint32_t in_sum;
    uint32_t out_sum;
} test_img_t;

/* 4 imagini generate cu make_image(); sumele sunt din Cod_C/checksums.txt */
static const test_img_t tests[4] = {
    { 8, 8, 0, 0xeaa1ffc5u, 0x585b0b81u },
    { 8, 8, 1, 0xac219a97u, 0xc8eef4f8u },
    { 128, 128, 1, 0xf446ee5eu, 0x9607334au },
    { 512, 512, 1, 0xc4a9261du, 0x26681436u }
};

static XGpio gpio_sws;
static XGpio gpio_btn;
static XGpio gpio_led;
static XAxiDma dma;
static FATFS fatfs;
static int sd_mounted = 0;

/* buffere in DDR, aliniate la linia de cache (32 octeti) */
static uint8_t img_buf[N_PIX] __attribute__((aligned(64)));
static uint8_t canvas_in[N_PIX] __attribute__((aligned(64)));
static uint8_t canvas_out[N_PIX] __attribute__((aligned(64)));
static uint8_t sw_out[N_PIX] __attribute__((aligned(64)));
static uint8_t hw_out[N_PIX] __attribute__((aligned(64)));
static uint8_t row_buf[IMG_MAX + 4];

static uint32_t ticks_to_us(tick_t t)
{
    return (uint32_t)((t * 1000000ULL) / TICKS_PER_SEC);
}

/* ------------------------------------------------------------------ */
/* GPIO, reset PL, DMA                                                */
/* ------------------------------------------------------------------ */

/* initializeaza un GPIO AXI la adresa base si ii seteaza directia
   (bit 1 = intrare, 0 = iesire). Intoarce 0 la succes. */
static int gpio_open(XGpio* g, UINTPTR base, u32 dir_mask)
{
    XGpio_Config cfg;
    memset(&cfg, 0, sizeof cfg);
#ifndef SDT
    cfg.DeviceId = 0;
#endif
    cfg.BaseAddress = base;
    cfg.InterruptPresent = 0;
    cfg.IsDual = 0;
    if (XGpio_CfgInitialize(g, &cfg, base) != XST_SUCCESS) {
        return -1;
    }
    XGpio_SetDataDirection(g, 1, dir_mask);
    return 0;
}

static void leds_set(u32 mask)
{
    XGpio_DiscreteWrite(&gpio_led, 1, mask);
}

/* reseteaza partea PL (FCLK_RESET0_N): readuce acceleratorul, DMA-ul si
   GPIO-urile la starea initiala. Dupa el trebuie reinitializat totul. */
static void pl_reset(void)
{
    Xil_Out32(SLCR_BASE + 0x008, 0xDF0D);
    Xil_Out32(SLCR_BASE + 0x240, 0x1);
    usleep(1000);
    Xil_Out32(SLCR_BASE + 0x240, 0x0);
    Xil_Out32(SLCR_BASE + 0x004, 0x767B);
    usleep(1000);
}

/* initializeaza AXI DMA in mod simplu (fara scatter-gather), fara
   intreruperi: starea se verifica prin polling. Intoarce 0 la succes. */
static int dma_open(void)
{
    XAxiDma_Config* cfg = XAxiDma_LookupConfig(XPAR_DMA_BASEADDR);
    if (cfg == NULL) {
        return -1;
    }
    if (XAxiDma_CfgInitialize(&dma, cfg) != XST_SUCCESS) {
        return -1;
    }
    if (XAxiDma_HasSg(&dma)) {
        return -1;
    }
    XAxiDma_IntrDisable(&dma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);
    XAxiDma_IntrDisable(&dma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DMA_TO_DEVICE);
    return 0;
}

/* reseteaza PL-ul, apoi initializeaza switch-urile, butonul, LED-urile
   si DMA-ul. Se apeleaza la pornire si dupa o eroare hardware. */
static int hw_init(void)
{
    pl_reset();
    if (gpio_open(&gpio_sws, XPAR_AXI_GPIO_SWS_BASEADDR, 0xF) != 0) {
        return -1;
    }
    if (gpio_open(&gpio_btn, XPAR_AXI_GPIO_BTN_BASEADDR, 0xF) != 0) {
        return -1;
    }
    if (gpio_open(&gpio_led, XPAR_AXI_GPIO_LED_BASEADDR, 0x0) != 0) {
        return -1;
    }
    leds_set(0);
    if (dma_open() != 0) {
        return -1;
    }
    return 0;
}

/* ------------------------------------------------------------------ */
/* Transfer prin DMA                                                  */
/* ------------------------------------------------------------------ */

/* asteapta (polling) sfarsitul transferului DMA pe directia data.
   Intoarce -1 daca depaseste DMA_TIMEOUT_S secunde de la t_start. */
static int wait_dma(int direction, tick_t t_start)
{
    tick_t now;
    while (XAxiDma_Busy(&dma, direction)) {
        tick_get(&now);
        if ((now - t_start) > (tick_t)TICKS_PER_SEC * DMA_TIMEOUT_S) {
            return -1;
        }
    }
    return 0;
}

/* trimite canvas_in (512x512) prin accelerator si primeste canvas_out.
   dma_ticks = durata transferului propriu-zis. Intoarce 0 la succes. */
static int run_hw(tick_t* dma_ticks)
{
    tick_t t0;
    tick_t t1;
    int st;

    memset(canvas_out, 0xA5, N_PIX);
    Xil_DCacheFlushRange((UINTPTR)canvas_in, N_PIX);
    Xil_DCacheFlushRange((UINTPTR)canvas_out, N_PIX);

    tick_get(&t0);

    /* S2MM (primire) se porneste primul, apoi MM2S (trimitere) */
    st = XAxiDma_SimpleTransfer(&dma, (UINTPTR)canvas_out, N_PIX,
                                XAXIDMA_DEVICE_TO_DMA);
    if (st != XST_SUCCESS) {
        return -1;
    }
    st = XAxiDma_SimpleTransfer(&dma, (UINTPTR)canvas_in, N_PIX,
                                XAXIDMA_DMA_TO_DEVICE);
    if (st != XST_SUCCESS) {
        return -1;
    }

    if (wait_dma(XAXIDMA_DMA_TO_DEVICE, t0) != 0) {
        xil_printf("DMA: timeout la trimitere (MM2S)\r\n");
        return -1;
    }
    if (wait_dma(XAXIDMA_DEVICE_TO_DMA, t0) != 0) {
        xil_printf("DMA: timeout la primire (S2MM)\r\n");
        return -1;
    }

    tick_get(&t1);
    *dma_ticks = t1 - t0;

    Xil_DCacheInvalidateRange((UINTPTR)canvas_out, N_PIX);
    return 0;
}

/* ------------------------------------------------------------------ */
/* Un test complet: canvas, software, hardware, comparatie            */
/* Intoarce numarul de pixeli diferiti, sau -1 la eroare hardware.    */
/* ref_in/ref_out: sumele asteptate (0 = nu se verifica)              */
/* ------------------------------------------------------------------ */

static int run_test(int w, int h, uint32_t ref_in, uint32_t ref_out,
                    int* refs_ok)
{
    tick_t t0;
    tick_t t1;
    tick_t dma_ticks = 0;
    int r;
    int c;
    int bad = 0;
    int first = -1;
    int n = w * h;
    uint32_t sum_in;
    uint32_t sum_sw;
    uint32_t sum_hw;

    *refs_ok = 1;
    sum_in = checksum(img_buf, n);

    /* canvas 512x512: zero + imaginea in coltul stanga-sus */
    memset(canvas_in, 0, N_PIX);
    for (r = 0; r < h; r++) {
        memcpy(&canvas_in[r * IMG_MAX], &img_buf[r * w], w);
    }

    /* software pe ARM, pe imaginea mica (zero padding la margini) */
    tick_get(&t0);
    conv_image(img_buf, sw_out, w, h);
    tick_get(&t1);
    uint32_t sw_us = ticks_to_us(t1 - t0);
    sum_sw = checksum(sw_out, n);

    /* hardware */
    tick_get(&t0);
    if (run_hw(&dma_ticks) != 0) {
        return -1;
    }
    tick_get(&t1);
    uint32_t hw_total_us = ticks_to_us(t1 - t0);
    uint32_t hw_dma_us = ticks_to_us(dma_ticks);

    /* regiunea w x h din canvas_out */
    for (r = 0; r < h; r++) {
        memcpy(&hw_out[r * w], &canvas_out[r * IMG_MAX], w);
    }
    sum_hw = checksum(hw_out, n);

    for (r = 0; r < h; r++) {
        for (c = 0; c < w; c++) {
            if (hw_out[r * w + c] != sw_out[r * w + c]) {
                if (first < 0) {
                    first = r * w + c;
                }
                bad++;
            }
        }
    }

    xil_printf("imagine %dx%d, %d pixeli\r\n", w, h, n);
    xil_printf("checksum intrare  : %08x\r\n", sum_in);
    xil_printf("checksum software : %08x\r\n", sum_sw);
    xil_printf("checksum hardware : %08x\r\n", sum_hw);
    if (ref_in != 0) {
        if (sum_in != ref_in || sum_sw != ref_out) {
            *refs_ok = 0;
            xil_printf("ATENTIE: sumele nu corespund cu Cod_C/checksums.txt "
                       "(asteptat in=%08x out=%08x)\r\n", ref_in, ref_out);
        } else {
            xil_printf("sumele de intrare si software corespund cu Cod_C\r\n");
        }
    }
    xil_printf("timp software       : %u us\r\n", sw_us);
    xil_printf("timp hardware total : %u us (cu flush/invalidate)\r\n",
               hw_total_us);
    xil_printf("timp transfer DMA   : %u us\r\n", hw_dma_us);

    if (bad == 0) {
        xil_printf("REZULTAT: hardware == software, 0 diferente\r\n");
    } else {
        xil_printf("REZULTAT: %d pixeli diferiti; primul la r=%d c=%d, "
                   "hw=%d sw=%d\r\n", bad, first / w, first % w,
                   hw_out[first], sw_out[first]);
    }
    return bad;
}

/* ------------------------------------------------------------------ */
/* Card SD: citire si scriere BMP grayscale 8 biti                    */
/* ------------------------------------------------------------------ */

static uint32_t rd32(const uint8_t* p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static void wr32(uint8_t* p, uint32_t v)
{
    p[0] = (uint8_t)(v & 0xFF);
    p[1] = (uint8_t)((v >> 8) & 0xFF);
    p[2] = (uint8_t)((v >> 16) & 0xFF);
    p[3] = (uint8_t)((v >> 24) & 0xFF);
}

/* monteaza cardul SD (FatFs) o singura data; apelurile urmatoare nu
   fac nimic. Intoarce 0 la succes. */
static int sd_mount(void)
{
    FRESULT res;
    if (sd_mounted) {
        return 0;
    }
    res = f_mount(&fatfs, "0:/", 1);
    if (res != FR_OK) {
        xil_printf("SD: eroare la montare, cod %d\r\n", (int)res);
        return -1;
    }
    sd_mounted = 1;
    return 0;
}

/* citeste BMP-ul in img_buf (w x h, orientare normala, randul 0 sus) */
static int sd_read_bmp(const char* name, int* pw, int* ph)
{
    FIL f;
    FRESULT res;
    uint br;
    uint8_t hdr[54];
    uint32_t offset;
    uint32_t w;
    int32_t h;
    uint32_t stride;
    int i;

    res = f_open(&f, name, FA_READ);
    if (res != FR_OK) {
        xil_printf("SD: nu pot deschide %s, cod %d\r\n", name, (int)res);
        return -1;
    }
    res = f_read(&f, hdr, sizeof hdr, &br);
    if (res != FR_OK || br != sizeof hdr) {
        xil_printf("SD: antet BMP incomplet\r\n");
        f_close(&f);
        return -1;
    }
    if (hdr[0] != 'B' || hdr[1] != 'M') {
        xil_printf("SD: %s nu este BMP\r\n", name);
        f_close(&f);
        return -1;
    }
    offset = rd32(&hdr[10]);
    w = rd32(&hdr[18]);
    h = (int32_t)rd32(&hdr[22]);
    if (hdr[28] != 8 || hdr[29] != 0) {
        xil_printf("SD: BMP-ul nu are 8 biti/pixel\r\n");
        f_close(&f);
        return -1;
    }
    if (rd32(&hdr[30]) != 0) {
        xil_printf("SD: BMP comprimat, nu se accepta\r\n");
        f_close(&f);
        return -1;
    }
    if (h <= 0) {
        xil_printf("SD: inaltime negativa (BMP de sus in jos), nu se accepta\r\n");
        f_close(&f);
        return -1;
    }
    if (w < 1 || w > IMG_MAX || h > IMG_MAX) {
        xil_printf("SD: dimensiune %ux%d in afara 1..512\r\n", (unsigned)w, (int)h);
        f_close(&f);
        return -1;
    }

    res = f_lseek(&f, offset);
    if (res != FR_OK) {
        xil_printf("SD: f_lseek a esuat\r\n");
        f_close(&f);
        return -1;
    }
    stride = (w + 3u) & ~3u;
    for (i = 0; i < h; i++) {
        res = f_read(&f, row_buf, stride, &br);
        if (res != FR_OK || br != stride) {
            xil_printf("SD: citire incompleta la randul %d\r\n", i);
            f_close(&f);
            return -1;
        }
        /* primul rand din fisier este ultimul rand al imaginii */
        memcpy(&img_buf[(h - 1 - i) * w], row_buf, w);
    }
    f_close(&f);
    *pw = (int)w;
    *ph = (int)h;
    return 0;
}

/* scrie img (w x h) ca BMP grayscale 8 biti cu paleta de gri, randurile
   de jos in sus, cu padding la multiplu de 4 octeti. Intoarce 0 la succes. */
static int sd_write_bmp(const char* name, const uint8_t* img, int w, int h)
{
    FIL f;
    FRESULT res;
    uint bw;
    uint8_t hdr[54];
    uint8_t pal[4];
    uint32_t stride = ((uint32_t)w + 3u) & ~3u;
    int i;

    memset(hdr, 0, sizeof hdr);
    hdr[0] = 'B';
    hdr[1] = 'M';
    wr32(&hdr[2], 54u + 1024u + stride * (uint32_t)h);
    wr32(&hdr[10], 54u + 1024u);
    wr32(&hdr[14], 40u);
    wr32(&hdr[18], (uint32_t)w);
    wr32(&hdr[22], (uint32_t)h);
    hdr[26] = 1;
    hdr[28] = 8;
    wr32(&hdr[34], stride * (uint32_t)h);
    wr32(&hdr[38], 2835u);
    wr32(&hdr[42], 2835u);
    wr32(&hdr[46], 256u);
    wr32(&hdr[50], 256u);

    res = f_open(&f, name, FA_CREATE_ALWAYS | FA_WRITE);
    if (res != FR_OK) {
        xil_printf("SD: nu pot crea %s, cod %d\r\n", name, (int)res);
        return -1;
    }
    res = f_write(&f, hdr, sizeof hdr, &bw);
    if (res != FR_OK || bw != sizeof hdr) {
        f_close(&f);
        return -1;
    }
    for (i = 0; i < 256; i++) {
        pal[0] = (uint8_t)i;
        pal[1] = (uint8_t)i;
        pal[2] = (uint8_t)i;
        pal[3] = 0;
        res = f_write(&f, pal, 4, &bw);
        if (res != FR_OK || bw != 4) {
            f_close(&f);
            return -1;
        }
    }
    for (i = 0; i < h; i++) {
        memset(row_buf, 0, sizeof row_buf);
        /* primul rand din fisier este ultimul rand al imaginii */
        memcpy(row_buf, &img[(h - 1 - i) * w], w);
        res = f_write(&f, row_buf, stride, &bw);
        if (res != FR_OK || bw != stride) {
            xil_printf("SD: scriere incompleta la randul %d\r\n", i);
            f_close(&f);
            return -1;
        }
    }
    f_close(&f);
    return 0;
}

/* ------------------------------------------------------------------ */
/* Butonul si programul principal                                     */
/* ------------------------------------------------------------------ */

static int btn0_pressed(void)
{
    return (XGpio_DiscreteRead(&gpio_btn, 1) & 0x1) != 0;
}

/* asteapta eliberarea lui BTN0, ca o singura apasare sa porneasca
   un singur START (plus o pauza de debounce). */
static void wait_btn_release(void)
{
    while (btn0_pressed()) {
        usleep(10000);
    }
    usleep(20000);
}

/* ruleaza o comanda START. sw = valoarea switch-urilor la apasare. */
static void do_start(u32 sw)
{
    int sw0 = (int)(sw & 0x1);
    int sw1 = (int)((sw >> 1) & 0x1);
    int idx = (int)((sw >> 2) & 0x3);
    int w = 0;
    int h = 0;
    int bad;
    int refs_ok = 1;
    char name[16];

    leds_set(0);

    if (sw0 && sw1) {
        xil_printf("Switch-uri invalide: SW0 si SW1 ambele pe 1\r\n");
        leds_set(LED3);
        return;
    }
    if (!sw0 && !sw1) {
        xil_printf("SW0 si SW1 pe 0: nimic de facut\r\n");
        return;
    }

    leds_set(LED2);

    if (sw0) {
        xil_printf("\r\n=== START: generator, imaginea %d ===\r\n", idx);
        w = tests[idx].w;
        h = tests[idx].h;
        make_image(img_buf, w, h, tests[idx].mode);
        bad = run_test(w, h, tests[idx].in_sum, tests[idx].out_sum, &refs_ok);
        if (bad < 0) {
            xil_printf("EROARE hardware, resetez partea PL\r\n");
            hw_init();
            leds_set(LED3);
            return;
        }
        if (bad == 0 && refs_ok) {
            leds_set(LED0);
        } else {
            leds_set(LED3);
        }
        return;
    }

    /* SW1: card SD */
    xil_printf("\r\n=== START: card SD, img%d.bmp ===\r\n", idx);
    if (sd_mount() != 0) {
        leds_set(LED3);
        return;
    }
    snprintf(name, sizeof name, "img%d.bmp", idx);
    if (sd_read_bmp(name, &w, &h) != 0) {
        leds_set(LED3);
        return;
    }
    bad = run_test(w, h, 0, 0, &refs_ok);
    if (bad < 0) {
        xil_printf("EROARE hardware, resetez partea PL\r\n");
        hw_init();
        leds_set(LED3);
        return;
    }
    if (sd_write_bmp("REZULTAT.BMP", hw_out, w, h) != 0) {
        leds_set(LED3);
        return;
    }
    xil_printf("Salvat REZULTAT.BMP (%dx%d)\r\n", w, h);
    if (SD_SHOW_MATCH && bad == 0) {
        leds_set(LED0 | LED1);
    } else if (SD_SHOW_MATCH && bad > 0) {
        leds_set(LED3);
    } else {
        leds_set(LED1);
    }
}

/* porneste cache-urile si timerul, initializeaza hardware-ul, apoi
   asteapta BTN0 intr-o bucla infinita si ruleaza do_start() la fiecare apasare. */
int main(void)
{
    Xil_ICacheEnable();
    Xil_DCacheEnable();
    gtc_start();

    xil_printf("\r\nP1: convolutie 2D pe FPGA\r\n");
    if (hw_init() != 0) {
        xil_printf("Initializare hardware esuata (DMA / GPIO)\r\n");
        while (1) {
        }
    }
    xil_printf("Gata. SW0/SW1 = sursa, SW2/SW3 = imaginea, BTN0 = START\r\n");

    while (1) {
        if (btn0_pressed()) {
            usleep(20000);
            if (btn0_pressed()) {
                u32 sw = XGpio_DiscreteRead(&gpio_sws, 1);
                do_start(sw);
                wait_btn_release();
            }
        }
        usleep(5000);
    }
    return 0;
}
