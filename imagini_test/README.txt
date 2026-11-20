Imagini de test pentru P1 (convolutie 2D pe FPGA)

Pe cardul SD, in radacina (FAT32), pune cele 4 fisiere din card_SD/:
  img0.bmp  SW3=0 SW2=0   64x64, decupaj central din cameraman
  img1.bmp  SW3=0 SW2=1   301x303, decupaj din coins (latime nemultiplu de 4,
                          imagine nepatrata: testeaza padding-ul de rand)
  img2.bmp  SW3=1 SW2=0   512x512, astronaut (NASA), grayscale
  img3.bmp  SW3=1 SW2=1   512x512, cameraman
(SW1 = 1 pentru modul card SD, SW0 = 0.)

Aplicatia scrie rezultatul in REZULTAT.BMP pe card. Ca sa verifici pe laptop,
compara-l cu fisierul din asteptat/ al aceleiasi imagini (img0_gauss.bmp etc.):
trebuie sa fie identic octet cu octet daca hardware-ul este corect.
(Calculat cu aceeasi functie ca in Cod_C: Gaussian 1 2 1 / 2 4 2 / 1 2 1,
zero padding, shift cu 4, saturare 0..255; verificat identic cu conv2d.c.)

extra/extra_gravel.bmp: textura 512x512 cu detalii fine, la care se vede bine
efectul de blur. Nu e legata de switch-uri; redenumeste-o img3.bmp ca s-o
folosesti.

Format: BMP grayscale 8 biti, necomprimat, cu paleta de 256 de nuante de gri,
randuri de jos in sus, maxim 512x512 (cel citit de aplicatie).

Surse si licente (din scikit-image, pachetul Python):
  cameraman: CC0, fotograf Lav Varshney
  astronaut: NASA, domeniu public (Eileen Collins)
  coins: fara restrictii de copyright cunoscute
  gravel: textura CC0 (CC0Textures)
