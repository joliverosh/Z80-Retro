#!/bin/bash
# mkz.sh - arma los htc/PROGz.as: el ensamblador de cada programa (prog_a.s,
# de SDCC) pasado a ZAS con sdas2zas.py, y los puentes de convencion
# (puentes.py) para que lo llame el C de HI-TECH. Se corre en el PC.
set -e
cd "$(dirname "$0")"
z() {  # z salida.as entrada.s "funciones del asm" "funciones de C que llama" prototipo...
  local out=$1 src=$2 fa=$3 fc=$4; shift 4
  local ren=$(echo $fa $fc | tr ' ' '\n' | sed 's/^/_/' | paste -sd,)
  python3 sdas2zas.py $src /tmp/z1.$$ S_ "$ren" $(basename $src _a.s | tr a-z A-Z | cut -c1-3)
  python3 puentes.py /tmp/z2.$$ S_ "$@"
  { echo "; $out - de $(basename $src) (sdas2zas.py) y sus puentes (puentes.py); no se edita"; cat /tmp/z1.$$ /tmp/z2.$$; } > $out
  rm -f /tmp/z1.$$ /tmp/z2.$$
  echo "$out: $(wc -l < $out) lineas"
}
z fibz.as ../fib_a.s "addbcd" "" \
  "uint8_t addbcd(uint8_t *a, const uint8_t *b, uint16_t n)"
z chessz.as ../chess_a.s "attacked" "" \
  "1:uint8_t attacked(uint8_t s, uint8_t by)"
z sha256z.as ../sha256_a.s "shacomp" "" \
  "1:void shacomp(void)"
z unzipz.as ../unzip_a.s "bit bits decode" "getb" \
  "uint8_t bit(void)" "uint16_t bits(uint8_t n)" "uint16_t decode(TREE *t)" \
  "r:uint8_t getb(void)"
python3 sdas2zas.py ../crc32_a.s /tmp/c1.$$ S_ _crcbuf CRC; python3 puentes.py /tmp/c2.$$ S_ "uint32_t crcbuf(uint32_t c, const uint8_t *p, uint16_t n)"
cat /tmp/c1.$$ /tmp/c2.$$ > /tmp/crc.$$; rm -f /tmp/c1.$$ /tmp/c2.$$
cat /tmp/crc.$$ >> unzipz.as
z zipz.as ../zip_a.s "pbits slidetab mlen" "" \
  "void pbits(uint16_t v, uint8_t n)" "void slidetab(uint16_t *p, uint16_t n)" "uint16_t mlen(uint8_t *a, uint8_t *b, uint16_t lim)"
cat /tmp/crc.$$ >> zipz.as; rm -f /tmp/crc.$$
z zgptz.as ../zgpt_a.s "dotinit dot8 dotk umul16 smul16" "" \
  "void dotinit(uint8_t page)" "int32_t dot8(const uint8_t *w, uint8_t n, uint8_t x0)" \
  "void dotk(const uint8_t *k, int32_t *out, uint8_t npos, uint8_t x0)" \
  "uint32_t umul16(uint16_t a, uint16_t b)" "int32_t smul16(int16_t a, int16_t b)"
