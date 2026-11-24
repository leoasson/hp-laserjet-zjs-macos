// SPDX-License-Identifier: GPL-2.0-or-later
#include <cups/raster.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

// CUPS raster (1-bit K or 8-bit W/K) -> concatenated PBM (P4) pages for foo2zjs.
int main(int argc, char **argv) {
    int fd = 0;
    if (argc == 2 && (fd = open(argv[1], O_RDONLY)) < 0) { perror(argv[1]); return 1; }

    cups_raster_t *ras = cupsRasterOpen(fd, CUPS_RASTER_READ);
    cups_page_header2_t h;
    int pages = 0;

    while (cupsRasterReadHeader2(ras, &h)) {
        unsigned w = h.cupsWidth, rows = h.cupsHeight, bpl = h.cupsBytesPerLine;
        unsigned outbpl = (w + 7) / 8;
        unsigned char *in = malloc(bpl), *out = calloc(1, outbpl);
        int white_is_zero = h.cupsColorSpace == CUPS_CSPACE_K;

        fprintf(stderr, "DEBUG: page %d %ux%u bpc=%u cs=%u res=%ux%u\n", pages + 1, w, rows,
                h.cupsBitsPerColor, h.cupsColorSpace, h.HWResolution[0], h.HWResolution[1]);
        printf("P4\n%u %u\n", w, rows);

        for (unsigned y = 0; y < rows; y++) {
            if (cupsRasterReadPixels(ras, in, bpl) == 0) break;
            if (h.cupsBitsPerColor == 1) {
                for (unsigned i = 0; i < outbpl; i++) out[i] = white_is_zero ? in[i] : ~in[i];
            } else {
                for (unsigned i = 0; i < outbpl; i++) out[i] = 0;
                for (unsigned x = 0; x < w; x++) {
                    unsigned v = in[x];
                    int black = white_is_zero ? v >= 128 : v < 128;
                    if (black) out[x >> 3] |= 0x80 >> (x & 7);
                }
            }
            fwrite(out, 1, outbpl, stdout);
        }
        free(in); free(out);
        pages++;
    }
    cupsRasterClose(ras);
    fprintf(stderr, "INFO: rastertopbm wrote %d page(s)\n", pages);
    return pages ? 0 : 1;
}
