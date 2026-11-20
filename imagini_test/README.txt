Imagini de test pentru P1 (convolutie 2D pe FPGA)
=================================================

Acest folder contine imaginile folosite pentru a testa acceleratorul de
convolutie 2D (Gaussian 3x3) in modul "card SD" al aplicatiei de pe placa
Zybo Z7-20, precum si rezultatele asteptate.

Continut
--------
  card_SD/     cele 4 imagini de intrare, de copiat pe cardul SD
  asteptat/    rezultatul corect al filtrarii pentru fiecare imagine
  extra/       o imagine suplimentara (textura), optionala
  previzualizare.png   vedere de ansamblu a imaginilor

Imaginile de intrare (card_SD/)
-------------------------------
Fisierele se copiaza in radacina cardului SD (FAT32). Aplicatia alege imaginea
dupa switch-urile SW3 si SW2, citite in momentul apasarii lui BTN0; modul card
SD se activeaza cu SW1 = 1 si SW0 = 0.

  fisier    SW3 SW2   dimensiune   sursa
  img0.bmp   0   0    64x64        decupaj central din cameraman
  img1.bmp   0   1    301x303      decupaj din coins; latimea nu e multiplu de 4
                                   si imaginea nu e patrata, deci testeaza
                                   padding-ul de rand al formatului BMP
  img2.bmp   1   0    512x512      astronaut (NASA), grayscale
  img3.bmp   1   1    512x512      cameraman

Imaginea suplimentara extra/extra_gravel.bmp este o textura 512x512 cu detalii
fine, pe care efectul de blur se vede bine. Nu este asociata unei combinatii de
switch-uri; pentru a fi folosita se copiaza pe card sub numele img0.bmp ..
img3.bmp, in locul uneia dintre imagini.

Rezultatul
----------
Aplicatia scrie rezultatul filtrarii in REZULTAT.BMP, in radacina cardului.
Fisierul corespunzator din asteptat/ (img0_gauss.bmp .. img3_gauss.bmp,
extra_gravel_gauss.bmp) contine rezultatul corect, calculat cu aceeasi functie
ca in Cod_C: Gaussian 1 2 1 / 2 4 2 / 1 2 1, zero padding, impartire la 16
prin shift cu 4 biti, saturare la 0..255. Rezultatul a fost verificat identic
cu cel produs de conv2d.c.

Daca hardware-ul este corect, datele de imagine din REZULTAT.BMP (de la
offset-ul 1078, adica dupa antetul de 54 de octeti si paleta de 1024 de
octeti) coincid octet cu octet cu cele din fisierul asteptat. Antetele difera
in cei 8 octeti care retin rezolutia (aplicatia scrie 2835 pixeli/metru,
fisierele din asteptat/ au 3780), deci o comparatie a intregului fisier va
raporta aceasta diferenta, fara ca ea sa indice o eroare.

Format
------
BMP grayscale pe 8 biti, necomprimat, cu paleta de 256 de nuante de gri,
randurile stocate de jos in sus. Aplicatia accepta cel mult 512x512, deoarece
acceleratorul din bitstream prelucreaza o imagine de 512x512; imaginile mai
mici se plaseaza in coltul stanga-sus al unui canvas completat cu zero, care
se comporta ca zero padding.

Surse si licente
----------------
Imaginile provin din scikit-image (pachetul Python):
  cameraman: CC0, fotograf Lav Varshney
  astronaut: NASA, domeniu public (Eileen Collins)
  coins:     fara restrictii de copyright cunoscute
  gravel:    textura CC0 (CC0Textures)
