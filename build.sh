#!/bin/bash
# Compila ZLoader (version RELEASE) y genera la imagen de 512 KB para la SST39SF040.
# Requiere zmac, ld80 y node en el PATH.
# Ojo: los mk.sh del proyecto usan pushd/popd, asi que tienen que correr con
# bash. Con sh (dash) pushd falla y zloader/mk.sh se vuelve a llamar a si mismo
# sin fin.
set -e
cd "$(dirname "$0")/zloader"
mkdir -p zout ../zlib/zout ../zios/zout
RELEASE=1 timeout 300 bash ./mk.sh > build.log 2>&1 || true
if grep -qiE "pushd: not found|errors? \(see listing|Undeclared|Syntax error|ld80: " build.log; then
  grep -iE "\([0-9]+\) :|pushd|ld80: " build.log | head -20; echo "ERRORES de compilacion"; exit 1
fi
python3 ../tools/chkmem.py build.log || { echo "ERRORES de memoria"; exit 1; }
python3 - <<'PY'
d=bytearray(b'\xff'*524288); base=0
for l in open('loader.hex'):
    l=l.strip()
    if not l.startswith(':'): continue
    b=bytes.fromhex(l[1:]); n,a,t=b[0],(b[1]<<8)|b[2],b[3]
    if t==0: d[base+a:base+a+n]=b[4:4+n]
    elif t==2: base=((b[4]<<8)|b[5])<<4
    elif t==4: base=((b[4]<<8)|b[5])<<16
open('zloader_sst39sf040.bin','wb').write(d)
PY
echo "OK: zloader/zloader_sst39sf040.bin"

# Imagen con el disco en flash (unidad H: de CP/M) con las aplicaciones basicas
python3 ../tools/mkflashdisk.py zloader_sst39sf040.bin zloader_sst39sf040_fd.bin \
    ../cpmtools/download.hex ../images/cpm22apps.pkg ../cpmtools/format.hex \
    ../apps/pi/PI1K.COM ../apps/pi/PI10K.COM \
    -u3 ../apps/cpm3/cpm3.pkg > mkflashdisk.log && \
    echo "OK: zloader/zloader_sst39sf040_fd.bin (con disco en flash)"
