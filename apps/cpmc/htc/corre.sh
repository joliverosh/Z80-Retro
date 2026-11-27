#!/bin/bash
# corre.sh guion archivo... - corre un guion de zemu bajo ZOS con esos archivos en A:
set -e
T=$(mktemp -d); mkdir -p $T/d; for f in "$@"; do [ "$f" = "${1}" ] && continue; cp "$f" $T/d/; done
python3 ${MKSD:-/tmp/claude-0/zb/zos/tools/mksd.py} $T/t.img 24 $T/d/* >/dev/null
timeout ${TMO:-300} ${ZEMU:-/tmp/claude-0/zemu} ${ZOS:-/tmp/claude-0/zb/zos/build/zos.bin} -s $T/t.img -i "$1" -E ${E:-3} -c ${C:-60000000000} 2>/dev/null | tr -d '\r' | sed -n '/^sh: pid/,$p' | sed 1d
rm -rf $T
