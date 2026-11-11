; znum_a.s - los numeros decimales de 9 cifras de ZCALC y ZBAS: aritmetica, numeros a texto y de texto, y las funciones (finanzas, fechas, trigonometria) en una pequena calculadora de registros (sdcccall 0: todo en la pila)
; q es un numero de 8 bytes, el byte bajo primero.
; lo que tambien usa zcalc_a.s
        .globl  _naddi
        .globl  _ndivi
        .globl  _nmuli
        .globl  cmps
        .globl  fdec
        .globl  fmax
        .globl  fmtn
        .globl  fnf
        .globl  fo
        .globl  fx
        .globl  iszero
        .globl  negv
        .globl  nsign
        .globl  nsubx
        .globl  oparg
        .globl  plain
        .globl  sci
        .globl  setvi
        .globl  u2s
        .globl  xop
        .globl  zerov
F_TODAY = 26
F_NOW   = 27
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


; ------------------------------------------------------------------ ayudas para las rutinas de num
V_ERR   = 1
V_NA    = 2
V_STR   = 3
        .area   _DATA
oparg:  .ds     6               ; r, a, b para las rutinas de num
nsbt:   .ds     5
cmps:   .ds     5
        .area   _CODE
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

; ------------------------------------------------------------------ numeros con formato
        .area   _DATA
fz:     .ds     5
fnf:    .ds     1
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

