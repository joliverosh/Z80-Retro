#!/bin/bash
# emu.sh rom "comandos separados por |" [ciclos]   (env pasa al emulador)
ROM=$1; CMDS=$2; CYC=${3:-150000000}
IN=$(mktemp); printf '%s' "$CMDS" | tr '|' '\r' > $IN; [ -n "$NOCR" ] || printf '\r' >> $IN
cp -n /home/claude/sim/sd1_cpm.img /home/claude/zr6/sd_test.img 2>/dev/null
SDIMG=${SDIMG:-/home/claude/zr6/sd_test.img} timeout 300 /home/claude/sim/retroemu23 $ROM $IN $CYC 2>&1 | tr -d '\000' | tr '\r' '\n' | sed 's/\x1b\[[0-9;]*[A-Za-z]//g' | grep -v '^$'
rm -f $IN
