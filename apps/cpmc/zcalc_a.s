; zcalc_a.s - aritmetica de ZCALC 1.2 (sdcccall 0: todo en la pila)
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
        sbc     hl,de           ; b.e - a.e (con signo)
        bit     7,h
        jr      nz,na1
        ld      a,h
        or      l
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

; ------------------------------------------------------------------ numeros a texto
        .area   _DATA
fo:     .ds     2               ; donde se escribe
fx:     .ds     5               ; el numero
fy:     .ds     5               ; el numero redondeado
fdg:    .ds     11              ; sus cifras
fnd:    .ds     1
fneg:   .ds     1
fip:    .ds     1
ffp:    .ds     1
fdec:   .ds     1
fmax:   .ds     1
flen:   .ds     1
udg:    .ds     1
pdot:   .ds     1

        .area   _CODE
; u2s: las cifras de DEHL en (iy) (iy avanza); A = cuantas
u2s:    push    ix
        ld      ix,#p10t+36
        ld      b,#10
        ld      c,#0
us1:    xor     a
        ld      (udg),a
us2:    ld      a,l
        sub     0(ix)
        ld      l,a
        ld      a,h
        sbc     a,1(ix)
        ld      h,a
        ld      a,e
        sbc     a,2(ix)
        ld      e,a
        ld      a,d
        sbc     a,3(ix)
        ld      d,a
        jr      c,us3
        ld      a,(udg)
        inc     a
        ld      (udg),a
        jr      us2
us3:    ld      a,l
        add     a,0(ix)
        ld      l,a
        ld      a,h
        adc     a,1(ix)
        ld      h,a
        ld      a,e
        adc     a,2(ix)
        ld      e,a
        ld      a,d
        adc     a,3(ix)
        ld      d,a
        ld      a,(udg)
        or      c
        jr      nz,us4
        ld      a,b
        dec     a
        jr      nz,us5          ; un cero de adelante no va (salvo el ultimo)
us4:    ld      a,(udg)
        add     a,#'0'
        ld      0(iy),a
        inc     iy
        inc     c
us5:    dec     ix
        dec     ix
        dec     ix
        dec     ix
        djnz    us1
        ld      a,c
        pop     ix
        ret

; uint8_t utoa_(uint32_t u, char *o): cifras de u en o (sin 0 al final)
_utoa_::
        push    iy
        ld      hl,#4
        add     hl,sp
        ld      c,(hl)
        inc     hl
        ld      b,(hl)
        inc     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      a,(hl)
        inc     hl
        ld      h,(hl)
        ld      l,a
        push    hl
        pop     iy
        ld      l,c
        ld      h,b
        call    u2s
        ld      l,a
        pop     iy
        ret

; cpyb: B bytes de (de) a (hl); zeros: B '0' en (hl)
cpyb:   ld      a,(de)
        ld      (hl),a
        inc     hl
        inc     de
        djnz    cpyb
        ret
zeros:  ld      (hl),#'0'
        inc     hl
        djnz    zeros
        ret

; uint8_t nplain(char *o, const num *x, int8_t dec, uint8_t max)
; x en decimal comun; dec >= 0: con dec decimales. Largo, o 0 si pasa de max
_nplain::
        push    ix
        push    iy
        ld      hl,#6
        add     hl,sp
        call    farg
        ld      a,(hl)
        ld      (fdec),a
        inc     hl
        ld      a,(hl)
        ld      (fmax),a
        call    plain
        ld      l,a
        pop     iy
        pop     ix
        ret
; farg: (hl) = o, x -> fo, fx; hl queda en el argumento siguiente
farg:   ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      (fo),de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        push    hl
        ex      de,hl
        ld      de,#fx
        ld      bc,#5
        ldir
        pop     hl
        ret
; plain: fx, fdec, fmax -> (fo); A = largo o 0
plain:  ld      ix,#fx
        call    ldmag
        ld      a,c
        ld      (fneg),a
        ld      iy,#fdg
        call    u2s
        ld      (fnd),a
        ld      a,(fx+4)
        ld      b,a
        bit     7,b
        jr      nz,pl1
        ld      a,(fnd)         ; e >= 0: ip = nd + e
        add     a,b
        ld      (fip),a
        xor     a
        ld      (ffp),a
        jr      pl3
pl1:    ld      a,b             ; e < 0: k = -e decimales
        neg
        ld      c,a
        ld      (ffp),a
        ld      a,(fnd)
        cp      c
        jr      c,pl2
        jr      z,pl2
        sub     c
        ld      (fip),a
        jr      pl3
pl2:    ld      a,#1
        ld      (fip),a
pl3:    ld      a,(fdec)
        bit     7,a
        jr      nz,pl4
        ld      c,a
        ld      a,(ffp)
        cp      c
        jr      nc,pl4
        ld      a,c
        ld      (ffp),a
pl4:    ld      a,(ffp)
        or      a
        jr      z,pl5
        inc     a
pl5:    ld      c,a
        ld      a,(fip)
        add     a,c
        jp      c,plbig
        ld      c,a
        ld      a,(fneg)
        add     a,c
        ld      (flen),a
        ld      c,a
        ld      a,(fmax)
        cp      c
        jp      c,plbig
        ld      hl,(fo)
        ld      a,(fneg)
        or      a
        jr      z,pw1
        ld      (hl),#'-'
        inc     hl
pw1:    ld      a,(fx+4)
        bit     7,a
        jr      nz,pw3
        ld      de,#fdg         ; entero: las cifras y e ceros
        ld      a,(fnd)
        ld      b,a
        call    cpyb
        ld      a,(fx+4)
        or      a
        jr      z,pw5
        ld      b,a
        call    zeros
        jr      pw5
pw3:    neg
        ld      c,a
        ld      a,(fnd)
        cp      c
        jr      c,pw4
        jr      z,pw4
        ld      a,(fip)
        ld      b,a
        ld      de,#fdg
        call    cpyb
        jr      pw5
pw4:    ld      (hl),#'0'
        inc     hl
pw5:    ld      a,(ffp)
        or      a
        jr      z,pwend
        ld      (hl),#'.'
        inc     hl
        ld      a,(fx+4)
        bit     7,a
        jr      z,pw8
        neg
        ld      c,a             ; k cifras decimales del numero
        ld      a,(fnd)
        cp      c
        jr      c,pw6
        jr      z,pw6
        ld      a,(fip)
        ld      e,a
        ld      d,#0
        push    hl
        ld      hl,#fdg
        add     hl,de
        ex      de,hl
        pop     hl
        ld      b,c
        call    cpyb
        jr      pw7
pw6:    ld      a,(fnd)
        ld      b,a
        ld      a,c
        sub     b
        jr      z,pw6a
        ld      b,a
        call    zeros
pw6a:   ld      a,(fnd)
        ld      b,a
        ld      de,#fdg
        call    cpyb
pw7:    ld      a,(ffp)
        sub     c
        jr      z,pwend
        jr      c,pwend
        ld      b,a
        call    zeros
        jr      pwend
pw8:    ld      a,(ffp)
        ld      b,a
        call    zeros
pwend:  ld      (hl),#0
        ld      a,(flen)
        ret
plbig:  xor     a
        ret

; uint8_t nsci(char *o, const num *x, uint8_t max): d.dddE+nn; 0 si no cabe
_nsci::
        push    ix
        push    iy
        ld      hl,#6
        add     hl,sp
        call    farg
        ld      a,(hl)
        ld      (fmax),a
        call    sci
        ld      l,a
        pop     iy
        pop     ix
        ret
; exp10: A = cifras - 1 + e del num en (ix)
exp10:  call    ldmag
        call    ndigr
        dec     a
        add     a,4(ix)
        ret
sci:    ld      ix,#fx
        call    ldmag
        ld      a,c
        ld      (fneg),a
        call    exp10           ; ex
        ld      c,#3            ; largo de E+n
        cp      #10
        jr      c,sc0
        cp      #-9
        jr      nc,sc0
        inc     c               ; E+nn
sc0:    ld      b,a             ; b = ex
        ld      a,(fneg)
        add     a,c
        inc     a
        ld      e,a             ; lo minimo
        ld      a,(fmax)
        cp      e
        jp      c,plbig
        ld      a,(fneg)        ; md = max - neg - el
        ld      e,a
        ld      a,(fmax)
        sub     e
        sub     c
        cp      #3
        jr      c,sc1
        dec     a
        jr      sc2
sc1:    ld      a,#1
sc2:    dec     a               ; nround(fy, fx, md - 1 - ex)
        sub     b
        push    af
        inc     sp
        ld      hl,#fx
        push    hl
        ld      hl,#fy
        push    hl
        call    _nround
        pop     af
        pop     af
        inc     sp
        ld      ix,#fy
        call    exp10
        ld      (flen),a        ; ex nuevo
        call    ldmag
        ld      iy,#fdg
        call    u2s
        ld      b,a             ; nd
        ld      hl,(fo)
        ld      a,(fneg)
        or      a
        jr      z,sc3
        ld      (hl),#'-'
        inc     hl
sc3:    ld      de,#fdg
        ld      a,(de)
        ld      (hl),a
        inc     hl
        inc     de
        dec     b
        jr      z,sc4
        ld      (hl),#'.'
        inc     hl
        call    cpyb
sc4:    ld      (hl),#'E'
        inc     hl
        ld      a,(flen)
        ld      c,#'+'
        bit     7,a
        jr      z,sc5
        neg
        ld      c,#'-'
sc5:    ld      (hl),c
        inc     hl
        ld      c,#'0'-1
sc6:    inc     c
        sub     #10
        jr      nc,sc6
        add     a,#10+'0'
        ld      b,a
        ld      a,c
        cp      #'0'
        jr      z,sc7
        ld      (hl),c
        inc     hl
sc7:    ld      (hl),b
        inc     hl
        ld      (hl),#0
        ld      de,(fo)
        or      a
        sbc     hl,de
        ld      a,l
        ret

; const char *pnum(const char *s, num *x): numero escrito -> x; devuelve lo que sigue
_pnum::
        push    ix
        ld      hl,#4
        add     hl,sp
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      a,(hl)
        inc     hl
        ld      h,(hl)
        ld      l,a
        ld      (rptr),hl
        push    de
        pop     ix              ; ix = s
        ld      hl,#0
        ld      (nexp),hl
        xor     a
        ld      (fnd),a
        ld      (pdot),a
        ld      (nneg),a
        ld      d,a
        ld      e,a             ; DEHL = u
pn1:    ld      a,0(ix)
        cp      #'.'
        jr      nz,pn2
        ld      a,(pdot)
        or      a
        jr      nz,pn5
        ld      a,1(ix)
        cp      #'.'
        jr      z,pn5
        ld      a,#1
        ld      (pdot),a
        inc     ix
        jr      pn1
pn2:    sub     #'0'
        jr      c,pn5
        cp      #10
        jr      nc,pn5
        ld      c,a
        ld      a,(fnd)
        cp      #9
        jr      nc,pn4
        push    bc              ; u = u * 10 + cifra
        call    mul10
        pop     bc
        ld      a,l
        add     a,c
        ld      l,a
        jr      nc,pn3
        inc     h
        jr      nz,pn3
        inc     de
pn3:    ld      a,d
        or      e
        or      h
        or      l
        jr      z,pn3a
        ld      a,(fnd)
        inc     a
        ld      (fnd),a
pn3a:   ld      a,(pdot)
        or      a
        jr      z,pn4b
        push    hl
        ld      hl,(nexp)
        dec     hl
        ld      (nexp),hl
        pop     hl
        jr      pn4b
pn4:    ld      a,(pdot)        ; mas de 9 cifras: sin decimales cuentan
        or      a
        call    z,incexp
pn4b:   inc     ix
        jr      pn1
pn5:    ld      a,0(ix)         ; exponente
        cp      #'E'
        jr      nz,pn9
        ld      a,1(ix)
        ld      c,#0
        cp      #'+'
        jr      z,pn6
        cp      #'-'
        jr      nz,pn7
        inc     c
pn6:    ld      a,2(ix)
        sub     #'0'
        cp      #10
        jr      nc,pn9
        inc     ix
        jr      pn7a
pn7:    sub     #'0'
        cp      #10
        jr      nc,pn9
pn7a:   inc     ix              ; ix en la primera cifra
        push    hl
        push    de
        ld      b,#0            ; ex (hasta 200)
pn8:    ld      a,0(ix)
        sub     #'0'
        jr      c,pn8b
        cp      #10
        jr      nc,pn8b
        ld      e,a
        ld      a,b
        cp      #200/10
        jr      nc,pn8a
        add     a,a
        ld      b,a
        add     a,a
        add     a,a
        add     a,b
        add     a,e
        ld      b,a
pn8a:   inc     ix
        jr      pn8
pn8b:   ld      e,b
        ld      d,#0
        ld      a,c
        or      a
        jr      z,pn8c
        ld      hl,#0
        or      a
        sbc     hl,de
        ex      de,hl
pn8c:   ld      hl,(nexp)
        add     hl,de
        ld      (nexp),hl
        pop     de
        pop     hl
pn9:    xor     a
        ld      (_nerr),a
        push    ix
        call    norm
        pop     hl
        pop     ix
        ret

; ------------------------------------------------------------------ referencias y formulas
; tokens (como en zcalc.c): 0 fin, 1 NUM m(4) e(1), 2 REF cf r, 3 RNG cf1 r1 cf2 r2,
; 4 FN id, 5 <=, 6 >=, 7 <>, 8 I8 n; cf = columna (bits 0-5) y $ (6 columna, 7 fila)
TK_NUM  = 1
TK_REF  = 2
TK_RNG  = 3
TK_FN   = 4
TK_LE   = 5
TK_GE   = 6
TK_NE   = 7
TK_I8   = 8
TK_STR  = 9                     ; texto: n y n letras
TK_NM   = 10                    ; nombre: id (sigue a la referencia o el rango que nombra)
NMSZ    = 15                    ; nms[]: nombre (9) y la referencia (6) en zcalc.c
NCOL    = 63
NROW    = 254
NFN     = 55                    ; funciones (igual que en zcalc.c)
F_AVG   = 1

        .area   _DATA
tko:    .ds     2
tks:    .ds     2
tnm:    .ds     10
_dknm:: .ds     1               ; dtok: id + 1 del nombre que sale como coordenadas
tx:     .ds     5
rc1:    .ds     2
rf1:    .ds     1
dkm:    .ds     1
dkx:    .ds     1
tsl:    .ds     2

        .area   _CODE
; nombres de las funciones en el orden de zcalc.c; despues los otros nombres
fntab:  .ascii  "SUM"
        .db     0
        .ascii  "AVG"
        .db     0
        .ascii  "MIN"
        .db     0
        .ascii  "MAX"
        .db     0
        .ascii  "COUNT"
        .db     0
        .ascii  "LOOKUP"
        .db     0
        .ascii  "ABS"
        .db     0
        .ascii  "INT"
        .db     0
        .ascii  "ROUND"
        .db     0
        .ascii  "SQRT"
        .db     0
        .ascii  "MOD"
        .db     0
        .ascii  "IF"
        .db     0
        .ascii  "AND"
        .db     0
        .ascii  "OR"
        .db     0
        .ascii  "NOT"
        .db     0
        .ascii  "PI"
        .db     0
        .ascii  "NA"
        .db     0
        .ascii  "ERROR"
        .db     0
        .ascii  "ISNA"
        .db     0
        .ascii  "ISERROR"
        .db     0
        .ascii  "PMT"
        .db     0
        .ascii  "PV"
        .db     0
        .ascii  "FV"
        .db     0
        .ascii  "NPV"
        .db     0
        .ascii  "IRR"
        .db     0
        .ascii  "DATE"
        .db     0
        .ascii  "TODAY"
        .db     0
        .ascii  "NOW"
        .db     0
        .ascii  "YEAR"
        .db     0
        .ascii  "MONTH"
        .db     0
        .ascii  "DAY"
        .db     0
        .ascii  "SIN"
        .db     0
        .ascii  "COS"
        .db     0
        .ascii  "TAN"
        .db     0
        .ascii  "ATAN"
        .db     0
        .ascii  "LN"
        .db     0
        .ascii  "EXP"
        .db     0
        .ascii  "LOG"
        .db     0
        .ascii  "LEFT"
        .db     0
        .ascii  "RIGHT"
        .db     0
        .ascii  "MID"
        .db     0
        .ascii  "LEN"
        .db     0
        .ascii  "UPPER"
        .db     0
        .ascii  "LOWER"
        .db     0
        .ascii  "PROPER"
        .db     0
        .ascii  "TRIM"
        .db     0
        .ascii  "VALUE"
        .db     0
        .ascii  "STRING"
        .db     0
        .ascii  "FIND"
        .db     0
        .ascii  "REPEAT"
        .db     0
        .ascii  "CHAR"
        .db     0
        .ascii  "CODE"
        .db     0
        .ascii  "EXACT"
        .db     0
        .ascii  "ISSTR"
        .db     0
        .ascii  "ISNUM"
        .db     0
        .ascii  "AVERAGE"       ; = AVG
        .db     0
        .db     0
opch:   .ascii  "+-*/^(),=<>&"

; isupa / isdga: carry si A no es A-Z / 0-9
isupa:  cp      #'A'
        ret     c
        cp      #'Z'+1
        ccf
        ret
isdga:  cp      #'0'
        ret     c
        cp      #'9'+1
        ccf
        ret

; prf: referencia en (ix) -> C columna, B fila, E $ (bit 0 columna, 1 fila);
; sin carry si esta bien (ix avanza), con carry si no (ix igual)
prf:    push    ix
        ld      e,#0
        ld      a,0(ix)
        cp      #'$'
        jr      nz,pf1
        set     0,e
        inc     ix
pf1:    ld      a,0(ix)
        call    isupa
        jr      c,pfno
        sub     #'A'-1
        ld      c,a
        inc     ix
        ld      a,0(ix)
        call    isupa
        jr      c,pf2
        ld      a,c
        cp      #3
        jr      nc,pfno
        ld      a,0(ix)
        sub     #'A'-1
        ld      d,a
        ld      a,c             ; c * 26 + d
        add     a,a
        ld      l,a
        add     a,a
        add     a,a
        ld      h,a
        add     a,a
        add     a,h
        add     a,l
        add     a,d
        ld      c,a
        inc     ix
pf2:    ld      a,c
        cp      #NCOL+1
        jr      nc,pfno
        ld      a,0(ix)
        cp      #'$'
        jr      nz,pf3
        set     1,e
        inc     ix
pf3:    ld      a,0(ix)
        call    isdga
        jr      c,pfno
        ld      hl,#0
pf4:    ld      a,0(ix)
        sub     #'0'
        jr      c,pf5
        cp      #10
        jr      nc,pf5
        push    de
        ld      d,h
        ld      e,l
        add     hl,hl
        add     hl,hl
        add     hl,de
        add     hl,hl
        ld      e,a
        ld      d,#0
        add     hl,de
        pop     de
        ld      a,h
        or      a
        jr      nz,pfno
        ld      a,l
        cp      #NROW+1
        jr      nc,pfno
        inc     ix
        jr      pf4
pf5:    ld      a,l
        or      a
        jr      z,pfno
        ld      b,a
        ld      a,0(ix)
        call    isupa
        jr      nc,pfno
        pop     af
        or      a
        ret
pfno:   pop     ix
        scf
        ret

; uint8_t pref(const char **ps, uint8_t *c, uint8_t *r, uint8_t *fl)
_pref::
        push    ix
        ld      hl,#4
        add     hl,sp
        ld      (rc1),hl        ; los argumentos
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl
        ld      a,(hl)
        inc     hl
        ld      h,(hl)
        ld      l,a
        push    hl
        pop     ix
        call    prf
        jr      c,pr9
        ld      a,e
        ld      (rf1),a
        ld      hl,(rc1)
        ld      e,(hl)          ; *ps = lo que sigue
        inc     hl
        ld      d,(hl)
        inc     hl
        push    hl
        ex      de,hl
        push    ix
        pop     de
        ld      (hl),e
        inc     hl
        ld      (hl),d
        pop     hl
        ld      a,c
        call    pst
        ld      a,b
        call    pst
        ld      a,(rf1)
        call    pst
        ld      l,#1
        pop     ix
        ret
pst:    ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      (de),a
        ret
pr9:    ld      l,#0
        pop     ix
        ret

; cnm: letras de la columna A en (hl)
cnm:    cp      #27
        jr      nc,cn1
        add     a,#'A'-1
        ld      (hl),a
        inc     hl
        ret
cn1:    dec     a
        ld      b,#'A'-2
cn2:    inc     b
        sub     #26
        jr      nc,cn2
        add     a,#26+'A'
        ld      (hl),b
        inc     hl
        ld      (hl),a
        inc     hl
        ret
; uint8_t colname(char *o, uint8_t c)
_colname::
        ld      hl,#2
        add     hl,sp
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      a,(hl)
        ex      de,hl
        push    hl
        call    cnm
        ld      (hl),#0
        pop     de
        or      a
        sbc     hl,de
        ret

; rfn: referencia C columna, B fila, E $ en (hl); hl avanza (sin 0)
rfn:    ld      a,c
        or      a
        jr      nz,rf1x
        ld      (hl),#'#'
        inc     hl
        ld      (hl),#'R'
        inc     hl
        ld      (hl),#'E'
        inc     hl
        ld      (hl),#'F'
        inc     hl
        ret
rf1x:   bit     0,e
        jr      z,rf2
        ld      (hl),#'$'
        inc     hl
rf2:    push    bc
        push    de
        ld      a,c
        call    cnm
        pop     de
        pop     bc
        bit     1,e
        jr      z,rf3
        ld      (hl),#'$'
        inc     hl
rf3:    push    iy
        push    hl
        pop     iy
        ld      l,b
        ld      h,#0
        ld      de,#0
        call    u2s
        push    iy
        pop     hl
        pop     iy
        ret
; uint8_t refname(char *o, uint8_t c, uint8_t r, uint8_t fl)
_refname::
        ld      hl,#2
        add     hl,sp
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      c,(hl)
        inc     hl
        ld      b,(hl)
        inc     hl
        ld      a,(hl)
        ex      de,hl
        ld      e,a
        push    hl
        call    rfn
        ld      (hl),#0
        pop     de
        or      a
        sbc     hl,de
        ret

; tput: A a la formula que se compila
tput:   push    hl
        ld      hl,(tko)
        ld      (hl),a
        inc     hl
        ld      (tko),hl
        pop     hl
        ret
; uint8_t tok(const char *s, uint8_t *o): compila s (en mayusculas); largo o 0
_tok::
        push    ix
        push    iy
        ld      hl,#6
        add     hl,sp
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        push    de
        pop     ix
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ld      (tko),de
        ld      (tks),de
        ld      a,0(ix)
        cp      #'='
        jr      nz,tk1
        inc     ix
tk1:    ld      a,0(ix)
        or      a
        jp      z,tkend
        ld      hl,(tko)
        ld      de,(tks)
        or      a
        sbc     hl,de
        ld      a,l
        cp      #152
        jp      nc,tkerr
        ld      a,0(ix)
        cp      #' '
        jr      nz,tk2
        inc     ix
        jr      tk1
tk2:    cp      #'"'
        jp      z,tkstr
        call    isdga
        jp      nc,tknum
        cp      #'.'
        jr      nz,tk3
        ld      a,1(ix)
        call    isdga
        jp      nc,tknum
tk3:    ld      a,0(ix)
        cp      #'$'
        jr      z,tkref
        call    isupa
        jp      c,tk6
tkref:  call    prf
        jp      c,tk5
        ld      a,0(ix)
        cp      #':'
        jr      z,tkr1
        cp      #'.'
        jr      z,tkr1
        ld      a,#TK_REF
        call    tput
        ld      a,e
        rrca
        rrca
        or      c
        call    tput
        ld      a,b
        call    tput
        jr      tk1
tkr1:   inc     ix
        ld      a,0(ix)
        cp      #':'
        jr      z,tkr1
        cp      #'.'
        jr      z,tkr1
        ld      (rc1),bc
        ld      a,e
        ld      (rf1),a
        call    prf
        jp      c,tkerr
        ld      a,(rc1)         ; columnas al reves: cambiarlas con su $
        ld      d,a
        ld      a,c
        cp      d
        jr      nc,tkr2
        ld      (rc1),a
        ld      c,d
        ld      a,(rf1)
        xor     e
        and     #1
        ld      d,a
        ld      a,(rf1)
        xor     d
        ld      (rf1),a
        ld      a,e
        xor     d
        ld      e,a
tkr2:   ld      a,(rc1+1)       ; filas al reves
        ld      d,a
        ld      a,b
        cp      d
        jr      nc,tkr3
        ld      (rc1+1),a
        ld      b,d
        ld      a,(rf1)
        xor     e
        and     #2
        ld      d,a
        ld      a,(rf1)
        xor     d
        ld      (rf1),a
        ld      a,e
        xor     d
        ld      e,a
tkr3:   ld      a,#TK_RNG
        call    tput
        ld      a,(rf1)
        rrca
        rrca
        ld      d,a
        ld      a,(rc1)
        or      d
        call    tput
        ld      a,(rc1+1)
        call    tput
        ld      a,e
        rrca
        rrca
        or      c
        call    tput
        ld      a,b
        call    tput
        jp      tk1
tk5:    ld      a,0(ix)
        cp      #'$'
        jp      z,tkerr
tk6:    ld      a,0(ix)         ; funcion: @NOMBRE o NOMBRE
        cp      #'@'
        jr      nz,tk7
        inc     ix
        jr      tkfn
tk7:    call    isupa
        jr      c,tkop
tkfn:   ld      hl,#tnm
        ld      b,#0
tf1:    ld      a,0(ix)
        call    isupa
        jr      nc,tf1a
        call    isdga
        jr      nc,tf1a
        cp      #'_'
        jr      nz,tf2
tf1a:   ld      a,b
        cp      #8
        jp      nc,tkerr
        ld      a,0(ix)
        ld      (hl),a
        inc     hl
        inc     b
        inc     ix
        jr      tf1
tf2:    ld      (hl),#0
        ld      de,#fntab
        ld      c,#0
tf3:    ld      a,(de)
        or      a
        jp      z,tknam
        ld      hl,#tnm
        push    de
tf4:    ld      a,(de)
        cp      (hl)
        jr      nz,tf5
        or      a
        jr      z,tf6
        inc     de
        inc     hl
        jr      tf4
tf5:    pop     de
tf5a:   ld      a,(de)
        inc     de
        or      a
        jr      nz,tf5a
        inc     c
        jr      tf3
tf6:    pop     de
        ld      a,c
        cp      #NFN
        jr      c,tf7
        ld      a,#F_AVG
tf7:    ld      b,a
        ld      a,#TK_FN
        call    tput
        ld      a,b
        call    tput
        jp      tk1
tkop:   ld      a,0(ix)
        cp      #'<'
        jr      nz,to2
        ld      a,1(ix)
        ld      b,#TK_LE
        cp      #'='
        jr      z,to1
        ld      b,#TK_NE
        cp      #'>'
        jr      z,to1
        jr      to3
to2:    cp      #'>'
        jr      nz,to3
        ld      a,1(ix)
        ld      b,#TK_GE
        cp      #'='
        jr      nz,to3
to1:    ld      a,b
        call    tput
        inc     ix
        inc     ix
        jp      tk1
to3:    ld      a,0(ix)
        ld      hl,#opch
        ld      b,#12
to4:    cp      (hl)
        jr      z,to5
        inc     hl
        djnz    to4
        jp      tkerr
to5:    call    tput
        inc     ix
        jp      tk1
tknum:  push    ix
        pop     hl
        ld      de,#tx
        push    de
        push    hl
        call    _pnum
        pop     af
        pop     af
        push    hl
        pop     ix
        ld      a,(_nerr)
        or      a
        jp      nz,tkerr
        ld      hl,(tx+2)       ; entero de 0 a 255: TK_I8
        ld      a,h
        or      l
        jr      nz,tkn2
        ld      hl,(tx)
        ld      a,h
        or      a
        jr      nz,tkn2
        ld      a,(tx+4)
        or      a
        jr      z,tkn1
        cp      #3
        jr      nc,tkn2
        ld      b,a
tkm:    ld      d,h
        ld      e,l
        add     hl,hl
        add     hl,hl
        add     hl,de
        add     hl,hl
        djnz    tkm
tkn1:   ld      a,h
        or      a
        jr      nz,tkn2
        ld      a,#TK_I8
        call    tput
        ld      a,l
        call    tput
        jp      tk1
tkn2:   ld      a,#TK_NUM
        call    tput
        ld      hl,#tx
        ld      b,#5
tkn3:   ld      a,(hl)
        call    tput
        inc     hl
        djnz    tkn3
        jp      tk1
tknam:  ld      hl,#_nms        ; un nombre de rango
        ld      c,#0
tnm1:   ld      a,(_nnm)
        cp      c
        jp      z,tkerr
        push    hl
        ld      de,#tnm
tnm2:   ld      a,(de)
        cp      (hl)
        jr      nz,tnm3
        inc     de
        inc     hl
        or      a
        jr      nz,tnm2
        pop     hl
        ld      de,#9           ; la referencia y el id
        add     hl,de
        ld      b,#3
        ld      a,(hl)
        cp      #TK_REF
        jr      z,tnm4
        ld      b,#5
tnm4:   ld      a,(hl)
        call    tput
        inc     hl
        djnz    tnm4
        ld      a,#TK_NM
        call    tput
        ld      a,c
        call    tput
        jp      tk1
tnm3:   pop     hl
        ld      de,#NMSZ
        add     hl,de
        inc     c
        jr      tnm1
tkstr:  ld      a,#TK_STR       ; "texto" ("" es una comilla)
        call    tput
        ld      hl,(tko)
        ld      (tsl),hl
        call    tput
        ld      c,#0
        inc     ix
ts1:    ld      a,0(ix)
        or      a
        jp      z,tkerr
        inc     ix
        cp      #'"'
        jr      nz,ts2
        ld      a,0(ix)
        cp      #'"'
        jr      nz,ts3
        inc     ix
ts2:    call    tput
        inc     c
        ld      hl,(tko)
        ld      de,(tks)
        or      a
        sbc     hl,de
        ld      a,l
        cp      #155
        jp      nc,tkerr
        jr      ts1
ts3:    ld      hl,(tsl)
        ld      (hl),c
        jp      tk1
tkend:  xor     a
        call    tput
        ld      hl,(tko)
        ld      de,(tks)
        or      a
        sbc     hl,de
        pop     iy
        pop     ix
        ret
tkerr:  ld      l,#0
        pop     iy
        pop     ix
        ret

; uint8_t dtok(const uint8_t *t, char *o, uint8_t max): la formula como texto
_dtok::
        push    ix
        push    iy
        ld      hl,#6
        add     hl,sp
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        push    de
        pop     ix
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      (tko),de
        ld      (tks),de
        ld      a,(hl)
        ld      (dkx),a
        sub     #24
        jr      nc,dk0
        xor     a
dk0:    ld      (dkm),a
dk1:    ld      a,0(ix)
        or      a
        jp      z,dkend
        ld      hl,(tko)
        ld      de,(tks)
        or      a
        sbc     hl,de
        ld      a,(dkm)
        cp      l
        jp      c,dkend
        jp      z,dkend
        ld      a,0(ix)
        cp      #TK_NUM
        jp      z,dknum
        cp      #TK_I8
        jp      z,dki8
        cp      #TK_REF
        jp      z,dkref
        cp      #TK_RNG
        jp      z,dkrng
        cp      #TK_FN
        jp      z,dkfn
        cp      #TK_STR
        jp      z,dkstr
        ld      bc,#'<'+'='*256
        cp      #TK_LE
        jr      z,dk2
        ld      bc,#'>'+'='*256
        cp      #TK_GE
        jr      z,dk2
        ld      bc,#'<'+'>'*256
        cp      #TK_NE
        jr      z,dk2
        call    tput
        inc     ix
        jr      dk1
dk2:    ld      a,c
        call    tput
        ld      a,b
        call    tput
        inc     ix
        jr      dk1
dknum:  push    ix
        pop     hl
        inc     hl
        ld      de,#fx
        ld      bc,#5
        ldir
        ld      hl,(tko)
        ld      (fo),hl
        ld      a,#0xFF
        ld      (fdec),a
        ld      a,#22
        ld      (fmax),a
        push    ix
        call    plain
        or      a
        jr      nz,dkn1
        call    sci
dkn1:   pop     ix
        ld      e,a
        ld      d,#0
        ld      hl,(tko)
        add     hl,de
        ld      (tko),hl
        ld      de,#6
        add     ix,de
        jp      dk1
dki8:   ld      iy,(tko)
        ld      l,1(ix)
        ld      h,#0
        ld      de,#0
        call    u2s
        ld      (tko),iy
        inc     ix
        inc     ix
        jp      dk1
dkref:  ld      a,3(ix)
        cp      #TK_NM
        jr      nz,dkr0
        ld      de,#3
        jr      dknm
dkr0:   call    dref1
        inc     ix
        inc     ix
        inc     ix
        jp      dk1
dknm:   push    ix              ; DE = largo de la referencia
        add     ix,de
        ld      a,1(ix)         ; el id
        pop     ix
        ld      l,a
        inc     a
        ld      h,#0
        push    hl
        ld      hl,#_dknm       ; dknm = id + 1: las coordenadas en vez del nombre
        cp      (hl)
        pop     hl
        jr      z,dknm0
        ld      b,h
        ld      c,l
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        or      a
        sbc     hl,bc           ; id * 15
        ld      bc,#_nms
        add     hl,bc
dknm3:  ld      a,(hl)
        or      a
        jr      z,dknm2
        call    tput
        inc     hl
        jr      dknm3
dknm0:  push    de
        ld      a,0(ix)
        cp      #TK_REF
        jr      z,dknm0b
        call    dref1
        ld      a,#':'
        call    tput
        inc     ix
        inc     ix
        call    dref1
        dec     ix
        dec     ix
        jr      dknm0a
dknm0b: call    dref1
dknm0a: pop     de
dknm2:  add     ix,de
        inc     ix
        inc     ix
        jp      dk1
dkrng:  ld      a,5(ix)
        cp      #TK_NM
        jr      nz,dkrg0
        ld      de,#5
        jp      dknm
dkrg0:  call    dref1
        ld      a,1(ix)
        and     #63
        jr      z,dkr1
        ld      a,#':'
        call    tput
        inc     ix
        inc     ix
        call    dref1
        dec     ix
        dec     ix
dkr1:   ld      de,#5
        add     ix,de
        jp      dk1
; dref1: la referencia en 1(ix) 2(ix)
dref1:  ld      a,1(ix)
        ld      c,a
        rlca
        rlca
        and     #3
        ld      e,a
        ld      a,c
        and     #63
        ld      c,a
        ld      b,2(ix)
        ld      hl,(tko)
        call    rfn
        ld      (tko),hl
        ret
dkfn:   ld      a,#'@'
        call    tput
        ld      b,1(ix)
        ld      hl,#fntab
        inc     b
dkf1:   dec     b
        jr      z,dkf3
dkf2:   ld      a,(hl)
        inc     hl
        or      a
        jr      nz,dkf2
        jr      dkf1
dkf3:   ld      a,(hl)
        or      a
        jr      z,dkf4
        call    tput
        inc     hl
        jr      dkf3
dkf4:   inc     ix
        inc     ix
        jp      dk1
dkstr:  ld      a,#'"'
        call    tput
        ld      b,1(ix)
        push    ix
        pop     hl
        inc     hl
        inc     hl
        ld      a,b
        or      a
        jr      z,dks3
dks1:   push    hl
        ld      hl,(tko)
        ld      de,(tks)
        or      a
        sbc     hl,de
        ld      a,(dkx)
        sub     #3
        cp      l
        pop     hl
        jr      c,dks3
        jr      z,dks3
        ld      a,(hl)
        cp      #'"'
        call    z,tput
        call    tput
        inc     hl
        djnz    dks1
dks3:   ld      a,#'"'
        call    tput
        ld      e,1(ix)
        ld      d,#0
        inc     de
        inc     de
        add     ix,de
        jp      dk1
dkend:  xor     a
        ld      hl,(tko)
        ld      (hl),a
        ld      de,(tks)
        or      a
        sbc     hl,de
        pop     iy
        pop     ix
        ret

; ------------------------------------------------------------------ calculo
; val: t (0 numero, 1 ERROR, 2 NA) y el num (5 bytes). Las rutinas de evaluacion
; escriben en el val de (ix) y guardan iy. Celda: nx(2) c r fl f n, d en +7:
; valor en +7, generacion en +12, formula en +13.
V_ERR   = 1
V_NA    = 2
V_STR   = 3                     ; texto: puntero (1-2) y largo (3)
K_NUM   = 3
K_FRM   = 4
F_COUNT = 4
F_MIN   = 2
F_MAX   = 3
F_LOOKUP = 5
F_ABS   = 6
F_INT   = 7
F_ROUND = 8
F_SQRT  = 9
F_MOD   = 10
F_IF    = 11
F_AND   = 12
F_OR    = 13
F_NOT   = 14
F_PI    = 15
F_NA    = 16
F_ISNA  = 18
F_ISERR = 19
F_NPV   = 23
F_IRR   = 24
F_TODAY = 26
F_NOW   = 27
F_CF    = 20                    ; de aqui en adelante, cfunc
F_LEFT  = 38                    ; de aqui en adelante, las de texto (fstr)
F_ISSTR = 53
F_ISNUM = 54

        .area   _DATA
_tp::   .ds     2               ; lo que sigue en la formula
_synerr:: .ds   1
_chk::  .ds     1               ; solo revisar la sintaxis
_gen::  .ds     1
_depth:: .ds    1
_again:: .ds    1
_circ:: .ds     1
pdep:   .ds     1               ; parentesis anidados
rpass:  .ds     1
oparg:  .ds     6               ; r, a, b para las rutinas de num
nsbt:   .ds     5
cmps:   .ds     5

        .area   _CODE
;              SUM AVG MIN MAX CNT LKP ABS INT RND SQR MOD IF AND OR NOT PI NA ERR ISNA ISERR
fmint:  .db     1,  1,  1,  1,  1,  2,  1,  1,  2,  1,  2,  3, 1,  1, 1,  0, 0, 0,  1,   1
;               PMT PV FV NPV IRR DATE TODAY NOW YEAR MONTH DAY SIN COS TAN ATAN LN EXP LOG
        .db     3,  3, 3, 2,  2,  3,   0,    0,  1,   1,    1,  1,  1,  1,  1,   1, 1,  1
;               LEFT RIGHT MID LEN UPPER LOWER PROPER TRIM VALUE STRING FIND REPEAT CHAR CODE EXACT ISSTR ISNUM
        .db     2,   2,    3,  1,  1,    1,    1,     1,   1,    1,     2,   2,     1,   1,   2,    1,    1
fmaxt:  .db     9,  9,  9,  9,  9,  2,  1,  1,  2,  1,  2,  3, 9,  9, 1,  0, 0, 0,  1,   1
        .db     3,  3, 3, 9,  9,  3,   0,    0,  1,   1,    1,  1,  1,  1,  1,   1, 1,  1
        .db     2,   2,    3,  1,  1,    1,    1,     1,   1,    2,     3,   2,     1,   1,   2,    1,    1

; xop: la rutina en DE (_naddi, _nmuli, _ndivi) con oparg
xop:    push    ix
        push    iy
        ld      hl,#xop1
        push    hl
        push    de
        ld      hl,#oparg
        ret
xop1:   pop     iy
        pop     ix
        ret
; nsubx: oparg r = a - b
nsubx:  ld      hl,(oparg+4)
        ld      de,#nsbt
        ld      bc,#5
        ldir
        ld      hl,#nsbt
        ld      b,#4
        or      a
nsx1:   ld      a,#0
        sbc     a,(hl)
        ld      (hl),a
        inc     hl
        djnz    nsx1
        ld      hl,#nsbt
        ld      (oparg+4),hl
        ld      de,#_naddi
        jr      xop
; nsign: A = 0 cero, 1 positivo, 2 negativo del num en (hl)
nsign:  push    hl
        call    iszero
        pop     hl
        ld      a,#0
        ret     z
        inc     hl
        inc     hl
        inc     hl
        bit     7,(hl)
        ld      a,#1
        ret     z
        inc     a
        ret

zerov:  xor     a
        ld      0(ix),a
        ld      1(ix),a
        ld      2(ix),a
        ld      3(ix),a
        ld      4(ix),a
        ld      5(ix),a
        ret
; setvi: v = HL (entero sin signo)
setvi:  ld      0(ix),#0
        push    ix
        pop     de
        inc     de
        ld      (rptr),de
        push    hl
        ld      hl,#0
        ld      (nexp),hl
        pop     hl
        xor     a
        ld      (nneg),a
        ld      d,a
        ld      e,a
        jp      norm
negv:   xor     a
        sub     1(ix)
        ld      1(ix),a
        ld      a,#0
        sbc     a,2(ix)
        ld      2(ix),a
        ld      a,#0
        sbc     a,3(ix)
        ld      3(ix),a
        ld      a,#0
        sbc     a,4(ix)
        ld      4(ix),a
        ret
synx:   ld      a,#1
        ld      (_synerr),a
        ret

; ffind: C columna, B fila -> HL celda o 0
ffind:  ld      a,c
        add     a,a
        add     a,a
        ld      l,a
        add     a,a
        add     a,l
        add     a,c
        add     a,b
        and     #127
        add     a,a
        ld      l,a
        ld      h,#0
        ld      de,#_ht
        add     hl,de
ff1:    ld      a,(hl)
        inc     hl
        ld      h,(hl)
        ld      l,a
        or      h
        ret     z
        push    hl
        inc     hl
        inc     hl
        ld      a,(hl)
        cp      c
        jr      nz,ff2
        inc     hl
        ld      a,(hl)
        cp      b
        jr      nz,ff2
        pop     hl
        ret
ff2:    pop     hl
        jr      ff1
; cell *find(uint8_t c, uint8_t r)
_find::
        ld      hl,#2
        add     hl,sp
        ld      c,(hl)
        inc     hl
        ld      b,(hl)
        jr      ffind

; evbin: (ix) = (ix) op (iy); A = op
evbin:  ld      c,a
        cp      #'&'
        jp      z,evcat
        ld      a,0(ix)
        cp      #V_STR
        jr      nz,ebs1
        ld      a,0(iy)
        cp      #V_STR
        jr      nz,ebs0
        ld      a,c             ; dos textos: se comparan
        call    iscmp
        jp      z,evscmp
ebs0:   call    zerov           ; un texto en una cuenta vale 0
ebs1:   ld      a,0(iy)
        cp      #V_STR
        jr      nz,ebs2
        xor     a
        ld      0(iy),a
        ld      1(iy),a
        ld      2(iy),a
        ld      3(iy),a
        ld      4(iy),a
        ld      5(iy),a
ebs2:   ld      a,0(ix)
        or      0(iy)
        jr      z,eb1
        ld      a,0(ix)
        cp      #V_ERR
        jr      z,eb0
        ld      a,0(iy)
        cp      #V_ERR
        jr      z,eb0
        ld      0(ix),#V_NA
        ret
eb0:    ld      0(ix),#V_ERR
        ret
eb1:    xor     a
        ld      (_nerr),a
        push    ix
        pop     hl
        inc     hl
        ld      (oparg),hl
        ld      (oparg+2),hl
        push    iy
        pop     hl
        inc     hl
        ld      (oparg+4),hl
        ld      a,c
        ld      de,#_naddi
        cp      #'+'
        jr      z,eb2
        ld      de,#_nmuli
        cp      #'*'
        jr      z,eb2
        ld      de,#_ndivi
        cp      #'/'
        jr      z,eb2
        cp      #'-'
        jr      z,ebsub
        cp      #'^'
        jr      z,ebpow
        push    bc              ; comparacion: el signo de a - b
        call    nsubx
        pop     bc
        ld      hl,(oparg)
        call    nsign
ecmp:   ld      d,a
        ld      a,c
        cp      #'='
        jr      nz,ec2
        ld      a,d
        or      a
        jr      z,ect
        jr      ecf
ec2:    cp      #TK_NE
        jr      nz,ec3
        ld      a,d
        or      a
        jr      nz,ect
        jr      ecf
ec3:    cp      #'<'
        jr      nz,ec4
        ld      a,d
        cp      #2
        jr      z,ect
        jr      ecf
ec4:    cp      #'>'
        jr      nz,ec5
        ld      a,d
        cp      #1
        jr      z,ect
        jr      ecf
ec5:    cp      #TK_LE
        jr      nz,ec6
        ld      a,d
        cp      #1
        jr      nz,ect
        jr      ecf
ec6:    ld      a,d             ; >=
        cp      #2
        jr      nz,ect
ecf:    ld      hl,#0
        jp      setvi
ect:    ld      hl,#1
        jp      setvi
eb2:    call    xop
eb3:    ld      a,(_nerr)
        or      a
        ret     z
        ld      0(ix),#V_ERR
        ret
ebsub:  call    nsubx
        jr      eb3
ebpow:  push    ix
        push    iy
        ld      hl,(oparg+4)
        push    hl
        ld      hl,(oparg+2)
        push    hl
        ld      hl,(oparg)
        push    hl
        call    _npow
        pop     af
        pop     af
        pop     af
        pop     iy
        pop     ix
        jr      eb3

; rhs: el operando derecho con la rutina DE en un val temporal; A = op
rhs:    push    iy
        push    af
        ld      hl,#-6
        add     hl,sp
        ld      sp,hl
        push    ix
        push    hl
        pop     ix
        call    jpde
        push    ix
        pop     iy
        pop     ix
        ld      hl,#7
        add     hl,sp
        ld      a,(hl)
        call    evbin
        ld      hl,#6
        add     hl,sp
        ld      sp,hl
        pop     af
        pop     iy
        ret
jpde:   push    de
        ret

ev_expr: call   ev_cat
        ld      hl,(_tp)
        ld      a,(hl)
        cp      #'='
        jr      z,ex1
        cp      #'<'
        jr      z,ex1
        cp      #'>'
        jr      z,ex1
        cp      #TK_LE
        jr      z,ex1
        cp      #TK_GE
        jr      z,ex1
        cp      #TK_NE
        ret     nz
ex1:    inc     hl
        ld      (_tp),hl
        ld      de,#ev_cat
        jp      rhs
ev_cat: call    ev_sum          ; & une textos
ecat1:  ld      hl,(_tp)
        ld      a,(hl)
        cp      #'&'
        ret     nz
        inc     hl
        ld      (_tp),hl
        ld      de,#ev_sum
        call    rhs
        jr      ecat1
ev_sum: call    ev_term
es1:    ld      hl,(_tp)
        ld      a,(hl)
        cp      #'+'
        jr      z,es2
        cp      #'-'
        ret     nz
es2:    inc     hl
        ld      (_tp),hl
        ld      de,#ev_term
        call    rhs
        jr      es1
ev_term: call   ev_una
et1:    ld      hl,(_tp)
        ld      a,(hl)
        cp      #'*'
        jr      z,et2
        cp      #'/'
        ret     nz
et2:    inc     hl
        ld      (_tp),hl
        ld      de,#ev_una
        call    rhs
        jr      et1
ev_una: ld      hl,(_tp)
        ld      a,(hl)
        cp      #'-'
        jr      nz,eu1
        inc     hl
        ld      (_tp),hl
        call    ev_una
        ld      a,0(ix)
        or      a
        ret     nz
        jp      negv
eu1:    cp      #'+'
        jr      nz,ev_pw
        inc     hl
        ld      (_tp),hl
        jr      ev_una
ev_pw:  call    ev_prim
        ld      hl,(_tp)
        ld      a,(hl)
        cp      #'^'
        ret     nz
        inc     hl
        ld      (_tp),hl
        ld      de,#ev_una
        jp      rhs
ev_prim: call   zerov
        ld      hl,(_tp)
        ld      a,(hl)
        inc     hl
        cp      #TK_NUM
        jr      nz,ep1
        push    ix
        pop     de
        inc     de
        ld      bc,#5
        ldir
        ld      (_tp),hl
        ret
ep1:    cp      #TK_I8
        jr      nz,ep1s
        ld      a,(hl)
        inc     hl
        ld      (_tp),hl
        ld      l,a
        ld      h,#0
        jp      setvi
ep1s:   cp      #TK_STR
        jr      nz,ep2
        ld      0(ix),#V_STR
        ld      c,(hl)
        inc     hl
        ld      1(ix),l
        ld      2(ix),h
        ld      3(ix),c
        ld      b,#0
        add     hl,bc
        ld      (_tp),hl
        ret
ep2:    cp      #TK_REF
        jr      nz,ep3
        ld      a,(hl)
        and     #63
        ld      c,a
        inc     hl
        ld      b,(hl)
        inc     hl
        call    sknm
        ld      (_tp),hl
        jr      refval
ep3:    cp      #TK_FN
        jr      nz,ep4
        ld      a,(hl)
        inc     hl
        ld      (_tp),hl
        jp      ev_func
ep4:    cp      #'('
        jr      nz,ep6
        ld      (_tp),hl
        ld      a,(pdep)
        cp      #24
        jp      nc,synx
        inc     a
        ld      (pdep),a
        call    ev_expr
        ld      hl,#pdep
        dec     (hl)
        ld      hl,(_tp)
        ld      a,(hl)
        cp      #')'
        jp      nz,synx
        inc     hl
        ld      (_tp),hl
        ret
ep6:    or      a
        jp      z,synx
        ld      (_tp),hl
        jp      synx

; sknm: salta el nombre que sigue a una referencia o un rango (HL)
sknm:   ld      a,(hl)
        cp      #TK_NM
        ret     nz
        inc     hl
        inc     hl
        ret
; refval: C columna (0 = #REF), B fila -> (ix)
refval: ld      a,c
        or      a
        jr      nz,rv1
        ld      0(ix),#V_ERR
        ret
rv1:    ld      a,(_chk)
        or      a
        ret     nz
        call    ffind
; cellv: HL celda -> (ix); A = 1 si tiene valor (vacia o texto: 0)
cellv:  ld      a,h
        or      l
        ret     z
        push    iy
        push    hl
        pop     iy
        ld      a,4(iy)
        and     #7
        cp      #K_NUM
        jr      nc,cv1
        dec     a               ; texto: el valor es el texto (sin valor para las listas)
        jr      nz,cv0
        ld      0(ix),#V_STR
        push    iy
        pop     hl
        ld      de,#7
        add     hl,de
        ld      1(ix),l
        ld      2(ix),h
        ld      a,6(iy)
        ld      3(ix),a
cv0:    xor     a
        pop     iy
        ret
cv1:    cp      #K_FRM
        call    z,evcell
        ld      a,4(iy)
        rrca
        rrca
        rrca
        rrca
        and     #3
        ld      0(ix),a
        ld      a,7(iy)
        ld      1(ix),a
        ld      a,8(iy)
        ld      2(ix),a
        ld      a,9(iy)
        ld      3(ix),a
        ld      a,10(iy)
        ld      4(ix),a
        ld      a,11(iy)
        ld      5(ix),a
        ld      a,#1
        pop     iy
        ret

; evcell: calcula la celda (iy) si es formula y no esta al dia
evcell: ld      a,4(iy)
        and     #7
        cp      #K_FRM
        ret     nz
        ld      a,(_gen)
        cp      12(iy)
        ret     z
        bit     3,4(iy)
        jr      z,ec1x
        ld      a,4(iy)         ; se llama a si misma
        and     #0xCF
        or      #0x10
        ld      4(iy),a
        ld      a,#1
        ld      (_circ),a
        ret
ec1x:   ld      a,(_depth)
        cp      #10
        jr      c,ec3x
        ld      a,#1
        ld      (_again),a
        ret
ec3x:   inc     a
        ld      (_depth),a
        set     3,4(iy)
        ld      hl,(spp)
        push    hl
        ld      hl,(_tp)
        push    hl
        push    iy
        pop     hl
        ld      de,#13
        add     hl,de
        ld      (_tp),hl
        xor     a
        ld      (_synerr),a
        ld      hl,#-6
        add     hl,sp
        ld      sp,hl
        push    ix
        push    iy
        push    hl
        pop     ix
        call    ev_expr
        push    ix
        pop     hl
        pop     iy
        pop     ix
        ld      a,(_synerr)
        or      a
        jr      z,ec4x
        ld      (hl),#V_ERR
ec4x:   push    hl
        call    stval
        pop     hl
        ld      a,(hl)
        rlca
        rlca
        rlca
        rlca
        and     #0x30
        ld      b,a
        ld      a,4(iy)
        and     #0xC7           ; sin tipo y sin "calculando"
        or      b
        ld      4(iy),a
        inc     hl
        push    iy
        pop     de
        ld      a,e
        add     a,#7
        ld      e,a
        adc     a,d
        sub     e
        ld      d,a
        ld      bc,#5
        ldir
        ld      a,(_gen)
        ld      12(iy),a
        ld      hl,#6
        add     hl,sp
        ld      sp,hl
        pop     hl
        ld      (_tp),hl
        pop     hl
        ld      (spp),hl
        ld      hl,#_depth
        dec     (hl)
        ret

; void expr(val *v): la formula en tp
_expr::
        push    ix
        push    iy
        ld      hl,#6
        add     hl,sp
        ld      a,(hl)
        inc     hl
        ld      h,(hl)
        ld      l,a
        push    hl
        pop     ix
        xor     a
        ld      (pdep),a
        ld      hl,#spool
        ld      (spp),hl
        call    ev_expr
        pop     iy
        pop     ix
        ret

; forall: llama a la rutina en DE con iy en cada celda
forall: ld      hl,#_ht
        ld      b,#128
fo1:    push    bc
        push    hl
        ld      a,(hl)
        inc     hl
        ld      h,(hl)
        ld      l,a
fo2:    ld      a,h
        or      l
        jr      z,fo3
        push    hl
        pop     iy
        push    hl
        push    de
        call    jpde
        pop     de
        pop     hl
        ld      a,(hl)
        inc     hl
        ld      h,(hl)
        ld      l,a
        jr      fo2
fo3:    pop     hl
        inc     hl
        inc     hl
        pop     bc
        djnz    fo1
        ret
genz:   ld      a,4(iy)
        and     #7
        cp      #K_FRM
        ret     nz
        ld      12(iy),#0
        ret
; void recalc(void)
_recalc::
        push    ix
        push    iy
        xor     a
        ld      (_circ),a
        ld      (rpass),a
rc1x:   xor     a
        ld      (_again),a
        ld      hl,#_gen
        inc     (hl)
        jr      nz,rc2x
        ld      de,#genz
        call    forall
        ld      hl,#_gen
        ld      (hl),#1
rc2x:   xor     a
        ld      (_depth),a
        ld      (pdep),a
        ld      hl,#spool
        ld      (spp),hl
        ld      de,#evcell
        call    forall
        ld      a,(_again)
        or      a
        jr      z,rc3x
        ld      hl,#rpass
        inc     (hl)
        ld      a,(hl)
        cp      #30
        jr      c,rc1x
rc3x:   pop     iy
        pop     ix
        ret

; ev_func: A = funcion -> (ix)
fclose: ld      hl,(_tp)
        ld      a,(hl)
        cp      #')'
        jp      nz,synx
        inc     hl
        ld      (_tp),hl
        ret
ev_func: ld     e,a
        call    zerov
        ld      d,#0
        ld      hl,#fmaxt
        add     hl,de
        ld      a,(hl)
        or      a
        jr      nz,fu1
        ld      hl,(_tp)        ; sin argumentos; "()" opcional
        ld      a,(hl)
        cp      #'('
        jr      nz,fc1
        inc     hl
        ld      a,(hl)
        cp      #')'
        jr      nz,fc1
        inc     hl
        ld      (_tp),hl
fc1:    ld      a,e
        cp      #F_PI
        jr      nz,fc2
        ld      1(ix),#0xA1     ; 314159265 E-8
        ld      2(ix),#0xB0
        ld      3(ix),#0xB9
        ld      4(ix),#0x12
        ld      5(ix),#-8
        ret
fc2:    cp      #F_TODAY
        jr      c,fc3
        ld      hl,#0           ; @TODAY, @NOW: cfunc(v, v, 0, id)
        jp      ccf
fc3:    ld      0(ix),#V_NA
        cp      #F_NA
        ret     z
        ld      0(ix),#V_ERR
        ret
; ccf: cfunc(v = ix, a = HL (0: ix), n = 0, id = A)
ccf:    push    iy
        push    af
        inc     sp
        xor     a
        push    af
        inc     sp
        ld      a,h
        or      l
        jr      nz,ccf1
        push    ix
        pop     hl
ccf1:   push    hl
        push    ix
        call    _cfunc
        pop     af
        pop     af
        pop     af
        pop     iy
        ret
fu1:    ld      hl,(_tp)
        ld      a,(hl)
        cp      #'('
        jp      nz,synx
        inc     hl
        ld      (_tp),hl
        ld      a,e
        cp      #F_COUNT+1
        jr      c,fagg
        cp      #F_AND
        jr      z,fagg
        cp      #F_OR
        jr      z,fagg
        cp      #F_LOOKUP
        jp      z,flook
        cp      #F_NPV
        jp      z,fnpv
        cp      #F_IRR
        jp      z,fnpv
        jp      fscal

; listas: marco en iy: acc(0-4) cnt(5-6) aet(7) id(8) tmp(9-14) c1(15) c2(16) r2(17) r(18)
fagg:   push    iy
        ld      hl,#-19
        add     hl,sp
        ld      sp,hl
        push    hl
        pop     iy
        xor     a
        ld      0(iy),a
        ld      1(iy),a
        ld      2(iy),a
        ld      3(iy),a
        ld      4(iy),a
        ld      5(iy),a
        ld      6(iy),a
        ld      7(iy),a
        ld      8(iy),e
fa1:    ld      hl,(_tp)
        ld      a,(hl)
        cp      #TK_RNG
        jr      nz,fa5
        inc     hl
        ld      a,(hl)
        and     #63
        ld      c,a
        inc     hl
        ld      b,(hl)
        inc     hl
        ld      a,(hl)
        and     #63
        ld      d,a
        inc     hl
        ld      e,(hl)
        inc     hl
        call    sknm
        ld      (_tp),hl
        ld      a,c
        or      a
        jr      nz,fa2
        ld      7(iy),#V_ERR
        jr      fa8
fa2:    ld      a,(_chk)
        or      a
        jr      nz,fa8
        ld      15(iy),c
        ld      16(iy),d
        ld      17(iy),e
        ld      18(iy),b
fa3:    ld      c,15(iy)
fa4:    ld      b,18(iy)
        push    bc
        call    ffind
        call    feedc
        pop     bc
        ld      a,c
        cp      16(iy)
        jr      nc,fa4e
        inc     c
        jr      fa4
fa4e:   ld      a,18(iy)
        cp      17(iy)
        jr      nc,fa8
        inc     a
        ld      18(iy),a
        jr      fa3
fa5:    push    ix
        push    iy
        pop     ix
        ld      de,#9
        add     ix,de
        call    ev_expr
        pop     ix
        call    feed
fa8:    ld      hl,(_tp)
        ld      a,(hl)
        cp      #','
        jr      nz,fa9
        inc     hl
        ld      (_tp),hl
        jp      fa1
fa9:    ld      a,7(iy)
        ld      0(ix),a
        or      a
        jp      nz,faend
        ld      a,0(iy)
        ld      1(ix),a
        ld      a,1(iy)
        ld      2(ix),a
        ld      a,2(iy)
        ld      3(ix),a
        ld      a,3(iy)
        ld      4(ix),a
        ld      a,4(iy)
        ld      5(ix),a
        xor     a
        ld      (_nerr),a
        ld      a,8(iy)
        cp      #F_COUNT
        jr      nz,fb1
        ld      l,5(iy)
        ld      h,6(iy)
        call    setvi
        jr      faend
fb1:    cp      #F_AVG
        jr      nz,fb2
        ld      a,5(iy)
        or      6(iy)
        jr      nz,fb1a
        ld      0(ix),#V_ERR
        jr      faend
fb1a:   ld      l,5(iy)
        ld      h,6(iy)
        push    ix
        push    iy
        pop     ix
        ld      de,#9
        add     ix,de
        call    setvi
        pop     ix
        push    iy
        ld      de,#9
        add     iy,de
        ld      a,#'/'
        call    evbin
        pop     iy
        jr      faend
fb2:    cp      #F_AND
        jr      z,fb3
        cp      #F_OR
        jr      nz,faend
fb3:    ld      a,5(iy)
        or      6(iy)
        jr      z,fb3f
        ld      a,1(ix)
        or      2(ix)
        or      3(ix)
        or      4(ix)
        jr      z,fb3f
        ld      hl,#1
        jr      fb3s
fb3f:   ld      hl,#0
fb3s:   call    setvi
faend:  ld      hl,#19
        add     hl,sp
        ld      sp,hl
        pop     iy
        jp      fclose
; feedc: la celda HL (si tiene valor) a la lista
feedc:  push    ix
        push    iy
        pop     ix
        ld      de,#9
        add     ix,de
        call    cellv
        pop     ix
        or      a
        ret     z
; feed: tmp (iy+9) a la lista
feed:   ld      a,9(iy)
        cp      #V_STR
        ret     z
        ld      a,8(iy)
        cp      #F_COUNT
        jp      z,inccnt        ; COUNT cuenta tambien ERROR y NA
        ld      a,9(iy)
        or      a
        jr      z,fd2
        cp      #V_ERR
        jr      z,fd1a
        ld      a,7(iy)
        cp      #V_ERR
        ret     z
        ld      a,9(iy)
fd1a:   ld      7(iy),a
        ret
fd2:    ld      a,5(iy)
        or      6(iy)
        push    af
        call    inccnt
        pop     af
        jr      nz,fd3
fdset:  push    iy              ; acc = tmp
        pop     hl
        push    hl
        ld      de,#10
        add     hl,de
        pop     de
        ld      bc,#5
        ldir
        ret
fd3:    ld      a,8(iy)
        cp      #F_MIN
        jr      z,fdmin
        cp      #F_MAX
        jr      z,fdmax
        cp      #F_AND
        jr      z,fdand
        cp      #F_OR
        jr      z,fdor
        push    iy              ; SUM, AVG: acc = acc + tmp
        pop     hl
        ld      (oparg),hl
        ld      (oparg+2),hl
        ld      de,#10
        add     hl,de
        ld      (oparg+4),hl
        ld      de,#_naddi
        jp      xop
fdmin:  call    fdcmp
        cp      #2
        ret     nz
        jr      fdset
fdmax:  call    fdcmp
        cp      #1
        ret     nz
        jr      fdset
fdcmp:  ld      hl,#cmps        ; signo de tmp - acc
        ld      (oparg),hl
        push    iy
        pop     hl
        ld      (oparg+4),hl
        ld      de,#10
        add     hl,de
        ld      (oparg+2),hl
        call    nsubx
        ld      hl,#cmps
        jp      nsign
fdand:  push    iy
        pop     hl
        ld      de,#10
        add     hl,de
        call    iszero
        ret     nz
        jr      fdset
fdor:   push    iy
        pop     hl
        ld      de,#10
        add     hl,de
        call    iszero
        ret     z
        jr      fdset
inccnt: ld      l,5(iy)
        ld      h,6(iy)
        inc     hl
        ld      5(iy),l
        ld      6(iy),h
        ret

; @LOOKUP(x, rango): marco x(0-5) a(6-11) c1 r1 c2 r2(12-15) vert(16) fc fr(17-18) c r(19-20)
flook:  push    iy
        ld      hl,#-21
        add     hl,sp
        ld      sp,hl
        push    hl
        pop     iy
        push    ix
        push    iy
        pop     ix
        call    ev_expr
        pop     ix
        ld      hl,(_tp)
        ld      a,(hl)
        cp      #','
        jp      nz,lsyn
        inc     hl
        ld      a,(hl)
        cp      #TK_RNG
        jp      nz,lsyn
        inc     hl
        ld      a,(hl)
        and     #63
        ld      12(iy),a
        inc     hl
        ld      a,(hl)
        ld      13(iy),a
        inc     hl
        ld      a,(hl)
        and     #63
        ld      14(iy),a
        inc     hl
        ld      a,(hl)
        ld      15(iy),a
        inc     hl
        call    sknm
        ld      (_tp),hl
        ld      0(ix),#V_NA
        ld      a,(_chk)
        or      a
        jr      z,lk1
        ld      0(ix),#0
        jp      lend
lk1:    ld      a,12(iy)
        or      a
        jr      nz,lk1a
        ld      0(ix),#V_ERR
        jp      lend
lk1a:   ld      a,0(iy)
        or      a
        jr      z,lk2
        cp      #V_STR
        jr      nz,lk1b
        ld      a,#V_NA
lk1b:   ld      0(ix),a
        jp      lend
lk2:    ld      a,12(iy)
        ld      19(iy),a
        sub     14(iy)
        ld      a,#0
        jr      nz,lk2a
        inc     a
lk2a:   ld      16(iy),a
        xor     a
        ld      17(iy),a
        ld      18(iy),a
        ld      a,13(iy)
        ld      20(iy),a
lk3:    ld      a,14(iy)
        cp      19(iy)
        jr      c,lk6
        ld      a,15(iy)
        cp      20(iy)
        jr      c,lk6
        ld      c,19(iy)
        ld      b,20(iy)
        call    ffind
        push    ix
        push    iy
        pop     ix
        ld      de,#6
        add     ix,de
        call    cellv
        pop     ix
        or      a
        jr      z,lk5
        ld      a,6(iy)
        or      a
        jr      nz,lk5
        ld      hl,#cmps        ; a - x > 0: se paso
        ld      (oparg),hl
        push    iy
        pop     hl
        inc     hl
        ld      (oparg+4),hl
        ld      de,#6
        add     hl,de
        ld      (oparg+2),hl
        call    nsubx
        ld      hl,#cmps
        call    nsign
        cp      #1
        jr      z,lk6
        ld      a,19(iy)
        ld      17(iy),a
        ld      a,20(iy)
        ld      18(iy),a
lk5:    ld      a,16(iy)
        or      a
        jr      z,lk5h
        ld      a,20(iy)
        cp      #NROW
        jr      z,lk6
        inc     20(iy)
        jr      lk3
lk5h:   ld      a,19(iy)
        cp      #NCOL
        jr      z,lk6
        inc     19(iy)
        jr      lk3
lk6:    ld      a,17(iy)
        or      a
        jr      z,lend
        ld      c,a
        ld      b,18(iy)
        ld      a,16(iy)
        or      a
        jr      z,lk7
        inc     c
        ld      a,c
        cp      #NCOL+1
        jr      nc,lend
        jr      lk8
lk7:    inc     b
        ld      a,b
        cp      #NROW+1
        jr      nc,lend
lk8:    call    zerov
        call    ffind
        call    cellv
lend:   ld      hl,#21
        add     hl,sp
        ld      sp,hl
        pop     iy
        jp      fclose
lsyn:   ld      hl,#21
        add     hl,sp
        ld      sp,hl
        pop     iy
        jp      synx

; funciones de 1 a 3 valores: marco a0 a1 a2 (0-17) n(18) id(19)
fscal:  push    iy
        ld      hl,#-20
        add     hl,sp
        ld      sp,hl
        push    hl
        pop     iy
        ld      18(iy),#0
        ld      19(iy),e
fs1:    ld      a,18(iy)
        cp      #3
        jp      z,fssyn
        ld      e,a
        add     a,a
        add     a,e
        add     a,a
        ld      e,a
        ld      d,#0
        push    ix
        push    iy
        pop     hl
        add     hl,de
        push    hl
        pop     ix
        call    ev_expr
        pop     ix
        inc     18(iy)
        ld      hl,(_tp)
        ld      a,(hl)
        cp      #','
        jr      nz,fs2
        inc     hl
        ld      (_tp),hl
        jr      fs1
fs2:    ld      e,19(iy)
        ld      d,#0
        ld      hl,#fmint
        add     hl,de
        ld      a,18(iy)
        cp      (hl)
        jp      c,fssyn
        ld      hl,#fmaxt
        add     hl,de
        ld      a,(hl)
        cp      18(iy)
        jp      c,fssyn
        ld      a,19(iy)
        cp      #F_LEFT
        jp      nc,fstr
        cp      #F_ISNA
        jr      nz,fs2a
        ld      a,0(iy)
        cp      #V_NA
        jr      fsbool
fs2a:   cp      #F_ISERR
        jr      nz,fs2b
        ld      a,0(iy)
        cp      #V_ERR
fsbool: ld      hl,#0
        jr      nz,fsb1
        inc     hl
fsb1:   call    setvi
        jp      fsend
fs2b:   cp      #F_IF
        jr      nz,fs2c
        ld      de,#0           ; a0 con error: a0; si no, a1 o a2
        ld      a,0(iy)
        or      a
        jr      nz,fsif
        push    iy
        pop     hl
        call    iszero1
        ld      de,#6
        jr      nz,fsif
        ld      de,#12
fsif:   push    iy
        pop     hl
        add     hl,de
        push    ix
        pop     de
        ld      bc,#6
        ldir
        jp      fsend
fs2c:   ld      b,18(iy)        ; errores de los argumentos: ERROR gana a NA
        push    iy
        pop     hl
        ld      c,#0
fs2d:   ld      a,(hl)
        or      a
        jr      z,fs2f
        cp      #V_STR          ; un texto donde va un numero: ERROR
        jr      nz,fs2d1
        ld      a,#V_ERR
fs2d1:  cp      #V_ERR
        jr      z,fs2e
        ld      c,a
fs2f:   ld      de,#6
        add     hl,de
        djnz    fs2d
        ld      a,c
        or      a
        jr      z,fs2g
fs2e:   ld      0(ix),a
        jp      fsend
fs2g:   ld      a,19(iy)
        cp      #F_CF
        jr      c,fs3
        push    iy              ; cfunc(v, a, n, id)
        push    af
        inc     sp
        ld      a,18(iy)
        push    af
        inc     sp
        push    iy
        push    ix
        call    _cfunc
        pop     af
        pop     af
        pop     af
        pop     iy
        jp      fsend
fs3:    xor     a
        ld      (_nerr),a
        push    iy              ; v = a0
        pop     hl
        inc     hl
        push    ix
        pop     de
        inc     de
        ld      bc,#5
        ldir
        ld      a,19(iy)
        cp      #F_ABS
        jr      nz,fs4
        bit     7,4(ix)
        call    nz,negv
        jp      fsok
fs4:    cp      #F_NOT
        jr      nz,fs5
        push    iy
        pop     hl
        call    iszero1
        ld      hl,#0
        jr      nz,fs4a
        inc     hl
fs4a:   call    setvi
        jp      fsok
fs5:    cp      #F_INT
        jr      nz,fs6
        call    pva0            ; ntrunc(v, a0)
        call    _ntrunc
        pop     af
        pop     af
        jp      fsok
fs6:    cp      #F_SQRT
        jr      nz,fs7
        push    iy
        call    pva0
        call    _nsqrt
        pop     af
        pop     af
        pop     iy
        ld      a,l
        or      a
        jp      z,fsok
        ld      0(ix),#V_ERR
        jp      fsend
fs7:    cp      #F_ROUND
        jr      nz,fs8
        push    iy              ; n = ntoi(a1), de -9 a 9
        pop     hl
        ld      de,#7
        add     hl,de
        push    iy              ; el C puede usar iy
        push    hl
        call    _ntoi
        pop     af
        pop     iy
        ld      a,h
        bit     7,a
        jr      nz,fs7n
        or      a
        jr      nz,fs7p
        ld      a,l
        cp      #10
        jr      c,fs7a
fs7p:   ld      a,#9
        jr      fs7a
fs7n:   inc     a
        jr      nz,fs7m
        ld      a,l
        cp      #-9
        jr      nc,fs7a
fs7m:   ld      a,#-9
fs7a:   push    af
        inc     sp
        call    pva0
        call    _nround
        pop     af
        pop     af
        inc     sp
        jr      fsok
fs8:    ; F_MOD: a0 - b * INT(a0 / b)
        push    iy
        pop     hl
        ld      de,#7
        add     hl,de
        call    iszero
        jr      nz,fs8a
        ld      0(ix),#V_ERR
        jr      fsend
fs8a:   push    ix              ; v = a0 / a1
        pop     hl
        inc     hl
        ld      (oparg),hl
        push    iy
        pop     hl
        inc     hl
        ld      (oparg+2),hl
        ld      de,#6
        add     hl,de
        ld      (oparg+4),hl
        ld      de,#_ndivi
        call    xop
        push    ix              ; INT
        pop     hl
        inc     hl
        push    hl
        push    hl
        call    _ntrunc
        pop     af
        pop     af
        push    ix              ; v = v * a1
        pop     hl
        inc     hl
        ld      (oparg),hl
        ld      (oparg+2),hl
        push    iy
        pop     hl
        ld      de,#7
        add     hl,de
        ld      (oparg+4),hl
        ld      de,#_nmuli
        call    xop
        push    ix              ; v = a0 - v
        pop     hl
        inc     hl
        ld      (oparg),hl
        ld      (oparg+4),hl
        push    iy
        pop     hl
        inc     hl
        ld      (oparg+2),hl
        call    nsubx
fsok:   ld      a,(_nerr)
        or      a
        jr      z,fsend
        ld      0(ix),#V_ERR
fsend:  ld      hl,#20
        add     hl,sp
        ld      sp,hl
        pop     iy
        jp      fclose
fssyn:  ld      hl,#20
        add     hl,sp
        ld      sp,hl
        pop     iy
        jp      synx
; @NPV(tasa, flujos) / @IRR(tasa inicial, flujos): marco tasa(0-5) tmp(6-11) c1 c2 r2 r(12-15) err(16) id(17)
fnpv:   push    iy
        ld      hl,#-18
        add     hl,sp
        ld      sp,hl
        push    hl
        pop     iy
        ld      17(iy),e
        xor     a
        ld      16(iy),a
        ld      (_cfn),a
        push    ix
        push    iy
        pop     ix
        call    ev_expr
        pop     ix
np1:    ld      hl,(_tp)
        ld      a,(hl)
        cp      #','
        jp      nz,np9
        inc     hl
        ld      (_tp),hl
        ld      a,(hl)
        cp      #TK_RNG
        jr      nz,np5
        inc     hl
        ld      a,(hl)
        and     #63
        ld      c,a
        inc     hl
        ld      b,(hl)
        inc     hl
        ld      a,(hl)
        and     #63
        ld      13(iy),a
        inc     hl
        ld      a,(hl)
        ld      14(iy),a
        inc     hl
        call    sknm
        ld      (_tp),hl
        ld      a,c
        or      a
        jr      nz,np2
        ld      16(iy),#V_ERR
        jr      np1
np2:    ld      a,(_chk)
        or      a
        jr      nz,np1
        ld      12(iy),c
        ld      15(iy),b
np3:    ld      c,12(iy)
np4:    ld      b,15(iy)
        push    bc
        call    ffind
        push    ix
        push    iy
        pop     ix
        ld      de,#6
        add     ix,de
        call    cellv
        pop     ix
        or      a
        call    nz,npadd
        pop     bc
        ld      a,c
        cp      13(iy)
        jr      nc,np4e
        inc     c
        jr      np4
np4e:   ld      a,15(iy)
        cp      14(iy)
        jr      nc,np1
        inc     a
        ld      15(iy),a
        jr      np3
np5:    push    ix
        push    iy
        pop     ix
        ld      de,#6
        add     ix,de
        call    ev_expr
        pop     ix
        call    npadd
        jp      np1
np9:    ld      a,(_chk)
        or      a
        jr      nz,npend
        ld      a,0(iy)         ; la tasa con error
        or      a
        jr      nz,np9a
        ld      a,16(iy)
        or      a
        jr      z,np9b
np9a:   ld      0(ix),a
        jr      npend
np9b:   push    iy              ; cfunc(v, tasa, n, id)
        ld      a,17(iy)
        push    af
        inc     sp
        ld      a,(_cfn)
        push    af
        inc     sp
        push    iy
        push    ix
        call    _cfunc
        pop     af
        pop     af
        pop     af
        pop     iy
npend:  ld      hl,#18
        add     hl,sp
        ld      sp,hl
        pop     iy
        jp      fclose
; npadd: el valor en iy+6 a los flujos
npadd:  ld      a,6(iy)
        or      a
        jr      z,npa1
        cp      #V_STR
        ret     z
        cp      #V_ERR
        jr      z,npa0
        ld      a,16(iy)
        cp      #V_ERR
        ret     z
        ld      a,6(iy)
npa0:   ld      16(iy),a
        ret
npa1:   ld      a,(_cfn)
        cp      #48
        ret     nc
        ld      l,a
        add     a,a
        add     a,a
        add     a,l
        ld      e,a
        ld      d,#0
        ld      hl,#_cfb
        add     hl,de
        ex      de,hl
        push    iy
        pop     hl
        ld      bc,#7
        add     hl,bc
        ld      bc,#5
        ldir
        ld      hl,#_cfn
        inc     (hl)
        ret

; pva0: empuja (a0, v) para una rutina C con sdcccall 0 (el que llama saca 2)
pva0:   pop     bc
        push    iy
        pop     hl
        inc     hl
        push    hl
        push    ix
        pop     hl
        inc     hl
        push    hl
        push    bc
        ret
; iszero1: Z si el num del val en (hl) es 0
iszero1: inc    hl
        jp      iszero

; ------------------------------------------------------------------ celdas en pantalla
        .area   _DATA
fz:     .ds     5
fnf:    .ds     1
ctb:    .ds     44
cxo:    .ds     2               ; donde va el texto de la celda
cxw:    .ds     1               ; su ancho
cxc:    .ds     1
cxr:    .ds     1
coff:   .ds     2

        .area   _CODE
; void fmtnum(char *o, const num *x, uint8_t nf, uint8_t w)
_fmtnum::
        push    ix
        push    iy
        ld      hl,#6
        add     hl,sp
        call    farg
        ld      a,(hl)
        ld      (fnf),a
        inc     hl
        ld      a,(hl)
        ld      (fmax),a
        call    fmtn
        pop     iy
        pop     ix
        ret
; fmtn: fx con el formato fnf en a lo mas fmax caracteres en (fo); si no cabe, >>>
fmtn:   ld      a,(fnf)
        cp      #3
        jr      c,fm2
        sub     #3              ; decimales fijos
        ld      (fdec),a
        call    rndfy
        ld      hl,#fy
        ld      de,#fx
        ld      bc,#5
        ldir
        call    plain
        or      a
        ret     nz
        jr      fmfill
fm2:    ld      a,#0xFF         ; general
        ld      (fdec),a
        call    plain
        or      a
        ret     nz
        ld      a,(fneg)        ; menos decimales
        ld      b,a
        ld      a,(fip)
        add     a,b
        ld      c,a             ; neg + ip
        inc     a
        ld      b,a
        ld      a,(fmax)
        cp      b
        jr      c,fm3
        jr      z,fm3
        sub     b
        jr      fm4
fm3:    ld      a,(fmax)
        cp      c
        jr      c,fm5
        xor     a
fm4:    call    rndfy
        ld      hl,#fy
        call    iszero
        jr      z,fm5
        ld      hl,#fx
        ld      de,#fz
        ld      bc,#5
        ldir
        ld      hl,#fy
        ld      de,#fx
        ld      bc,#5
        ldir
        ld      a,#0xFF
        ld      (fdec),a
        call    plain
        push    af
        ld      hl,#fz
        ld      de,#fx
        ld      bc,#5
        ldir
        pop     af
        or      a
        ret     nz
fm5:    call    sci
        or      a
        ret     nz
fmfill: ld      hl,(fo)
        ld      a,(fmax)
        ld      b,a
fmf1:   ld      (hl),#'>'
        inc     hl
        djnz    fmf1
        ld      (hl),#0
        ld      a,(fmax)
        ret
; rndfy: fy = fx redondeado a A decimales
rndfy:  push    af
        inc     sp
        ld      hl,#fx
        push    hl
        ld      hl,#fy
        push    hl
        call    _nround
        pop     af
        pop     af
        inc     sp
        ret

; cwid: A = ancho de la columna C
cwid:   push    hl
        push    de
        ld      e,c
        ld      d,#0
        ld      hl,#_cw
        add     hl,de
        ld      a,(hl)
        or      a
        jr      nz,cw1
        ld      a,(_gw)
cw1:    pop     de
        pop     hl
        ret

; void cellstr(char *o, uint8_t c, uint8_t r, uint8_t w): exactamente w caracteres
_cellstr::
        push    ix
        push    iy
        ld      hl,#6
        add     hl,sp
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      (cxo),de
        ld      a,(hl)
        ld      (cxc),a
        inc     hl
        ld      a,(hl)
        ld      (cxr),a
        inc     hl
        ld      a,(hl)
        ld      (cxw),a
        ex      de,hl           ; espacios y 0
        ld      b,a
        or      a
        jr      z,cs0
cs0a:   ld      (hl),#' '
        inc     hl
        djnz    cs0a
cs0:    ld      (hl),#0
        ld      a,(cxc)
        ld      c,a
        ld      a,(cxr)
        ld      b,a
        call    ffind
        ld      a,h
        or      l
        jp      nz,cs5
        ld      hl,#0           ; vacia: un texto largo de la izquierda sigue aqui
        ld      (coff),hl
        ld      a,(cxc)
        ld      c,a
cs1:    dec     c
        jp      z,csend
        ld      hl,(coff)
        ld      a,h
        or      a
        jp      nz,csend
        ld      a,l
        cp      #120
        jp      nc,csend
        call    cwid
        add     a,l
        ld      l,a
        ld      h,#0
        ld      (coff),hl
        push    bc
        ld      a,(cxr)
        ld      b,a
        call    ffind
        pop     bc
        ld      a,h
        or      l
        jr      z,cs1
        push    hl
        pop     iy
        ld      a,4(iy)         ; texto, no a la derecha, mas largo que lo que hay antes
        and     #7
        cp      #1
        jp      nz,csend
        ld      a,5(iy)
        and     #0x30
        cp      #0x20
        jp      z,csend
        ld      a,(coff)
        ld      b,a
        ld      a,6(iy)
        sub     b
        jp      c,csend
        jp      z,csend
        ld      c,a             ; n - off
        ld      a,(cxw)
        cp      c
        jr      nc,cs2
        ld      c,a
cs2:    push    iy
        pop     hl
        ld      de,#7
        add     hl,de
        ld      e,b
        ld      d,#0
        add     hl,de
        ld      de,(cxo)
        ld      b,#0
        ldir
        jp      csend
cs5:    push    hl
        pop     iy
        ld      a,4(iy)
        and     #7
        cp      #1
        jr      nz,cs6
        ld      a,6(iy)         ; texto
        ld      c,a
        ld      a,(cxw)
        cp      c
        jr      nc,cs5a
        ld      c,a
cs5a:   ld      de,(cxo)
        ld      a,5(iy)
        and     #0x30
        cp      #0x20
        jr      nz,cs5b
        ld      a,(cxw)         ; a la derecha
        sub     c
        add     a,e
        ld      e,a
        adc     a,d
        sub     e
        ld      d,a
cs5b:   ld      a,c
        or      a
        jp      z,csend
        push    iy
        pop     hl
        ld      bc,#7
        add     hl,bc
        ld      c,a
        ld      b,#0
        ldir
        jp      csend
cs6:    cp      #2
        jr      nz,cs7
        ld      a,6(iy)         ; texto repetido
        or      a
        jp      z,csend
        ld      hl,(cxo)
        ld      a,(cxw)
        ld      b,a
        or      a
        jp      z,csend
cs6a:   push    iy
        pop     de
        ld      a,e
        add     a,#7
        ld      e,a
        adc     a,d
        sub     e
        ld      d,a
        ld      c,6(iy)
cs6b:   ld      a,(de)
        ld      (hl),a
        inc     hl
        inc     de
        dec     b
        jp      z,csend
        dec     c
        jr      nz,cs6b
        jr      cs6a
cs7:    ld      a,4(iy)         ; valor
        rrca
        rrca
        rrca
        rrca
        and     #3
        jr      z,cs8
        cp      #V_STR
        jp      z,cstr
        ld      hl,#serr
        cp      #V_ERR
        jr      z,cs7a
        ld      hl,#sna
cs7a:   ld      de,#ctb
        ld      bc,#6
        ldir
        jp      cs9
cs8:    ld      a,5(iy)
        and     #15
        jr      nz,cs8a
        ld      a,(_gnf)
cs8a:   cp      #13
        jr      c,cs8x
        push    iy              ; fecha o la hora: datestr(ctb, num, nf)
        push    af
        inc     sp
        push    iy
        pop     hl
        ld      de,#7
        add     hl,de
        push    hl
        ld      hl,#ctb
        push    hl
        call    _datestr
        pop     af
        pop     af
        inc     sp
        pop     iy
        ld      a,l
        or      a
        jp      nz,cs9
        ld      hl,(cxo)        ; fuera de rango
        ld      a,(cxw)
        ld      b,a
cs8y:   ld      (hl),#'>'
        inc     hl
        djnz    cs8y
        jp      csend
cs8x:   cp      #2
        jr      nz,cs8g
        push    iy              ; grafico: tantos * como la parte entera
        pop     hl
        ld      de,#7
        add     hl,de
        push    iy
        push    hl
        call    _ntoi
        pop     af
        pop     iy
        bit     7,h
        jp      nz,csend
        ld      a,h
        or      a
        ld      a,(cxw)
        jr      nz,cs8b
        cp      l
        jr      c,cs8b
        ld      a,l
cs8b:   or      a
        jp      z,csend
        ld      b,a
        ld      hl,(cxo)
cs8c:   ld      (hl),#'*'
        inc     hl
        djnz    cs8c
        jr      csend
cs8g:   ld      (fnf),a
        push    iy
        pop     hl
        ld      de,#7
        add     hl,de
        ld      de,#fx
        ld      bc,#5
        ldir
        ld      hl,#ctb
        ld      (fo),hl
        ld      a,(cxw)
        dec     a
        jr      nz,cs8d
        inc     a
cs8d:   ld      (fmax),a
        call    fmtn
cs9:    ld      hl,#ctb         ; a la derecha (o a la izquierda con L)
        ld      bc,#0
cs9a:   ld      a,(hl)
        or      a
        jr      z,cs9b
        inc     hl
        inc     c
        jr      cs9a
cs9b:   ld      a,(cxw)
        cp      c
        jr      nc,cs9c
        ld      c,a
cs9c:   ld      a,c
        or      a
        jr      z,csend
        ld      de,(cxo)
        ld      a,5(iy)
        and     #0x30
        cp      #0x10
        jr      z,cs9d
        ld      a,(cxw)
        sub     c
        add     a,e
        ld      e,a
        adc     a,d
        sub     e
        ld      d,a
cs9d:   ld      hl,#ctb
        ldir
csend:  pop     iy
        pop     ix
        ret
cstr:   ld      a,9(iy)         ; formula que da texto
        ld      c,a
        ld      a,(cxw)
        cp      c
        jr      nc,cst1
        ld      c,a
cst1:   ld      de,(cxo)
        ld      a,5(iy)
        and     #0x30
        cp      #0x20
        jr      nz,cst2
        ld      a,(cxw)
        sub     c
        add     a,e
        ld      e,a
        adc     a,d
        sub     e
        ld      d,a
cst2:   ld      a,c
        or      a
        jp      z,csend
        ld      l,7(iy)
        ld      h,8(iy)
        ld      b,#0
        ldir
        jp      csend
serr:   .ascii  "ERROR"
        .db     0
sna:    .ascii  "NA"
        .db     0,0,0,0

; ------------------------------------------------------------------ referencias que se mueven
; modos (_am): 0 insertar en aat, 1 borrar aat (filas si _arow), 2 mover el
; rectangulo mc1,mr1-mc2,mr2 en mdc, mdr; shiftform corre las relativas en sdc, sdr
        .area   _DATA
_am::   .ds     1
_arow:: .ds     1
_aat::  .ds     1
_mc1::  .ds     1
_mr1::  .ds     1
_mc2::  .ds     1
_mr2::  .ds     1
_mdc::  .ds     2
_mdr::  .ds     2
wmode:  .ds     1
wend:   .ds     1
sdc:    .ds     2
sdr:    .ds     2

        .area   _CODE
; void adjform(uint8_t *t)
_adjform::
        xor     a
        jr      wk0
; void shiftform(uint8_t *t, int16_t dc, int16_t dr)
_shiftform::
        ld      hl,#4
        add     hl,sp
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      (sdc),de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ld      (sdr),de
        ld      a,#1
wk0:    ld      (wmode),a
        push    ix
        ld      hl,#4
        add     hl,sp
        ld      a,(hl)
        inc     hl
        ld      h,(hl)
        ld      l,a
        push    hl
        pop     ix
wk1:    ld      a,0(ix)
        or      a
        jp      z,wkend
        ld      de,#6
        cp      #TK_NUM
        jr      z,wkn
        ld      de,#2
        cp      #TK_I8
        jr      z,wkn
        cp      #TK_FN
        jr      z,wkn
        cp      #TK_NM
        jr      z,wkn
        cp      #TK_REF
        jr      z,wkref
        cp      #TK_RNG
        jr      z,wkrng
        cp      #TK_STR
        jr      z,wkstr
        ld      de,#1
wkn:    add     ix,de
        jr      wk1
wkstr:  ld      e,1(ix)
        ld      d,#0
        inc     de
        inc     de
        jr      wkn
wkref:  ld      a,1(ix)
        and     #63
        jr      z,wkr2
        xor     a
        ld      (wend),a
        push    ix
        pop     hl
        inc     hl
        call    xform
        jr      nc,wkr2
        ld      1(ix),#0
wkr2:   ld      de,#3
        jr      wkn
wkrng:  ld      a,1(ix)
        and     #63
        jr      z,wkg9
        ld      a,#1
        ld      (wend),a
        push    ix
        pop     hl
        inc     hl
        call    xform
        jr      c,wkg8
        ld      a,#2
        ld      (wend),a
        push    ix
        pop     hl
        inc     hl
        inc     hl
        inc     hl
        call    xform
        jr      c,wkg8
        ld      a,3(ix)         ; columnas
        and     #63
        ld      b,a
        ld      a,1(ix)
        and     #63
        cp      b
        jr      z,wkg5
        jr      c,wkg5
        ld      a,(wmode)       ; al reves: al mover, error; al copiar, se cambian
        or      a
        jr      z,wkg8
        ld      a,1(ix)
        ld      b,3(ix)
        ld      3(ix),a
        ld      1(ix),b
wkg5:   ld      a,4(ix)         ; filas
        cp      2(ix)
        jr      nc,wkg9
        ld      a,(wmode)
        or      a
        jr      z,wkg8
        ld      a,2(ix)
        ld      b,4(ix)
        ld      4(ix),a
        ld      2(ix),b
        jr      wkg9
wkg8:   ld      1(ix),#0
wkg9:   ld      de,#5
        jp      wkn
wkend:  pop     ix
        ret

; xform: (hl) = cf, (hl+1) = fila; la cambia segun el modo; carry si se pierde
xform:  ld      a,(hl)
        and     #0xC0
        ld      d,a             ; los $
        ld      a,(hl)
        and     #63
        ld      c,a
        inc     hl
        ld      b,(hl)
        dec     hl
        ld      a,(wmode)
        or      a
        jr      z,xa
        push    hl              ; copiar: c += sdc si no tiene $, r += sdr
        ld      e,c
        bit     6,d
        jr      nz,xs1
        ld      a,(sdc)
        add     a,c
        ld      e,a
xs1:    ld      a,e
        or      a
        jr      z,xs9
        cp      #NCOL+1
        jr      nc,xs9
        ld      c,a
        ld      l,b
        ld      h,#0
        bit     7,d
        jr      nz,xs2
        push    de
        ld      de,(sdr)
        add     hl,de
        pop     de
xs2:    ld      a,h
        or      a
        jr      nz,xs9
        ld      a,l
        or      a
        jr      z,xs9
        cp      #NROW+1
        jr      nc,xs9
        ld      b,a
        pop     hl
        jr      xok
xs9:    pop     hl
        scf
        ret
xa:     ld      a,(_am)
        cp      #2
        jr      nz,xa3
        ld      a,(_mc1)        ; mover: solo lo de adentro
        dec     a
        cp      c
        jr      nc,xok0
        ld      a,(_mc2)
        cp      c
        jr      c,xok0
        ld      a,(_mr1)
        dec     a
        cp      b
        jr      nc,xok0
        ld      a,(_mr2)
        cp      b
        jr      c,xok0
        ld      a,(_mdc)
        add     a,c
        jr      z,xbad
        cp      #NCOL+1
        jr      nc,xbad
        ld      c,a
        push    hl
        ld      l,b
        ld      h,#0
        push    de
        ld      de,(_mdr)
        add     hl,de
        pop     de
        ld      a,h
        or      a
        jr      nz,xs9
        ld      a,l
        or      a
        jr      z,xs9
        cp      #NROW+1
        jr      nc,xs9
        ld      b,a
        pop     hl
        jr      xok
xa3:    ld      a,(_arow)
        or      a
        jr      z,xa4
        ld      a,b
        ld      e,#NROW
        call    adj1
        or      a
        jr      z,xbad
        ld      b,a
        jr      xok
xa4:    ld      a,c
        ld      e,#NCOL
        call    adj1
        or      a
        jr      z,xbad
        ld      c,a
xok:    ld      a,c
        or      d
        ld      (hl),a
        inc     hl
        ld      (hl),b
        dec     hl
xok0:   or      a
        ret
xbad:   scf
        ret
; adj1: A = coordenada, E = maximo -> A (0 = se pierde)
adj1:   push    bc
        ld      c,a
        ld      a,(_aat)
        ld      b,a
        ld      a,(_am)
        or      a
        ld      a,c
        jr      nz,ad3
        cp      b               ; insertar
        jr      c,ad9
        cp      e
        jr      nz,ad1
        ld      a,(wend)
        cp      #2
        ld      a,e
        jr      z,ad9
        xor     a
        jr      ad9
ad1:    ld      a,c
        inc     a
        jr      ad9
ad3:    cp      b               ; borrar
        jr      nz,ad5
        ld      a,(wend)
        or      a
        jr      z,ad9
        cp      #1
        ld      a,b
        jr      nz,ad4
        cp      e
        jr      c,ad9
        xor     a
        jr      ad9
ad4:    dec     a
        jr      ad9
ad5:    jr      c,ad9
        dec     a
ad9:    pop     bc
        ret

; ------------------------------------------------------------------ funciones de finanzas, fechas y trigonometria
; Una "calculadora" chica: 16 registros num (R0-R15) y programas de 2 bytes por
; operacion (vmasm.py los arma: el texto esta en los comentarios). R0 da el resultado.
        .area   _DATA
_cfb::  .ds     240             ; flujos de @NPV y @IRR (48)
_cfn::  .ds     1
vreg:   .ds     80
vpc:    .ds     2
vcnt:   .ds     4
vfp:    .ds     2
vb2:    .ds     1
vr:     .ds     2
vop:    .ds     1
vargs:  .ds     2
vid:    .ds     1
vneg:   .ds     1
ny:     .ds     2               ; fechas
nm_:    .ds     2
nd_:    .ds     2
nser:   .ds     4
clkb:   .ds     4

        .area   _CODE
; constantes de LDK: 0, 1, 2, pi, ln2, ln10, 4, 86400, 0.1, 1440
ktab:   .db     0,0,0,0,0
        .db     1,0,0,0,0
        .db     2,0,0,0,0
        .db     0xA1,0xB0,0xB9,0x12,0xF8
        .db     0x2D,0x96,0x50,0x29,0xF7
        .db     0x4D,0x77,0xB9,0x0D,0xF8
        .db     4,0,0,0,0
        .db     0x60,0x03,0,0,2
        .db     1,0,0,0,0xFF
        .db     144,0,0,0,1

; raddr: HL = el registro A
raddr:  ld      l,a
        add     a,a
        add     a,a
        add     a,l
        ld      e,a
        ld      d,#0
        ld      hl,#vreg
        add     hl,de
        ret
; nop: A = '+' '-' '*' '/', HL = r, DE = a, BC = b
nop:    ld      (oparg),hl
        ld      (oparg+2),de
        ld      (oparg+4),bc
        cp      #'-'
        jp      z,nsubx
        ld      de,#_naddi
        cp      #'+'
        jp      z,xop
        ld      de,#_nmuli
        cp      #'*'
        jp      z,xop
        ld      de,#_ndivi
        jp      xop
; vab: DE = registro a (nibble alto de vb2), BC = registro b (nibble bajo)
vab:    ld      a,(vb2)
        and     #15
        call    raddr
        push    hl
        ld      a,(vb2)
        rrca
        rrca
        rrca
        rrca
        and     #15
        call    raddr
        ex      de,hl
        pop     bc
        ret
; vrr: HL = registro r (C)
vrr:    ld      a,(vr)
        jr      raddr

; vmrun: corre el programa en HL
vmrun:  ld      (vpc),hl
vm1:    ld      hl,(vpc)
        ld      a,(hl)
        or      a
        ret     z
        inc     hl
        ld      c,a
        ld      a,(hl)
        inc     hl
        ld      (vb2),a
        ld      (vpc),hl
        ld      a,c
        and     #15
        ld      b,a
        ld      a,c
        rrca
        rrca
        rrca
        rrca
        and     #15
        ld      c,b             ; C = r
        ld      (vr),bc
        ld      hl,#vm1
        push    hl
        add     a,a
        ld      e,a
        ld      d,#0
        ld      hl,#vmtab
        add     hl,de
        ld      a,(hl)
        inc     hl
        ld      h,(hl)
        ld      l,a
        jp      (hl)
vmtab:  .dw     0,vadd,vsub,vmul,vdiv,vrnd,vpow,vsqr,vmov,vldk,vjz,vjlt,vsetc,vloop,vngo,vmisc
vadd:   ld      a,#'+'
        jr      vbin
vsub:   ld      a,#'-'
        jr      vbin
vmul:   ld      a,#'*'
        jr      vbin
vdiv:   ld      a,#'/'
vbin:   ld      (vop),a
        call    vrr
        push    hl
        call    vab
        pop     hl
        ld      a,(vop)
        jp      nop
vrnd:   ld      a,(vb2)         ; nround(r, a, d)
        and     #15
        push    af
        inc     sp
        call    vab
        push    de
        call    vrr
        push    hl
        call    _nround
        pop     af
        pop     af
        inc     sp
        ret
vpow:   call    vab             ; npow(r, a, b)
        push    bc
        push    de
        call    vrr
        push    hl
        call    _npow
        pop     af
        pop     af
        pop     af
        ret
vsqr:   call    vab             ; nsqrt(r, a)
        push    de
        call    vrr
        push    hl
        call    _nsqrt
        pop     af
        pop     af
        ld      a,l
        or      a
        ret     z
        ld      (_nerr),a
        ret
vmov:   call    vrr
        push    hl
        call    vab
        pop     hl
        ex      de,hl
vcpy:   ld      bc,#5
        ldir
        ret
vldk:   ld      a,(vb2)
        ld      l,a
        add     a,a
        add     a,a
        add     a,l
        ld      e,a
        ld      d,#0
        ld      hl,#ktab
        add     hl,de
        push    hl
        call    vrr
        ex      de,hl
        pop     hl
        jr      vcpy
vjz:    call    vrr
        call    iszero
        ret     nz
vjmp:   ld      a,(vb2)
        ld      e,a
        add     a,a
        sbc     a,a
        ld      d,a
        ld      hl,(vpc)
        add     hl,de
        ld      (vpc),hl
        ret
vjlt:   ld      hl,(vpc)        ; tercer byte: el salto
        ld      a,(hl)
        inc     hl
        ld      (vpc),hl
        push    af
        call    vab             ; r - a < 0
        ld      (oparg+4),de
        call    vrr
        ld      (oparg+2),hl
        ld      hl,#cmps
        ld      (oparg),hl
        call    nsubx
        ld      hl,#cmps
        call    nsign
        pop     bc
        cp      #2
        ret     nz
        ld      a,b
        ld      (vb2),a
        jr      vjmp
vsetc:  ld      a,(vb2)
        or      a
        jr      nz,vsc1
        ld      a,(_cfn)
vsc1:   ld      b,#0
        ld      hl,#vcnt
        add     hl,bc
        ld      (hl),a
        ret
vloop:  ld      b,#0
        ld      hl,#vcnt
        add     hl,bc
        dec     (hl)
        ret     z
        jr      vjmp
vngo:   call    vmov
        call    vrr
        ld      b,#4
        or      a
vng1:   ld      a,#0
        sbc     a,(hl)
        ld      (hl),a
        inc     hl
        djnz    vng1
        ret
vmisc:  ld      a,(vb2)
        or      a
        jr      nz,vms1
        ld      hl,(vfp)        ; LDF: el siguiente flujo
        push    hl
        ld      de,#5
        add     hl,de
        ld      (vfp),hl
        call    vrr
        ex      de,hl
        pop     hl
        jp      vcpy
vms1:   dec     a
        jr      nz,vms2
        ld      hl,#_cfb        ; RSTF
        ld      (vfp),hl
        ret
vms2:   ld      a,#1            ; ERR
        ld      (_nerr),a
        ret

vexp1:
        .db     0x9D,0x04             ; LDK R13,4
        .db     0x44,0x1D             ; DIV R4,R1,R13
        .db     0x54,0x40             ; RND R4,R4,0
        .db     0x00                  ; END
vexp2:
        .db     0x35,0x4D             ; MUL R5,R4,R13
        .db     0x25,0x15             ; SUB R5,R1,R5
        .db     0x90,0x01             ; LDK R0,1
        .db     0x96,0x01             ; LDK R6,1
        .db     0x97,0x00             ; LDK R7,0
        .db     0x9E,0x01             ; LDK R14,1
        .db     0xC0,0x10             ; SETC 0,16
        .db     0x17,0x7E             ; ADD R7,R7,R14
        .db     0x36,0x65             ; MUL R6,R6,R5
        .db     0x46,0x67             ; DIV R6,R6,R7
        .db     0x10,0x06             ; ADD R0,R0,R6
        .db     0xA6,0x02             ; JZ R6,E
        .db     0xD0,0xF4             ; LOOP 0,L
        .db     0x98,0x02             ; LDK R8,2
        .db     0x68,0x84             ; POW R8,R8,R4
        .db     0x30,0x08             ; MUL R0,R0,R8
        .db     0x00                  ; END
vln:
        .db     0x9E,0x01             ; LDK R14,1
        .db     0x9F,0x02             ; LDK R15,2
        .db     0x97,0x00             ; LDK R7,0
        .db     0x9C,0x00             ; LDK R12,0
        .db     0xB5,0xF0,0x06        ; JLT R5,R15,D
        .db     0x45,0x5F             ; DIV R5,R5,R15
        .db     0x17,0x7E             ; ADD R7,R7,R14
        .db     0xAC,0xF7             ; JZ R12,W
        .db     0x26,0x5E             ; SUB R6,R5,R14
        .db     0x18,0x5E             ; ADD R8,R5,R14
        .db     0x46,0x68             ; DIV R6,R6,R8
        .db     0x38,0x66             ; MUL R8,R6,R6
        .db     0x80,0x60             ; MOV R0,R6
        .db     0x8A,0x60             ; MOV R10,R6
        .db     0x9B,0x01             ; LDK R11,1
        .db     0xC0,0x18             ; SETC 0,24
        .db     0x1B,0xBF             ; ADD R11,R11,R15
        .db     0x3A,0xA8             ; MUL R10,R10,R8
        .db     0x44,0xAB             ; DIV R4,R10,R11
        .db     0xA4,0x04             ; JZ R4,E
        .db     0x10,0x04             ; ADD R0,R0,R4
        .db     0xD0,0xF4             ; LOOP 0,L
        .db     0x10,0x00             ; ADD R0,R0,R0
        .db     0x9D,0x04             ; LDK R13,4
        .db     0x34,0x7D             ; MUL R4,R7,R13
        .db     0x10,0x04             ; ADD R0,R0,R4
        .db     0x9D,0x05             ; LDK R13,5
        .db     0x34,0x9D             ; MUL R4,R9,R13
        .db     0x10,0x04             ; ADD R0,R0,R4
        .db     0x00                  ; END
vsin:
        .db     0x9D,0x03             ; LDK R13,3
        .db     0x1D,0xDD             ; ADD R13,R13,R13
        .db     0x45,0x1D             ; DIV R5,R1,R13
        .db     0x55,0x50             ; RND R5,R5,0
        .db     0x35,0x5D             ; MUL R5,R5,R13
        .db     0x25,0x15             ; SUB R5,R1,R5
        .db     0x38,0x55             ; MUL R8,R5,R5
        .db     0x80,0x50             ; MOV R0,R5
        .db     0x86,0x50             ; MOV R6,R5
        .db     0x97,0x01             ; LDK R7,1
        .db     0x9E,0x01             ; LDK R14,1
        .db     0x9F,0x02             ; LDK R15,2
        .db     0xC0,0x10             ; SETC 0,16
        .db     0x36,0x68             ; MUL R6,R6,R8
        .db     0x19,0x7E             ; ADD R9,R7,R14
        .db     0x1A,0x7F             ; ADD R10,R7,R15
        .db     0x39,0x9A             ; MUL R9,R9,R10
        .db     0x46,0x69             ; DIV R6,R6,R9
        .db     0xE6,0x60             ; NEG R6,R6
        .db     0x10,0x06             ; ADD R0,R0,R6
        .db     0x17,0x7F             ; ADD R7,R7,R15
        .db     0xA6,0x02             ; JZ R6,E
        .db     0xD0,0xEC             ; LOOP 0,L
        .db     0x00                  ; END
vatan:
        .db     0x9E,0x01             ; LDK R14,1
        .db     0x9F,0x02             ; LDK R15,2
        .db     0x85,0x10             ; MOV R5,R1
        .db     0x9C,0x00             ; LDK R12,0
        .db     0xBE,0x50,0x02        ; JLT R14,R5,I
        .db     0xAC,0x04             ; JZ R12,C
        .db     0x45,0xE5             ; DIV R5,R14,R5
        .db     0x9C,0x01             ; LDK R12,1
        .db     0xC1,0x02             ; SETC 1,2
        .db     0x38,0x55             ; MUL R8,R5,R5
        .db     0x18,0x8E             ; ADD R8,R8,R14
        .db     0x78,0x80             ; SQR R8,R8
        .db     0x18,0x8E             ; ADD R8,R8,R14
        .db     0x45,0x58             ; DIV R5,R5,R8
        .db     0xD1,0xF4             ; LOOP 1,H
        .db     0x38,0x55             ; MUL R8,R5,R5
        .db     0x80,0x50             ; MOV R0,R5
        .db     0x8A,0x50             ; MOV R10,R5
        .db     0x9B,0x01             ; LDK R11,1
        .db     0xC0,0x18             ; SETC 0,24
        .db     0x1B,0xBF             ; ADD R11,R11,R15
        .db     0x3A,0xA8             ; MUL R10,R10,R8
        .db     0xEA,0xA0             ; NEG R10,R10
        .db     0x44,0xAB             ; DIV R4,R10,R11
        .db     0xA4,0x04             ; JZ R4,E
        .db     0x10,0x04             ; ADD R0,R0,R4
        .db     0xD0,0xF2             ; LOOP 0,L
        .db     0x94,0x06             ; LDK R4,6
        .db     0x30,0x04             ; MUL R0,R0,R4
        .db     0xAC,0x06             ; JZ R12,X
        .db     0x9D,0x03             ; LDK R13,3
        .db     0x4D,0xDF             ; DIV R13,R13,R15
        .db     0x20,0xD0             ; SUB R0,R13,R0
        .db     0x00                  ; END
vfin:
        .db     0x9E,0x01             ; LDK R14,1
        .db     0x15,0x1E             ; ADD R5,R1,R14
        .db     0x65,0x52             ; POW R5,R5,R2
        .db     0x00                  ; END
vfv:
        .db     0x26,0x5E             ; SUB R6,R5,R14
        .db     0x46,0x61             ; DIV R6,R6,R1
        .db     0x30,0x36             ; MUL R0,R3,R6
        .db     0x00                  ; END
vpmt:
        .db     0x46,0xE5             ; DIV R6,R14,R5
        .db     0x26,0xE6             ; SUB R6,R14,R6
        .db     0x30,0x31             ; MUL R0,R3,R1
        .db     0x40,0x06             ; DIV R0,R0,R6
        .db     0x00                  ; END
vpv:
        .db     0x46,0xE5             ; DIV R6,R14,R5
        .db     0x26,0xE6             ; SUB R6,R14,R6
        .db     0x46,0x61             ; DIV R6,R6,R1
        .db     0x30,0x36             ; MUL R0,R3,R6
        .db     0x00                  ; END
vnpv:
        .db     0x9E,0x01             ; LDK R14,1
        .db     0x9C,0x00             ; LDK R12,0
        .db     0x80,0xC0             ; MOV R0,R12
        .db     0x89,0xC0             ; MOV R9,R12
        .db     0x15,0x1E             ; ADD R5,R1,R14
        .db     0x86,0xE0             ; MOV R6,R14
        .db     0x87,0xC0             ; MOV R7,R12
        .db     0xF0,0x01             ; RSTF
        .db     0xC0,0x00             ; SETC 0,0
        .db     0xF8,0x00             ; LDF R8
        .db     0x46,0x65             ; DIV R6,R6,R5
        .db     0x3A,0x86             ; MUL R10,R8,R6
        .db     0x10,0x0A             ; ADD R0,R0,R10
        .db     0x17,0x7E             ; ADD R7,R7,R14
        .db     0x3A,0xA7             ; MUL R10,R10,R7
        .db     0x4A,0xA5             ; DIV R10,R10,R5
        .db     0x29,0x9A             ; SUB R9,R9,R10
        .db     0xD0,0xEE             ; LOOP 0,L
        .db     0x00                  ; END
virr:
        .db     0xC3,0x28             ; SETC 3,40
        .db     0x9E,0x01             ; LDK R14,1
        .db     0x9C,0x00             ; LDK R12,0
        .db     0x80,0xC0             ; MOV R0,R12
        .db     0x89,0xC0             ; MOV R9,R12
        .db     0x15,0x1E             ; ADD R5,R1,R14
        .db     0x86,0xE0             ; MOV R6,R14
        .db     0x87,0xC0             ; MOV R7,R12
        .db     0xF0,0x01             ; RSTF
        .db     0xC0,0x00             ; SETC 0,0
        .db     0xF8,0x00             ; LDF R8
        .db     0x46,0x65             ; DIV R6,R6,R5
        .db     0x3A,0x86             ; MUL R10,R8,R6
        .db     0x10,0x0A             ; ADD R0,R0,R10
        .db     0x17,0x7E             ; ADD R7,R7,R14
        .db     0x3A,0xA7             ; MUL R10,R10,R7
        .db     0x4A,0xA5             ; DIV R10,R10,R5
        .db     0x29,0x9A             ; SUB R9,R9,R10
        .db     0xD0,0xEE             ; LOOP 0,K
        .db     0xA9,0x0A             ; JZ R9,F
        .db     0x4B,0x09             ; DIV R11,R0,R9
        .db     0x21,0x1B             ; SUB R1,R1,R11
        .db     0x5B,0xB7             ; RND R11,R11,7
        .db     0xAB,0x04             ; JZ R11,O
        .db     0xD3,0xD0             ; LOOP 3,T
        .db     0xF0,0x02             ; ERR
        .db     0x80,0x10             ; MOV R0,R1
        .db     0x00                  ; END
vcos0:  .db     0x9D,0x03       ; LDK R13,3
        .db     0x9F,0x02       ; LDK R15,2
        .db     0x4D,0xDF       ; DIV R13,R13,R15
        .db     0x11,0x1D       ; ADD R1,R1,R13
        .db     0
vdivr:  .db     0x40,0x30       ; DIV R0,R3,R0
        .db     0
vlog:   .db     0x9D,0x05       ; LDK R13,5
        .db     0x40,0x0D       ; DIV R0,R0,R13
        .db     0
vnow:   .db     0x9D,0x07       ; LDK R13,7
        .db     0x40,0x1D       ; DIV R0,R1,R13
        .db     0

; ldn: el registro A = DEHL (sin signo); con signo si nneg
ldn:    push    hl
        push    de
        call    raddr
        ld      (rptr),hl
        ld      hl,#0
        ld      (nexp),hl
        pop     de
        pop     hl
        jp      norm
; ntol: DEHL = la parte entera del registro A (>= 0, hasta 2^32)
ntol:   call    raddr
        push    hl
        push    hl
        ld      hl,#fy
        push    hl
        call    _ntrunc
        pop     af
        pop     af
        pop     af
        push    ix
        ld      ix,#fy
        call    ldmag
        pop     ix
        ld      a,(fy+4)
        or      a
        ret     z
        bit     7,a
        jr      nz,ntl9
ntl1:   push    af
        call    mul10
        pop     af
        dec     a
        jr      nz,ntl1
        ret
ntl9:   ld      hl,#0
        ld      d,h
        ld      e,l
        ret
; ntoiR: HL = ntoi(registro A)
ntoir:  call    raddr
        push    hl
        call    _ntoi
        pop     af
        ret

; leap: Z si el ano HL es bisiesto
leap:   ld      a,l
        and     #3
        ret     nz
        push    hl
        ld      de,#100
        call    hmod
        ld      a,h
        or      l
        pop     hl
        jr      z,lp4
        xor     a               ; no divisible por 100: bisiesto
        ret
lp4:    ld      de,#400
        call    hmod
        ld      a,h
        or      l
        ret
; hmod: HL = HL mod DE (HL >= 0)
hmod:   or      a
        sbc     hl,de
        jr      nc,hmod
        add     hl,de
        ret
; ylen: BC = dias del ano HL
ylen:   ld      bc,#365
        push    hl
        call    leap
        pop     hl
        ret     nz
        inc     bc
        ret
mdays:  .dw     0,31,59,90,120,151,181,212,243,273,304,334,365
; mdz: BC = dias antes del mes A (1-12) del ano HL, con el 29 de febrero
mdz:    push    hl
        push    af
        dec     a
        add     a,a
        ld      e,a
        ld      d,#0
        ld      hl,#mdays
        add     hl,de
        ld      c,(hl)
        inc     hl
        ld      b,(hl)
        pop     af
        pop     hl
        cp      #3
        ret     c
        push    hl
        push    bc
        call    leap
        pop     bc
        pop     hl
        ret     nz
        inc     bc
        ret
; serial: nser = el dia de ny/nm_/nd_ (1 = 1900-01-01)
serial: ld      hl,(nm_)        ; mes a 1-12
sr1:    ld      a,h
        bit     7,a
        jr      nz,sr2
        or      a
        jr      nz,sr1a
        ld      a,l
        cp      #13
        jr      c,sr3
sr1a:   ld      de,#-12
        add     hl,de
        ld      de,(ny)
        inc     de
        ld      (ny),de
        jr      sr1
sr2:    ld      de,#12          ; mes < 1
        add     hl,de
        ld      de,(ny)
        dec     de
        ld      (ny),de
        jr      sr1
sr3:    ld      a,l
        or      a
        jr      z,sr2
        ld      (nm_),hl
        ld      hl,#0
        ld      (nser),hl
        ld      (nser+2),hl
        ld      hl,#1900
sr4:    ld      de,(ny)
        or      a
        push    hl
        sbc     hl,de
        pop     hl
        jr      nc,sr5
        call    ylen
        call    addser
        inc     hl
        jr      sr4
sr5:    ld      a,(nm_)
        ld      hl,(ny)
        call    mdz
        call    addser
        ld      bc,(nd_)
; addser: nser += BC (con signo)
addser: push    hl
        ld      hl,(nser)
        add     hl,bc
        ld      (nser),hl
        ld      hl,(nser+2)
        ld      a,b
        add     a,a
        sbc     a,a
        ld      e,a
        ld      d,a
        adc     hl,de
        ld      (nser+2),hl
        pop     hl
        ret
; dsplit: el dia DEHL a ny, nm_, nd_; carry si esta fuera de 1900-2199
dsplit: ld      a,d
        or      e
        jr      nz,ds0
        ld      a,h
        or      l
        scf
        ret     z
ds0:    ld      (nser),hl
        ld      (nser+2),de
        ld      hl,#1900
ds1:    call    ylen            ; mientras n > largo del ano
        push    hl
        ld      hl,(nser+2)
        ld      a,h
        or      l
        jr      nz,ds2
        ld      hl,(nser)
        or      a
        sbc     hl,bc
        jr      c,ds3
        jr      z,ds3
ds2:    ld      hl,(nser)       ; n -= largo
        or      a
        sbc     hl,bc
        ld      (nser),hl
        ld      hl,(nser+2)
        ld      bc,#0
        sbc     hl,bc
        ld      (nser+2),hl
        pop     hl
        inc     hl
        ld      a,h             ; hasta 2199
        cp      #2200/256
        jr      c,ds1
        ld      a,l
        cp      #2200%256
        jr      c,ds1
        scf
        ret
ds3:    pop     hl
        ld      (ny),hl
        ld      a,#1            ; el mes
ds4:    cp      #12
        jr      z,ds5
        inc     a
        push    af
        call    mdz
        ld      hl,(nser)
        or      a
        sbc     hl,bc
        jr      z,ds4a
        jr      c,ds4a
        pop     af
        ld      hl,(ny)
        jr      ds4
ds4a:   pop     af
        dec     a
ds5:    ld      l,a
        ld      h,#0
        ld      (nm_),hl
        ld      hl,(ny)
        call    mdz
        ld      hl,(nser)
        or      a
        sbc     hl,bc
        ld      (nd_),hl
        or      a
        ret

; uint8_t datestr(char *o, const num *x, uint8_t nf): dd/mm/aa (13) o hh:mm (14)
_datestr::
        push    ix
        push    iy
        ld      hl,#6
        add     hl,sp
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      (fo),de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      a,(hl)
        ld      (vop),a
        push    de
        ld      a,#1
        call    raddr
        ex      de,hl
        pop     hl
        ld      bc,#5
        ldir                    ; R1 = x
        ld      a,(vop)
        cp      #14
        jr      z,dt5
        ld      a,#1
        call    ntol
        call    dsplit
        jr      c,dt9
        ld      hl,(fo)
        ld      a,(nd_)
        call    dt2
        ld      (hl),#'/'
        inc     hl
        ld      a,(nm_)
        call    dt2
        ld      (hl),#'/'
        inc     hl
        push    hl
        ld      hl,(ny)
        ld      de,#100
        call    hmod
        ld      a,l
        pop     hl
        call    dt2
        ld      (hl),#0
        ld      l,#8
        jr      dtend
dt5:    ld      a,#1            ; minutos del dia: R2 = INT(R1), luego vtm
        call    raddr
        push    hl
        ld      a,#2
        call    raddr
        push    hl
        call    _ntrunc
        pop     af
        pop     af
        ld      hl,#vtm
        call    vmrun
        ld      a,#2
        call    ntoir
        ld      a,h
        or      a
        jr      nz,dt6
        ld      a,l
dt6:    ld      de,#1440        ; 1440 -> 0
        or      a
        push    hl
        sbc     hl,de
        pop     hl
        jr      c,dt7
        ld      hl,#0
dt7:    ld      c,#0            ; horas
        ld      de,#60
dt8:    or      a
        sbc     hl,de
        jr      c,dt8a
        inc     c
        jr      dt8
dt8a:   add     hl,de
        ld      b,l
        ld      hl,(fo)
        ld      a,c
        call    dt2
        ld      (hl),#':'
        inc     hl
        ld      a,b
        call    dt2
        ld      (hl),#0
        ld      l,#5
        jr      dtend
dt9:    ld      l,#0
dtend:  pop     iy
        pop     ix
        ret
; dt2: A (0-99) como dos cifras en (hl)
dt2:    ld      c,#'0'-1
dt2a:   inc     c
        sub     #10
        jr      nc,dt2a
        add     a,#10+'0'
        ld      (hl),c
        inc     hl
        ld      (hl),a
        inc     hl
        ret
vtm:    .db     0x21,0x12       ; SUB R1,R1,R2  (la parte decimal)
        .db     0x9D,0x09       ; LDK R13,9     (1440)
        .db     0x31,0x1D       ; MUL R1,R1,R13
        .db     0x52,0x10       ; RND R2,R1,0
        .db     0

; void cfunc(val *v, val *a, uint8_t n, uint8_t id): las funciones F_PMT en adelante
_cfunc::
        push    ix
        push    iy
        ld      hl,#6
        add     hl,sp
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        push    de
        pop     ix
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      (vargs),de
        inc     hl
        ld      a,(hl)
        ld      (vid),a
        call    zerov
        xor     a
        ld      (_nerr),a
        ld      (vneg),a
        ld      (nneg),a
        call    raddr           ; R0 = 0
        ld      b,#5
cf0:    ld      (hl),#0
        inc     hl
        djnz    cf0
        ld      hl,(vargs)      ; R1-R3 = los argumentos
        ld      c,#1
cf1:    inc     hl
        push    hl
        push    bc
        ld      a,c
        call    raddr
        ex      de,hl
        pop     bc
        pop     hl
        push    bc
        ld      bc,#5
        ldir
        pop     bc
        inc     c
        ld      a,c
        cp      #4
        jr      c,cf1
        ld      a,(vid)
        sub     #20
        add     a,a
        ld      e,a
        ld      d,#0
        ld      hl,#cftab
        add     hl,de
        ld      a,(hl)
        inc     hl
        ld      h,(hl)
        ld      l,a
        ld      de,#cfend
        push    de
        jp      (hl)
cfend:  xor     a               ; v = R0
        call    raddr
        push    ix
        pop     de
        inc     de
        ld      bc,#5
        ldir
        ld      a,(_nerr)
        or      a
        jr      z,cfe1
        ld      0(ix),#V_ERR
cfe1:   pop     iy
        pop     ix
        ret
cftab:  .dw     cfpmt,cfpv,cffv,cfnpv,cfirr,cfdate,cftoday,cftoday,cfymd,cfymd,cfymd
        .dw     cfsin,cfcos,cftan,cfatan,cfln,cfexp,cflog

; r0r3r2: HL = R0, DE = R3, BC = R2
r0r3r2: ld      a,#2
        call    raddr
        push    hl
        ld      a,#3
        call    raddr
        push    hl
        xor     a
        call    raddr
        pop     de
        pop     bc
        ret
; r1z: Z si la tasa (R1) es 0
r1z:    ld      a,#1
        call    raddr
        jp      iszero
cfpmt:  call    r1z
        jr      nz,cfp1
        call    r0r3r2          ; sin interes: R3 / R2
        ld      a,#'/'
        jp      nop
cfp1:   ld      hl,#vfin
        call    vmrun
        ld      hl,#vpmt
        jp      vmrun
cfpv:   call    r1z
        jr      nz,cfv1
cfv0:   call    r0r3r2          ; sin interes: R3 * R2
        ld      a,#'*'
        jp      nop
cfv1:   ld      hl,#vfin
        call    vmrun
        ld      hl,#vpv
        jp      vmrun
cffv:   call    r1z
        jr      z,cfv0
        ld      hl,#vfin
        call    vmrun
        ld      hl,#vfv
        jp      vmrun
cfnpv:  ld      a,(_cfn)
        or      a
        ret     z
        ld      hl,#vnpv
        jp      vmrun
cfirr:  ld      a,(_cfn)
        or      a
        jr      z,cferr
        call    r1z
        jr      nz,cfi1
        ld      a,#1            ; sin tasa inicial: 0.1
        call    raddr
        ex      de,hl
        ld      hl,#ktab+40
        ld      bc,#5
        ldir
cfi1:   ld      hl,#virr
        jp      vmrun
cferr:  ld      a,#1
        ld      (_nerr),a
        ret
cfdate: ld      a,#1
        call    ntoir
        ld      (ny),hl
        ld      a,#2
        call    ntoir
        ld      (nm_),hl
        ld      a,#3
        call    ntoir
        ld      (nd_),hl
        call    serial
        ld      hl,(nser)
        ld      de,(nser+2)
        bit     7,d
        jr      nz,cferr
        xor     a
        jp      ldn
bdosx:  push    ix
        push    iy
        call    5
        pop     iy
        pop     ix
        ret
; bcd2: A en BCD a binario
bcd2:   ld      b,a
        and     #0xF0
        rrca
        ld      c,a
        rrca
        rrca
        add     a,c
        ld      c,a
        ld      a,b
        and     #15
        add     a,c
        ret
cftoday: ld     c,#12           ; reloj: CP/M 3 y MP/M (funcion 105)
        call    bdosx
        ld      a,l
        cp      #0x30
        jr      c,cft0
        ld      c,#105
        ld      de,#clkb
        call    bdosx
        ld      (vop),a         ; segundos
        ld      hl,(clkb)
        ld      a,h
        or      l
        jr      nz,cft1
cft0:   ld      0(ix),#V_NA
        ret
cft1:   ld      a,(vid)
        cp      #F_NOW
        jr      z,cfn1
        ld      de,#28489       ; dias desde 1978 -> desde 1900
        add     hl,de
        ld      de,#0
        jr      nc,cft2
        inc     de
cft2:   xor     a
        jp      ldn
cfn1:   ld      a,(clkb+2)      ; segundos del dia / 86400
        call    bcd2
        ld      l,a
        ld      h,#0
        add     hl,hl           ; * 60
        add     hl,hl
        ld      d,h
        ld      e,l
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        or      a
        sbc     hl,de
        push    hl
        ld      a,(clkb+3)
        call    bcd2
        pop     hl
        ld      e,a
        ld      d,#0
        add     hl,de           ; minutos
        ld      de,#0
        call    mul10           ; * 60
        add     hl,hl
        rl      e
        rl      d
        ld      (t32),hl
        ld      (t32+2),de
        add     hl,hl
        rl      e
        rl      d
        ld      bc,(t32)
        add     hl,bc
        ex      de,hl
        ld      bc,(t32+2)
        adc     hl,bc
        ex      de,hl
        push    hl
        push    de
        ld      a,(vop)
        call    bcd2
        pop     de
        pop     hl
        ld      c,a
        ld      b,#0
        add     hl,bc
        jr      nc,cfn2
        inc     de
cfn2:   ld      a,#1
        call    ldn
        ld      hl,#vnow
        jp      vmrun
cfymd:  ld      a,#1
        call    ntol
        call    dsplit
        jp      c,cferr
        ld      a,(vid)
        ld      hl,(ny)
        cp      #28
        jr      z,cfy1
        ld      hl,(nm_)
        cp      #29
        jr      z,cfy1
        ld      hl,(nd_)
cfy1:   ld      de,#0
        xor     a
        jp      ldn
cfsin:  ld      hl,#vsin
        jp      vmrun
cfcos:  ld      hl,#vcos0
        call    vmrun
        jr      cfsin
; rcp: copia el registro B al registro C
rcp:    push    bc
        ld      a,c
        call    raddr
        pop     bc
        push    hl
        ld      a,b
        call    raddr
        pop     de
        ld      bc,#5
        ldir
        ret
cftan:  ld      bc,#0x0102      ; R2 = x
        call    rcp
        call    cfsin
        ld      bc,#0x0003      ; R3 = sen
        call    rcp
        ld      bc,#0x0201      ; R1 = x
        call    rcp
        call    cfcos
        xor     a
        call    raddr
        call    iszero
        jp      z,cferr
        ld      hl,#vdivr
        jp      vmrun
; negr: el registro A cambia de signo
negr:   call    raddr
        ld      b,#4
        or      a
ngr1:   ld      a,#0
        sbc     a,(hl)
        ld      (hl),a
        inc     hl
        djnz    ngr1
        ret
cfatan: ld      a,#1
        call    raddr
        inc     hl
        inc     hl
        inc     hl
        bit     7,(hl)
        jr      z,cfa1
        ld      a,#1
        ld      (vneg),a
        call    negr
cfa1:   ld      hl,#vatan
        call    vmrun
        ld      a,(vneg)
        or      a
        ret     z
        xor     a
        jr      negr
cfln:   ld      a,#1            ; x > 0
        call    raddr
        push    hl
        call    iszero
        pop     hl
        jp      z,cferr
        push    hl
        inc     hl
        inc     hl
        inc     hl
        bit     7,(hl)
        pop     hl
        jp      nz,cferr
        push    ix              ; e' = cifras - 1 + e
        push    hl
        pop     ix
        call    exp10
        pop     ix
        ld      (vop),a
        ld      bc,#0x0105      ; R5 = x / 10^e'
        call    rcp
        ld      a,#5
        call    raddr
        ld      de,#4
        add     hl,de
        ld      a,(vop)
        ld      b,a
        ld      a,(hl)
        sub     b
        ld      (hl),a
        ld      a,(vop)         ; R9 = e'
        bit     7,a
        jr      z,cfl1
        neg
        ld      b,a
        ld      a,#1
        ld      (nneg),a
        ld      a,b
cfl1:   ld      l,a
        ld      h,#0
        ld      de,#0
        ld      a,#9
        call    ldn
        xor     a
        ld      (nneg),a
        ld      hl,#vln
        jp      vmrun
cfexp:  ld      hl,#vexp1
        call    vmrun
        ld      a,#4
        call    ntoir
        bit     7,h
        jr      nz,cfx1
        ld      de,#331
        or      a
        sbc     hl,de
        jp      nc,cferr
        jr      cfx2
cfx1:   ld      de,#331
        add     hl,de
        ret     nc              ; muy negativo: 0
cfx2:   ld      hl,#vexp2
        jp      vmrun
cflog:  call    cfln
        ld      a,(_nerr)
        or      a
        ret     nz
        ld      hl,#vlog
        jp      vmrun

; la marca de esta version, que tambien lleva ZCALC.OVL
_ovlmark::
        .dw     l__CODE, s__HEAP

; ------------------------------------------------------------------ textos
; Un val de texto (V_STR) apunta a las letras: de una celda de texto, de la formula
; ("..."), del lugar de su formula (un bloque del heap) o de spool, donde van los
; textos que se arman al calcular. spool se vacia en cada expr y se recupera al
; terminar cada celda (evcell).
SPSZ    = 400
        .area   _DATA
spool:  .ds     SPSZ
spend:
spp:    .ds     2
tsp0:    .ds     2               ; el texto del argumento 0
tsl0:    .ds     1
tsp1:    .ds     2               ; y el del 1
tsl1:    .ds     1
sfl:    .ds     1
sdst:   .ds     2

        .area   _CODE
; salloc: HL = lugar para BC letras en spool; carry si no hay
salloc: ld      hl,(spp)
        push    hl
        add     hl,bc
        ex      de,hl
        ld      hl,#spend
        or      a
        sbc     hl,de
        pop     hl
        ret     c
        ld      (spp),de
        ret
; tostr: HL = val -> DE letras, B largo (un numero se escribe en spool); carry si no hay lugar
tostr:  ld      a,(hl)
        cp      #V_STR
        jr      nz,tsn
        inc     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      b,(hl)
        or      a
        ret
tsn:    inc     hl
        ld      de,#fx
        ld      bc,#5
        ldir
        ld      bc,#24
        call    salloc
        ret     c
        ld      (fo),hl
        push    hl
        ld      a,#0xFF
        ld      (fdec),a
        ld      a,#22
        ld      (fmax),a
        push    ix
        push    iy
        call    plain
        or      a
        jr      nz,tsn1
        call    sci
tsn1:   pop     iy
        pop     ix
        pop     de
        ld      b,a
        ld      l,a
        ld      h,#0
        add     hl,de
        ld      (spp),hl
        or      a
        ret
; iscmp: Z si A es una comparacion
iscmp:  cp      #'='
        ret     z
        cp      #'<'
        ret     z
        cp      #'>'
        ret     z
        cp      #TK_LE
        ret     z
        cp      #TK_GE
        ret     z
        cp      #TK_NE
        ret
; upc: A en mayuscula
upc:    cp      #'a'
        ret     c
        cp      #'z'+1
        ret     nc
        sub     #32
        ret
; lwc: A en minuscula
lwc:    cp      #'A'
        ret     c
        cp      #'Z'+1
        ret     nc
        add     a,#32
        ret
; evscmp: compara los textos (ix) y (iy) sin mirar mayusculas; C = la comparacion
evscmp: push    bc
        ld      e,1(ix)
        ld      d,2(ix)
        ld      l,1(iy)
        ld      h,2(iy)
        ld      b,3(ix)
        ld      c,3(iy)
evs1:   ld      a,b
        or      a
        jr      z,evs4
        ld      a,c
        or      a
        jr      z,evsp          ; a es mas largo
        ld      a,(hl)
        call    upc
        push    af
        ld      a,(de)
        call    upc
        pop     af
        push    hl
        ld      l,a
        ld      a,(de)
        call    upc
        cp      l
        pop     hl
        jr      c,evsn
        jr      nz,evsp
        inc     de
        inc     hl
        dec     b
        dec     c
        jr      evs1
evs4:   ld      a,c
        or      a
        jr      nz,evsn
        xor     a
        jr      evs9
evsp:   ld      a,#1
        jr      evs9
evsn:   ld      a,#2
evs9:   pop     bc
        jp      ecmp
; evcat: (ix) = (ix) & (iy)
evcat:  ld      a,0(ix)
        cp      #V_ERR
        jr      z,evce
        ld      a,0(iy)
        cp      #V_ERR
        jr      z,evce
        ld      a,0(ix)
        cp      #V_NA
        ret     z
        ld      a,0(iy)
        cp      #V_NA
        jr      z,evcn
        push    ix
        pop     hl
        call    tostr
        jr      c,evce
        ld      (tsp0),de
        ld      a,b
        ld      (tsl0),a
        push    iy
        pop     hl
        call    tostr
        jr      c,evce
        ld      (tsp1),de
        ld      a,b
        ld      (tsl1),a
        ld      a,(tsl0)
        add     a,b
        jr      c,evce
        cp      #241
        jr      nc,evce
        ld      c,a
        ld      b,#0
        push    bc
        call    salloc
        pop     bc
        jr      c,evce
        ld      1(ix),l
        ld      2(ix),h
        ld      3(ix),c
        ld      0(ix),#V_STR
        ex      de,hl
        ld      hl,(tsp0)
        ld      a,(tsl0)
        or      a
        jr      z,evc1
        ld      c,a
        ld      b,#0
        ldir
evc1:   ld      hl,(tsp1)
        ld      a,(tsl1)
        or      a
        ret     z
        ld      c,a
        ld      b,#0
        ldir
        ret
evce:   ld      0(ix),#V_ERR
        ret
evcn:   ld      0(ix),#V_NA
        ret

; stval: guarda en la celda (iy) el texto del val en HL (libera el que tenia).
; zalloc y zfree son de zcalc.c (y pueden cambiar ix e iy)
stval:  ld      a,4(iy)
        and     #0x30
        cp      #0x30
        jr      nz,stv1
        ld      e,7(iy)
        ld      d,8(iy)
        xor     a
        ld      7(iy),a
        ld      8(iy),a
        ld      a,d
        or      e
        jr      z,stv1
        push    hl
        push    iy
        ex      de,hl
        call    _zfree          ; (sdcccall 1: HL)
        pop     iy
        pop     hl
stv1:   ld      a,(hl)
        cp      #V_STR
        ret     nz
        push    hl
        inc     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      c,(hl)
        pop     hl
        ld      a,c
        or      a
        jr      z,stv0
        push    hl
        push    de
        push    bc
        push    iy
        ld      l,c
        ld      h,#0
        call    _zalloc         ; (sdcccall 1: HL -> DE)
        ex      de,hl
        pop     iy
        pop     bc
        pop     de
        ld      a,h
        or      l
        jr      z,stverr
        push    hl
        ex      de,hl
        ld      b,#0
        ldir
        pop     de
        pop     hl
        inc     hl
        ld      (hl),e
        inc     hl
        ld      (hl),d
        inc     hl
        inc     hl
        ld      (hl),#0
        inc     hl
        ld      (hl),#0
        ret
stverr: pop     hl
        ld      (hl),#V_ERR
        ret
stv0:   inc     hl
        ld      (hl),#0
        inc     hl
        ld      (hl),#0
        ret

; funciones de texto (marco de fscal: a0 a1 a2 en 0-17, n en 18, id en 19)
fstr:   cp      #F_ISSTR
        jr      nz,fst1
        ld      a,0(iy)
        cp      #V_STR
        jp      fsbool
fst1:   cp      #F_ISNUM
        jr      nz,fst2
        ld      a,0(iy)
        or      a
        jp      fsbool
fst2:   ld      b,18(iy)        ; ERROR gana a NA
        push    iy
        pop     hl
        ld      c,#0
fst2a:  ld      a,(hl)
        cp      #V_ERR
        jr      z,fst2e
        cp      #V_NA
        jr      nz,fst2b
        ld      c,a
fst2b:  ld      de,#6
        add     hl,de
        djnz    fst2a
        ld      a,c
        or      a
        jr      z,fst3
fst2e:  ld      0(ix),a
        jp      fsend
fst3:   ld      a,19(iy)
        sub     #F_LEFT
        add     a,a
        ld      e,a
        ld      d,#0
        ld      hl,#fstab
        add     hl,de
        ld      a,(hl)
        inc     hl
        ld      h,(hl)
        ld      l,a
        jp      (hl)
fstab:  .dw     sleft,sright,smid,slen,supper,slower,sproper,strim,svalue,sstring
        .dw     sfind,srepeat,schar,scode,sexact
fserr:  ld      0(ix),#V_ERR
        jp      fsend
; sarg: HL = el argumento A
sarg:   ld      l,a
        add     a,a
        add     a,l
        add     a,a
        ld      e,a
        ld      d,#0
        push    iy
        pop     hl
        add     hl,de
        ret
; sa0 / sa1: el texto del argumento 0 / 1 en tsp0 tsl0 / tsp1 tsl1 (salta a fserr si no hay lugar)
sa0:     xor     a
        call    sarg
        call    tostr
        jr      c,sxerr
        ld      (tsp0),de
        ld      a,b
        ld      (tsl0),a
        ret
sa1:     ld      a,#1
        call    sarg
        call    tostr
        jr      c,sxerr
        ld      (tsp1),de
        ld      a,b
        ld      (tsl1),a
        ret
sxerr:  pop     hl
        jr      fserr
; iarg: HL = el entero del argumento A (salta a fserr si es texto)
iarg:   call    sarg
        ld      a,(hl)
        or      a
        jr      nz,sxerr
        inc     hl
        push    ix
        push    iy
        push    hl
        call    _ntoi
        pop     af
        pop     iy
        pop     ix
        ret
; cl8: A = HL entre 0 y 255
cl8:    xor     a
        bit     7,h
        ret     nz
        ld      a,h
        or      a
        ld      a,l
        ret     z
        ld      a,#255
        ret
; setstr: el resultado es el texto DE, largo B
setstr: ld      0(ix),#V_STR
        ld      1(ix),e
        ld      2(ix),d
        ld      3(ix),b
        ld      4(ix),#0
        ld      5(ix),#0
        jp      fsend
; ldsl: DE = tsp0, B = tsl0
ldsl:   ld      de,(tsp0)
        ld      a,(tsl0)
        ld      b,a
        ret
sleft:  call    sa0
        ld      a,#1
        call    iarg
        call    cl8
        ld      c,a
        call    ldsl
        ld      a,c
        cp      b
        jr      nc,slf1
        ld      b,a
slf1:   jp      setstr
sright: call    sa0
        ld      a,#1
        call    iarg
        call    cl8
        ld      c,a
        call    ldsl
        ld      a,c
        cp      b
        jr      nc,srt1
        ld      a,b             ; desde len - n
        sub     c
        add     a,e
        ld      e,a
        adc     a,d
        sub     e
        ld      d,a
        ld      b,c
srt1:   jp      setstr
smid:   call    sa0
        ld      a,#1
        call    iarg
        call    cl8
        or      a
        jr      nz,sm1
        inc     a
sm1:    ld      (sfl),a         ; desde (1 = la primera)
        ld      a,#2
        call    iarg
        call    cl8
        ld      c,a
        call    ldsl
        ld      a,(sfl)
        dec     a
        cp      b
        jr      c,sm2
        ld      b,#0
        jp      setstr
sm2:    push    af
        add     a,e
        ld      e,a
        adc     a,d
        sub     e
        ld      d,a
        pop     af
        neg
        add     a,b             ; lo que queda
        cp      c
        jr      c,sm3
        ld      a,c
sm3:    ld      b,a
        jp      setstr
slen:   call    sa0
        ld      a,(tsl0)
        ld      l,a
        ld      h,#0
        call    setvi
        jp      fsend
; scopy: lugar en spool (sdst) para una copia del argumento 0
scopy:  call    sa0
        ld      a,(tsl0)
        ld      c,a
        ld      b,#0
        call    salloc
        jp      c,fserr
        ex      de,hl
        ld      hl,(tsp0)
        ld      a,(tsl0)
        ld      b,a
        ld      (sdst),de
        ret                     ; HL = de donde, DE = a donde, B = largo
supper: call    scopy
sup1:   ld      a,b
        or      a
        jr      z,scend
        ld      a,(hl)
        call    upc
        ld      (de),a
        inc     hl
        inc     de
        dec     b
        jr      sup1
scend:  ld      de,(sdst)
        ld      a,(tsl0)
        ld      b,a
        jp      setstr
slower: call    scopy
slw1:   ld      a,b
        or      a
        jr      z,scend
        ld      a,(hl)
        call    lwc
        ld      (de),a
        inc     hl
        inc     de
        dec     b
        jr      slw1
sproper: call   scopy
        ld      c,#1            ; la que sigue empieza palabra
spr1:   ld      a,b
        or      a
        jr      z,scend
        ld      a,(hl)
        bit     0,c
        jr      z,spr2
        call    upc
        jr      spr3
spr2:   call    lwc
spr3:   ld      (de),a
        ld      c,#0
        call    upc
        call    isupa
        jr      nc,spr4
        call    isdga
        jr      nc,spr4
        ld      c,#1
spr4:   inc     hl
        inc     de
        dec     b
        jr      spr1
strim:  call    scopy           ; sin espacios al principio, al final ni dobles
        ld      c,#1            ; 1: lo anterior es un espacio (o el principio)
strm1:  ld      a,b
        or      a
        jr      z,strm3
        ld      a,(hl)
        inc     hl
        dec     b
        cp      #' '
        jr      nz,strm2
        bit     0,c
        jr      nz,strm1
        ld      c,#1
        ld      (de),a
        inc     de
        jr      strm1
strm2:  ld      c,#0
        ld      (de),a
        inc     de
        jr      strm1
strm3:  ld      hl,(sdst)       ; el principio
        ld      a,c             ; sin el espacio del final
        or      a
        jr      z,strm4
        ld      a,e
        cp      l
        jr      nz,strm3a
        ld      a,d
        cp      h
        jr      z,strm4
strm3a: dec     de
strm4:  ex      de,hl           ; HL = fin, DE = principio
        or      a
        sbc     hl,de
        ld      b,l
        jp      setstr
svalue: call    sa0              ; el numero escrito en el texto
        ld      a,(tsl0)
        inc     a
        ld      c,a
        ld      b,#0
        call    salloc
        jp      c,fserr
        push    hl
        ex      de,hl
        ld      hl,(tsp0)
        ld      a,(tsl0)
        or      a
        jr      z,sv0
        ld      c,a
        ld      b,#0
        ldir
sv0:    xor     a
        ld      (de),a
        pop     hl
sv1:    ld      a,(hl)          ; espacios y signo
        cp      #' '
        jr      nz,sv2
        inc     hl
        jr      sv1
sv2:    ld      c,#0
        cp      #'+'
        jr      z,sv3
        cp      #'-'
        jr      nz,sv4
        inc     c
sv3:    inc     hl
sv4:    ld      a,(hl)
        call    isdga
        jr      nc,sv5
        cp      #'.'
        jp      nz,fserr
sv5:    push    bc
        xor     a
        ld      (_nerr),a
        push    ix
        pop     de
        inc     de
        push    ix
        push    iy
        push    de
        push    hl
        call    _pnum
        pop     af
        pop     af
        pop     iy
        pop     ix
        pop     bc
        ld      a,(_nerr)
        or      a
        jp      nz,fserr
sv6:    ld      a,(hl)
        cp      #' '
        jr      nz,sv7
        inc     hl
        jr      sv6
sv7:    or      a
        jp      nz,fserr
        ld      0(ix),#0
        ld      a,c
        or      a
        call    nz,negv
        jp      fsend
sstring: ld     a,0(iy)         ; el numero como texto, con n decimales
        or      a
        jp      nz,fserr
        xor     a
        ld      (sfl),a
        ld      a,18(iy)
        cp      #2
        jr      c,sst1
        ld      a,#1
        call    iarg
        call    cl8
        cp      #10
        jr      c,sst0
        ld      a,#9
sst0:   ld      (sfl),a
sst1:   push    ix              ; nround(fx, a0, n)
        push    iy
        ld      a,(sfl)
        push    af
        inc     sp
        push    iy
        pop     hl
        inc     hl
        push    hl
        ld      hl,#fx
        push    hl
        call    _nround
        pop     af
        pop     af
        inc     sp
        pop     iy
        pop     ix
        ld      bc,#24
        call    salloc
        jp      c,fserr
        ld      (fo),hl
        push    hl
        ld      a,(sfl)
        ld      (fdec),a
        ld      a,#22
        ld      (fmax),a
        push    ix
        push    iy
        call    plain
        or      a
        jr      nz,sst2
        call    sci
sst2:   pop     iy
        pop     ix
        pop     de
        ld      b,a
        ld      l,a
        ld      h,#0
        add     hl,de
        ld      (spp),hl
        jp      setstr
sfind:  call    sa0              ; donde esta el texto 0 en el 1 (desde el 1 = la primera)
        call    sa1
        ld      c,#1
        ld      a,18(iy)
        cp      #3
        jr      c,sf1
        ld      a,#2
        call    iarg
        call    cl8
        or      a
        jp      z,fserr
        ld      c,a
sf1:    ld      a,(tsl1)         ; c = posicion (1...); hasta tsl1 - tsl0 + 1
        ld      b,a
        ld      a,(tsl0)
        ld      e,a
        ld      a,b
        sub     e
        jp      c,fserr
        inc     a
        ld      b,a             ; ultima posicion posible
sf2:    ld      a,b
        cp      c
        jp      c,fserr
        push    bc
        ld      hl,(tsp1)
        ld      e,c
        dec     e
        ld      d,#0
        add     hl,de
        ld      de,(tsp0)
        ld      a,(tsl0)
        or      a
        jr      z,sf4
        ld      b,a
sf3:    ld      a,(de)
        cp      (hl)
        jr      nz,sf5
        inc     de
        inc     hl
        djnz    sf3
sf4:    pop     bc
        ld      l,c
        ld      h,#0
        call    setvi
        jp      fsend
sf5:    pop     bc
        inc     c
        jr      sf2
srepeat: call   sa0
        ld      a,#1
        call    iarg
        call    cl8
        ld      c,a             ; veces
        ld      a,(tsl0)
        ld      e,a
        ld      d,#0
        ld      hl,#0
        ld      b,c
        ld      a,b
        or      a
        jr      z,srp1
srp0:   add     hl,de
        djnz    srp0
srp1:   ld      a,h
        or      a
        jp      nz,fserr
        ld      a,l
        cp      #241
        jp      nc,fserr
        push    hl
        push    bc
        ld      b,#0
        ld      c,l
        call    salloc
        pop     bc
        pop     de              ; e = largo total
        jp      c,fserr
        push    hl
        push    de
        ex      de,hl
srp2:   ld      a,c
        or      a
        jr      z,srp3
        ld      hl,(tsp0)
        ld      a,(tsl0)
        or      a
        jr      z,srp3
        push    bc
        ld      c,a
        ld      b,#0
        ldir
        pop     bc
        dec     c
        jr      srp2
srp3:   pop     bc
        ld      b,c
        pop     de
        jp      setstr
schar:  xor     a
        call    iarg
        call    cl8
        push    af
        ld      bc,#1
        call    salloc
        pop     bc
        jp      c,fserr
        ld      (hl),b
        ex      de,hl
        ld      b,#1
        jp      setstr
scode:  call    sa0
        ld      a,(tsl0)
        or      a
        jp      z,fserr
        ld      hl,(tsp0)
        ld      l,(hl)
        ld      h,#0
        call    setvi
        jp      fsend
sexact: call    sa0
        call    sa1
        ld      hl,#0
        ld      a,(tsl0)
        ld      b,a
        ld      a,(tsl1)
        cp      b
        jr      nz,sex2
        ld      de,(tsp0)
        ld      hl,(tsp1)
        or      a
        jr      z,sex1
sex0:   ld      a,(de)
        cp      (hl)
        jr      nz,sex1n
        inc     de
        inc     hl
        djnz    sex0
sex1:   ld      hl,#1
        jr      sex2
sex1n:  ld      hl,#0
sex2:   call    setvi
        jp      fsend

; ------------------------------------------------------------------ para los .WKS
        .area   _DATA
bm:     .ds     8
bd:     .ds     4
bR:     .ds     4
bq:     .ds     8
bt:     .ds     4
bnb:    .ds     1
bi:     .ds     1
bk:     .ds     1
        .area   _CODE
; uint8_t bx10(uint8_t *m): m (8 bytes) = m * 10; 1 si no cabe
_bx10::
        pop     bc
        pop     hl
        push    hl
        push    bc
        call    sh8             ; m * 2
        jr      c,bx9
        push    hl
        ld      de,#bm
        ld      bc,#8
        ldir
        ld      hl,#bm          ; bm = m * 8
        call    sh8
        jr      c,bx8
        call    sh8
        jr      c,bx8
        pop     hl
        ld      de,#bm          ; m = m * 2 + m * 8
        ld      b,#8
        or      a
bx4:    ld      a,(de)
        adc     a,(hl)
        ld      (hl),a
        inc     hl
        inc     de
        djnz    bx4
        ld      l,#0
        ret     nc
bx9:    ld      l,#1
        ret
bx8:    pop     hl
        jr      bx9
; sh8: (hl) de 8 bytes un bit a la izquierda; carry el que sale (hl no cambia)
sh8:    push    hl
        ld      b,#8
        or      a
sh8a:   rl      (hl)
        inc     hl
        djnz    sh8a
        pop     hl
        ret
; uint8_t bdiv(uint8_t *m, uint32_t d, uint8_t *q): los primeros 53 bits de m / d
; (m de 8 bytes) en q (8 bytes; el de arriba es 1); devuelve cuantos pasos dio:
; el ultimo bit vale 2^(64 - pasos)
_bdiv::
        ld      hl,#2
        add     hl,sp
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        push    hl
        ex      de,hl
        ld      de,#bm
        ld      bc,#8
        ldir
        pop     hl
        ld      de,#bd
        ld      bc,#4
        ldir
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        push    de
        xor     a
        ld      hl,#bR
        ld      b,#12
bdv0:   ld      (hl),a          ; r = q = 0
        inc     hl
        djnz    bdv0
        ld      (bnb),a
        ld      (bi),a
bdv1:   ld      a,(bnb)
        cp      #53
        jp      z,bdv9
        ld      a,(bi)
        cp      #180
        jp      z,bdv9
        inc     a
        ld      (bi),a
        ld      hl,#bm          ; m <<= 1 (sale el bit de arriba)
        ld      b,#8
        or      a
bdv1a:  rl      (hl)
        inc     hl
        djnz    bdv1a
        ld      hl,#bR          ; r = r << 1 | bit
        ld      b,#4
bdv1b:  rl      (hl)
        inc     hl
        djnz    bdv1b
        ld      hl,#bR          ; bt = r - d
        ld      de,#bd
        ld      bc,#bt
        ld      a,#4
        ld      (bk),a
        or      a
bdv2:   ld      a,(de)
        ld      (bc),a
        ld      a,(hl)
        push    hl
        ld      h,b
        ld      l,c
        sbc     a,(hl)
        ld      (hl),a
        pop     hl
        inc     hl
        inc     de
        inc     bc
        push    af
        ld      a,(bk)
        dec     a
        ld      (bk),a
        jr      z,bdv2e
        pop     af
        jr      bdv2
bdv2e:  pop     af
        ccf                     ; carry = 1 si r >= d
        jr      nc,bdv3
        ld      hl,#bt
        ld      de,#bR
        ld      bc,#4
        ldir
        scf
bdv3:   ld      a,(bnb)
        jr      c,bdv4
        or      a
        jp      z,bdv1          ; todavia ceros adelante
        or      a
bdv4:   ld      hl,#bq          ; q = q << 1 | bit
        ld      b,#8
bdv4a:  rl      (hl)
        inc     hl
        djnz    bdv4a
        ld      hl,#bnb
        inc     (hl)
        jp      bdv1
bdv9:   pop     de
        ld      hl,#bq
        ld      bc,#8
        ldir
        ld      a,(bi)
        ld      l,a
        ret
