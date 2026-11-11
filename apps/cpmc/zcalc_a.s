; zcalc_a.s - aritmetica de 64 bits para ZCALC (sdcccall 0: todo en la pila)
; q es un numero de 8 bytes, el byte bajo primero.
        .module zcalc_a
        .area   _DATA
ma:     .ds     8               ; multiplicando corrido
mb:     .ds     4               ; multiplicador
mr:     .ds     2               ; puntero al producto
mrm:    .ds     5               ; resto de la division
mt:     .ds     8               ; temporal

        .area   _CODE
; void m32x32(uint8_t *r, uint32_t a, uint32_t b): r = a * b
_m32x32::
        push    ix
        ld      ix,#0
        add     ix,sp           ; 4 r, 6 a, 10 b
        ld      hl,#ma
        ld      b,#8
m1:     ld      (hl),#0
        inc     hl
        djnz    m1
        ld      l,4(ix)
        ld      h,5(ix)
        ld      (mr),hl
        ld      b,#8
m2:     ld      (hl),#0
        inc     hl
        djnz    m2
        ld      a,6(ix)
        ld      (ma),a
        ld      a,7(ix)
        ld      (ma+1),a
        ld      a,8(ix)
        ld      (ma+2),a
        ld      a,9(ix)
        ld      (ma+3),a
        ld      a,10(ix)
        ld      (mb),a
        ld      a,11(ix)
        ld      (mb+1),a
        ld      a,12(ix)
        ld      (mb+2),a
        ld      a,13(ix)
        ld      (mb+3),a
        ld      c,#32
m3:     ld      hl,#mb+3
        srl     (hl)
        dec     hl
        rr      (hl)
        dec     hl
        rr      (hl)
        dec     hl
        rr      (hl)
        jr      nc,m5
        ld      hl,(mr)
        ld      de,#ma
        ld      b,#8
        or      a
m4:     ld      a,(de)
        adc     a,(hl)
        ld      (hl),a
        inc     hl
        inc     de
        djnz    m4
m5:     ld      hl,#ma
        call    shl1
        dec     c
        jr      nz,m3
        pop     ix
        ret

; shl1: (hl) de 8 bytes, un bit a la izquierda (hl no cambia)
shl1:   push    hl
        ld      b,#8
        or      a
s1:     rl      (hl)
        inc     hl
        djnz    s1
        pop     hl
        ret

; void d64x32(uint8_t *q, uint32_t d): q = q / d
_d64x32::
        push    ix
        ld      ix,#0
        add     ix,sp           ; 4 q, 6 d
        xor     a
        ld      (mrm),a
        ld      (mrm+1),a
        ld      (mrm+2),a
        ld      (mrm+3),a
        ld      (mrm+4),a
        ld      c,#64
d1:     ld      l,4(ix)
        ld      h,5(ix)
        call    shl1
        ld      hl,#mrm
        ld      b,#5
d2:     rl      (hl)
        inc     hl
        djnz    d2
        ld      a,(mrm)
        sub     6(ix)
        ld      (mt),a
        ld      a,(mrm+1)
        sbc     a,7(ix)
        ld      (mt+1),a
        ld      a,(mrm+2)
        sbc     a,8(ix)
        ld      (mt+2),a
        ld      a,(mrm+3)
        sbc     a,9(ix)
        ld      (mt+3),a
        ld      a,(mrm+4)
        sbc     a,#0
        jr      c,d3
        ld      (mrm+4),a
        ld      a,(mt)
        ld      (mrm),a
        ld      a,(mt+1)
        ld      (mrm+1),a
        ld      a,(mt+2)
        ld      (mrm+2),a
        ld      a,(mt+3)
        ld      (mrm+3),a
        ld      l,4(ix)
        ld      h,5(ix)
        set     0,(hl)
d3:     dec     c
        jr      nz,d1
        pop     ix
        ret

; uint8_t d64x8(uint8_t *q, uint8_t d): q = q / d; devuelve el resto
_d64x8::
        push    ix
        ld      ix,#0
        add     ix,sp           ; 4 q, 6 d
        ld      e,6(ix)
        ld      d,#0            ; resto
        ld      c,#64
e1:     ld      l,4(ix)
        ld      h,5(ix)
        call    shl1
        rl      d
        jr      c,e2
        ld      a,d
        cp      e
        jr      c,e3
e2:     ld      a,d
        sub     e
        ld      d,a
        ld      l,4(ix)
        ld      h,5(ix)
        set     0,(hl)
e3:     dec     c
        jr      nz,e1
        ld      l,d
        pop     ix
        ret

; void q10(uint8_t *q): q = q * 10
_q10::
        ld      hl,#2
        add     hl,sp
        ld      a,(hl)
        inc     hl
        ld      h,(hl)
        ld      l,a
        call    shl1            ; q * 2
        push    hl
        ld      de,#mt
        ld      bc,#8
        ldir
        pop     hl
        call    shl1
        call    shl1            ; q * 8
        ld      de,#mt
        ld      b,#8
        or      a
q1:     ld      a,(de)
        adc     a,(hl)
        ld      (hl),a
        inc     hl
        inc     de
        djnz    q1
        ret

; ------------------------------------------------------------------ numeros
; num: m (4 bytes, con signo) y e (1 byte con signo); valor = m * 10^e,
; |m| < 10^9 y sin ceros al final. Rutinas con sdcccall 0.
        .area   _DATA
_nerr:: .ds     1               ; desbordamiento o division por cero
wa:     .ds     5
wb:     .ds     5
acc:    .ds     4
t32:    .ds     4
nexp:   .ds     2
nneg:   .ds     1
nd:     .ds     1
nk:     .ds     1
nsa:    .ds     1
nsb:    .ds     1
nrem:   .ds     1
nrnd:   .ds     1
rptr:   .ds     2
_qq::   .ds     8

        .area   _CODE
p10t:   .dw     1,0, 10,0, 100,0, 1000,0, 10000,0, 0x86A0,1, 0x4240,0x0F
        .dw     0x9680,0x98, 0xE100,0x5F5, 0xCA00,0x3B9A
p64t:   .db 0x00,0xCA,0x9A,0x3B,0x00,0x00,0x00,0x00
        .db 0x00,0xE4,0x0B,0x54,0x02,0x00,0x00,0x00
        .db 0x00,0xE8,0x76,0x48,0x17,0x00,0x00,0x00
        .db 0x00,0x10,0xA5,0xD4,0xE8,0x00,0x00,0x00
        .db 0x00,0xA0,0x72,0x4E,0x18,0x09,0x00,0x00
        .db 0x00,0x40,0x7A,0x10,0xF3,0x5A,0x00,0x00
        .db 0x00,0x80,0xC6,0xA4,0x7E,0x8D,0x03,0x00
        .db 0x00,0x00,0xC1,0x6F,0xF2,0x86,0x23,0x00
        .db 0x00,0x00,0x8A,0x5D,0x78,0x45,0x63,0x01
        .db 0x00,0x00,0x64,0xA7,0xB3,0xB6,0xE0,0x0D

; div10: DEHL = DEHL / 10; A = resto
div10:  xor     a
        ld      b,#32
dv1:    add     hl,hl
        rl      e
        rl      d
        rla
        cp      #10
        jr      c,dv2
        sub     #10
        inc     l
dv2:    djnz    dv1
        ret
; mul10: DEHL = DEHL * 10
mul10:  add     hl,hl
        rl      e
        rl      d
        ld      (t32),hl
        ld      (t32+2),de
        add     hl,hl
        rl      e
        rl      d
        add     hl,hl
        rl      e
        rl      d
        ld      bc,(t32)
        add     hl,bc
        ex      de,hl
        ld      bc,(t32+2)
        adc     hl,bc
        ex      de,hl
        ret
; ge1e9: carry si DEHL < 10^9
ge1e9:  ld      a,l
        sub     #0x00
        ld      a,h
        sbc     a,#0xCA
        ld      a,e
        sbc     a,#0x9A
        ld      a,d
        sbc     a,#0x3B
        ret
; neg32: DEHL = -DEHL
neg32:  xor     a
        sub     l
        ld      l,a
        ld      a,#0
        sbc     a,h
        ld      h,a
        ld      a,#0
        sbc     a,e
        ld      e,a
        ld      a,#0
        sbc     a,d
        ld      d,a
        ret
; sx: HL = A con signo
sx:     ld      l,a
        add     a,a
        sbc     a,a
        ld      h,a
        ret
; incexp: nexp + 1
incexp: push    hl
        ld      hl,(nexp)
        inc     hl
        ld      (nexp),hl
        pop     hl
        ret
; ndigr: A = cifras de DEHL (1-10); no cambia DEHL
ndigr:  push    ix
        push    bc
        ld      ix,#p10t+4
        ld      c,#1
nd1:    ld      a,c
        cp      #10
        jr      z,nd2
        ld      a,l
        sub     0(ix)
        ld      a,h
        sbc     a,1(ix)
        ld      a,e
        sbc     a,2(ix)
        ld      a,d
        sbc     a,3(ix)
        jr      c,nd2
        inc     c
        inc     ix
        inc     ix
        inc     ix
        inc     ix
        jr      nd1
nd2:    ld      a,c
        pop     bc
        pop     ix
        ret
; uint8_t ndig(uint32_t u)
_ndig::
        ld      hl,#2
        add     hl,sp
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      a,(hl)
        inc     hl
        ld      h,(hl)
        ld      l,a
        ex      de,hl
        call    ndigr
        ld      l,a
        ret
; ldmag: DEHL = |m| del num en (ix); C = 1 si es negativo
ldmag:  ld      l,0(ix)
        ld      h,1(ix)
        ld      e,2(ix)
        ld      d,3(ix)
        ld      c,#0
        bit     7,d
        ret     z
        inc     c
        jp      neg32
; iszero: Z si el num en (hl) es 0
iszero: ld      a,(hl)
        inc     hl
        or      (hl)
        inc     hl
        or      (hl)
        inc     hl
        or      (hl)
        ret
; args3: (hl) = r, a, b -> rptr, wa, wb
args3:  ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      (rptr),de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        push    hl
        ex      de,hl
        ld      de,#wa
        ld      bc,#5
        ldir
        pop     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl
        ld      de,#wb
        ld      bc,#5
        ldir
        ret
copya:  ld      hl,#wa
        jr      copy
copyb:  ld      hl,#wb
copy:   ld      de,(rptr)
        ld      bc,#5
        ldir
        ret
zres:   ld      hl,(rptr)
        ld      b,#5
zr1:    ld      (hl),#0
        inc     hl
        djnz    zr1
        ret

; norm: DEHL = magnitud, nexp, nneg -> num en (rptr), redondeado a 9 cifras
norm:   call    ge1e9
        jr      c,no1
        call    div10
        call    incexp
        cp      #5
        jr      c,no1
        ld      bc,#1
        add     hl,bc
        jr      nc,no1
        inc     de
no1:    ld      a,d
        or      e
        or      h
        or      l
        jp      z,zres
no2:    push    de              ; quitar los ceros del final
        push    hl
        call    div10
        or      a
        jr      nz,no3
        pop     af
        pop     af
        call    incexp
        jr      no2
no3:    pop     hl
        pop     de
        ld      (acc),hl
        ld      (acc+2),de
        ld      hl,(nexp)
        ld      bc,#99
        add     hl,bc
        bit     7,h
        jp      nz,zres         ; e < -99: cero
        ld      bc,#-199
        add     hl,bc
        jr      nc,no4
        ld      a,#1            ; e > 99: desborde
        ld      (_nerr),a
        jp      zres
no4:    ld      a,(nneg)
        or      a
        jr      z,no5
        ld      hl,#acc
        ld      b,#4
no6:    ld      a,#0
        sbc     a,(hl)
        ld      (hl),a
        inc     hl
        djnz    no6
no5:    ld      de,(rptr)
        ld      hl,#acc
        ld      bc,#4
        ldir
        ld      a,(nexp)
        ld      (de),a
        ret

; void mk32(num *x, uint32_t v, uint8_t neg, int16_t e)
_mk32::
        ld      hl,#2
        add     hl,sp
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      (rptr),de
        ld      c,(hl)
        inc     hl
        ld      b,(hl)
        inc     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      a,(hl)
        ld      (nneg),a
        inc     hl
        ld      a,(hl)
        inc     hl
        ld      h,(hl)
        ld      l,a
        ld      (nexp),hl
        ld      h,b
        ld      l,c
        jp      norm

; void nadd(num *r, const num *a, const num *b)
_nadd::
        push    ix
        ld      hl,#4
        add     hl,sp
        call    _naddi
        pop     ix
        ret
_naddi:
        call    args3
        ld      hl,#wb
        call    iszero
        jp      z,copya
        ld      hl,#wa
        call    iszero
        jp      z,copyb
        ld      a,(wa+4)        ; que a tenga el exponente mayor
        call    sx
        ex      de,hl
        ld      a,(wb+4)
        call    sx
        or      a
        sbc     hl,de
        jr      c,na1
        jr      z,na1
        ld      hl,#wa
        ld      de,#wb
        ld      b,#5
sw1:    ld      a,(de)
        ld      c,(hl)
        ld      (hl),a
        ld      a,c
        ld      (de),a
        inc     hl
        inc     de
        djnz    sw1
na1:    ld      a,(wa+4)
        ld      hl,#wb+4
        sub     (hl)
        ld      (nd),a          ; d = a.e - b.e
        cp      #19
        jp      nc,copya        ; b no cuenta
        ld      ix,#wa
        call    ldmag
        ld      a,c
        ld      (nsa),a
        call    ndigr           ; a hasta 9 cifras, sin pasar de d
        ld      b,a
        ld      a,#9
        sub     b
        ld      b,a
        ld      a,(nd)
        cp      b
        jr      c,na2
        ld      a,b
na2:    ld      (nk),a
        or      a
        jr      z,na3
na4:    push    af
        call    mul10
        pop     af
        dec     a
        jr      nz,na4
na3:    ld      (acc),hl
        ld      (acc+2),de
        ld      a,(wa+4)
        call    sx
        ld      a,(nk)
        ld      e,a
        ld      d,#0
        or      a
        sbc     hl,de
        ld      (nexp),hl
        ld      a,(nd)
        ld      hl,#nk
        sub     (hl)
        ld      (nd),a
        ld      ix,#wb
        call    ldmag
        ld      a,c
        ld      (nsb),a
        ld      a,(nd)          ; b a ese exponente, redondeado
        cp      #10
        jr      c,na5
        ld      hl,#0
        ld      d,h
        ld      e,l
        jr      na7
na5:    or      a
        jr      z,na7
na6:    push    af
        call    div10
        ld      (nrem),a
        pop     af
        dec     a
        jr      nz,na6
        ld      a,(nrem)
        cp      #5
        jr      c,na7
        ld      bc,#1
        add     hl,bc
        jr      nc,na7
        inc     de
na7:    ld      a,(nsb)
        or      a
        call    nz,neg32
        ld      (t32),hl
        ld      (t32+2),de
        ld      hl,(acc)
        ld      de,(acc+2)
        ld      a,(nsa)
        or      a
        call    nz,neg32
        ld      bc,(t32)
        add     hl,bc
        ex      de,hl
        ld      bc,(t32+2)
        adc     hl,bc
        ex      de,hl
        xor     a
        bit     7,d
        jr      z,na8
        call    neg32
        ld      a,#1
na8:    ld      (nneg),a
        jp      norm

; red64: qq (hasta 10^19) a 9 cifras con redondeo; nexp sube; luego norm
red64:  ld      ix,#p64t
        xor     a
        ld      (nk),a
r1:     ld      a,(nk)
        cp      #10
        jr      z,r2
        ld      hl,#_qq         ; qq - tabla: carry si qq es menor
        push    ix
        pop     de
        ld      b,#8
        or      a
r0:     ld      a,(de)
        ld      c,a
        ld      a,(hl)
        sbc     a,c
        inc     hl
        inc     de
        djnz    r0
        jr      c,r2
        ld      hl,#nk
        inc     (hl)
        ld      de,#8
        add     ix,de
        jr      r1
r2:     xor     a
        ld      (nrem),a
        ld      a,(nk)          ; qq tiene 9 + nk cifras: quitar nk
        or      a
        jr      z,r5
        dec     a
        jr      z,r3
        add     a,a             ; qq / 10^(nk-1)
        add     a,a
        ld      e,a
        ld      d,#0
        ld      hl,#p10t
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      a,(hl)
        inc     hl
        ld      h,(hl)
        ld      l,a
        push    hl
        push    de
        ld      hl,#_qq
        push    hl
        call    _d64x32
        pop     af
        pop     af
        pop     af
r3:     ld      a,#10
        push    af
        inc     sp
        ld      hl,#_qq
        push    hl
        call    _d64x8
        pop     af
        inc     sp
        ld      a,l
        ld      (nrem),a
        ld      hl,(nexp)
        ld      a,(nk)
        ld      e,a
        ld      d,#0
        add     hl,de
        ld      (nexp),hl
r5:     ld      hl,(_qq)
        ld      de,(_qq+2)
        ld      a,(nrem)
        cp      #5
        jp      c,norm
        ld      bc,#1
        add     hl,bc
        jp      nc,norm
        inc     de
        jp      norm

; void nmul(num *r, const num *a, const num *b)
_nmul::
        push    ix
        ld      hl,#4
        add     hl,sp
        call    _nmuli
        pop     ix
        ret
_nmuli:
        call    args3
        ld      hl,#wa
        call    iszero
        jp      z,zres
        ld      hl,#wb
        call    iszero
        jp      z,zres
        ld      a,(wa+4)
        call    sx
        ex      de,hl
        ld      a,(wb+4)
        call    sx
        add     hl,de
        ld      (nexp),hl
        ld      ix,#wa
        call    ldmag
        ld      a,c
        ld      (nsa),a
        ld      (acc),hl
        ld      (acc+2),de
        ld      ix,#wb
        call    ldmag
        ld      a,(nsa)
        xor     c
        ld      (nneg),a
        push    de
        push    hl
        ld      hl,(acc+2)
        push    hl
        ld      hl,(acc)
        push    hl
        ld      hl,#_qq
        push    hl
        call    _m32x32
        ld      hl,#10
        add     hl,sp
        ld      sp,hl
        jp      red64

; void ndiv(num *r, const num *a, const num *b)
_ndiv::
        push    ix
        ld      hl,#4
        add     hl,sp
        call    _ndivi
        pop     ix
        ret
_ndivi:
        call    args3
        ld      hl,#wb
        call    iszero
        jr      nz,dd1
        ld      a,#1
        ld      (_nerr),a
        jp      zres
dd1:    ld      hl,#wa
        call    iszero
        jp      z,zres
        ld      ix,#wb
        call    ldmag
        ld      a,c
        ld      (nsb),a
        ld      (t32),hl        ; |b| para despues
        ld      (t32+2),de
        push    de
        push    hl
        ld      ix,#wa
        call    ldmag
        ld      a,(nsb)
        xor     c
        ld      (nneg),a
        call    ndigr           ; |a| a 9 cifras
        ld      b,a
        ld      a,#9
        sub     b
        ld      (nk),a
        jr      z,dd3
dd2:    push    af
        call    mul10
        pop     af
        dec     a
        jr      nz,dd2
dd3:    ld      (acc),hl
        ld      (acc+2),de
        ld      a,(wa+4)        ; e = a.e - k - 10 - b.e
        call    sx
        ld      a,(nk)
        add     a,#10
        ld      e,a
        ld      d,#0
        or      a
        sbc     hl,de
        ex      de,hl
        ld      a,(wb+4)
        call    sx
        ex      de,hl
        or      a
        sbc     hl,de
        ld      (nexp),hl
        ld      hl,#0x3B9A      ; qq = |a| * 10^9
        push    hl
        ld      hl,#0xCA00
        push    hl
        ld      hl,(acc+2)
        push    hl
        ld      hl,(acc)
        push    hl
        ld      hl,#_qq
        push    hl
        call    _m32x32
        ld      hl,#10
        add     hl,sp
        ld      sp,hl
        ld      hl,#_qq         ; * 10
        push    hl
        call    _q10
        pop     af
        ld      hl,#_qq         ; / |b| (en la pila)
        push    hl
        call    _d64x32
        pop     af
        pop     af
        pop     af
        jp      red64

; void nround(num *r, const num *a, int8_t d): a d decimales
; void ntrunc(num *r, const num *a): sin decimales, hacia el cero
_ntrunc::
        xor     a
        ld      (nrnd),a
        ld      c,#0
        jr      nr00
_nround::
        ld      a,#1
        ld      (nrnd),a
        ld      hl,#6
        add     hl,sp
        ld      c,(hl)
nr00:   push    ix
        ld      hl,#4
        add     hl,sp
        call    nr0
        pop     ix
        ret
nr0:    ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      (rptr),de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl
        ld      de,#wa
        push    bc
        ld      bc,#5
        ldir
        pop     bc
        ld      a,c             ; nexp = -d
        neg
        call    sx
        ld      (nexp),hl
        ld      a,(wa+4)        ; k = -e - d
        call    sx
        ex      de,hl
        ld      a,c
        call    sx
        add     hl,de
        ex      de,hl
        ld      hl,#0
        or      a
        sbc     hl,de
        bit     7,h
        jp      nz,copya        ; k < 0
        ld      a,h
        or      l
        jp      z,copya         ; k = 0
        ld      a,h
        or      a
        jp      nz,zres
        ld      a,l
        cp      #10
        jp      nc,zres
        ld      (nk),a
        ld      ix,#wa
        call    ldmag
        ld      a,c
        ld      (nneg),a
        ld      a,(nk)
nr1:    push    af
        call    div10
        ld      (nrem),a
        pop     af
        dec     a
        jr      nz,nr1
        ld      a,(nrnd)
        or      a
        jp      z,norm
        ld      a,(nrem)
        cp      #5
        jp      c,norm
        ld      bc,#1
        add     hl,bc
        jp      nc,norm
        inc     de
        jp      norm
