; crt0.s - arranque de los programas en C (SDCC) para CP/M y MP/M: el .COM
; empieza en 0100h, la pila va al tope del TPA (la direccion de 0006h).
        .module crt0
        .globl  _main
        .globl  _exit
        .area   _HEADER (ABS)
        .org    0x100
        ld      sp,(6)
        call    gsinit
        call    _main
_exit::
        ld      c,#0
        jp      5
        .area   _HOME
        .area   _CODE
        .area   _INITIALIZER
        .area   _GSINIT
        .area   _GSFINAL
        .area   _DATA
        .area   _INITIALIZED
        .area   _BSEG
        .area   _BSS
        .area   _HEAP
        .area   _GSINIT
gsinit::
        ld      hl,#s__DATA     ; las variables sin valor inicial, en cero
        ld      bc,#l__DATA
        ld      a,b
        or      a,c
        jr      z,gs1
        ld      (hl),#0
        dec     bc
        ld      a,b
        or      a,c
        jr      z,gs1
        ld      d,h
        ld      e,l
        inc     de
        ldir
gs1:    ld      bc,#l__INITIALIZER
        ld      a,b
        or      a,c
        jr      z,gs2
        ld      de,#s__INITIALIZED
        ld      hl,#s__INITIALIZER
        ldir
gs2:
        .area   _GSFINAL
        ret
