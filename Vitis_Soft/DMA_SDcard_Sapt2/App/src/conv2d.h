#ifndef CONV2D_H
#define CONV2D_H

#include <stdint.h>

/* genereaza o imagine de test.
   mode 0 = gradient: pixel = 4 * (r * w + c)
   mode 1 = pseudo-aleator, mereu aceleasi valori */
void make_image(uint8_t* im, int w, int h, int mode);

/* limiteaza valoarea v la intervalul 0-255. */
uint8_t saturate(int v);

/* intoarce pixelul de la (r, c), sau 0 daca e in afara imaginii
   (zero padding). */
int get_pixel(const uint8_t* im, int w, int h, int r, int c);

/* calculeaza noul pixel de la (r, c): suma celor 9 produse cu nucleul,
   impartita la 16 prin shift cu 4 biti (trunchiere). */
int conv_pixel(const uint8_t* im, int w, int h, int r, int c);

/* aplica convolutia pe toata imaginea in si scrie rezultatul in out,
   cu saturare la 0-255. */
void conv_image(const uint8_t* in, uint8_t* out, int w, int h);

/* suma de control (FNV-1a pe 32 de biti) a unei imagini, ca sa putem
   compara rapid rezultatele de pe PC si de pe ARM. */
uint32_t checksum(const uint8_t* im, int n);

#endif
