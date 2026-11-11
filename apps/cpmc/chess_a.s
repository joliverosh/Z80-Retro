; chess_a.s - lo que mas usa la busqueda de CHESS, en ensamblador
; uint8_t attacked(uint8_t s, uint8_t by): 1 si alguna pieza de by (0 blancas, 8 negras)
; ataca la casilla s. Recorre las piezas de by (pl, np) y mira con amask si desde su
; casilla se puede llegar a s; las que se deslizan siguen astep hasta s o hasta topar.
; (C) OLIVEROS 2026
        .module chess_a
        .globl  _attacked
        .area   _CODE
_attacked:
        push    iy
        ld      c, a            ; c = s
        ld      a, l
        or      a
        ld      iy, #_pl
        ld      hl, #_np
        jr      z, 1$
        ld      iy, #_pl+16
        inc     hl
1$:     ld      b, (hl)
        inc     b
        jr      3$
2$:     ld      a, 0 (iy)       ; f: la casilla de la pieza
        inc     iy
        ld      (at_f), a
        ld      hl, #_b         ; la pieza
        add     a, l
        ld      l, a
        adc     a, h
        sub     l
        ld      h, a
        ld      e, (hl)
        ld      hl, #_pbit      ; su bit
        ld      a, e
        add     a, l
        ld      l, a
        adc     a, h
        sub     l
        ld      h, a
        ld      d, (hl)
        ld      a, (at_f)       ; la distancia: s - f + 119
        ld      l, a
        ld      a, c
        sub     l
        add     a, #119
        ld      (at_d), a
        ld      hl, #_amask
        add     a, l
        ld      l, a
        adc     a, h
        sub     l
        ld      h, a
        ld      a, (hl)
        and     d
        jr      z, 3$
        ld      a, d            ; peon, caballo o rey: ataca
        and     #0x47
        jr      nz, 5$
        ld      a, (at_d)       ; las que se deslizan: el paso
        ld      hl, #_astep
        add     a, l
        ld      l, a
        adc     a, h
        sub     l
        ld      h, a
        ld      d, (hl)
        ld      a, (at_f)
4$:     add     a, d
        cp      c
        jr      z, 5$
        ld      e, a
        ld      hl, #_b
        add     a, l
        ld      l, a
        adc     a, h
        sub     l
        ld      h, a
        ld      a, (hl)
        or      a
        ld      a, e
        jr      z, 4$
3$:     djnz    2$
        xor     a
        pop     iy
        ret
5$:     ld      a, #1
        pop     iy
        ret
        .area   _DATA
at_f:   .ds     1
at_d:   .ds     1
