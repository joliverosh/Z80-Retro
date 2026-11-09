; z80rt.inc - el "monitor" de los programas ACTIO traducidos a Z80: las rutinas
; del monitor del SBC 6502 sobre el BDOS de CP/M. Conservan B y C (X e Y).
Z_CHROUT:
        PUSH AF
        PUSH BC
        PUSH DE
        PUSH HL
        LD E,A
        LD C,2
        CALL 5
        POP HL
        POP DE
        POP BC
        POP AF
        RET
; CHKIN: CY = 1 y A = tecla si hay una; CY = 0 si no
Z_CHKIN:
        PUSH BC
        PUSH DE
        PUSH HL
        LD C,6
        LD E,0FFh
        CALL 5
        POP HL
        POP DE
        POP BC
        OR A
        RET Z
        SCF
        RET
Z_CHRIN:
        CALL Z_CHKIN
        JR NC,Z_CHRIN
        RET
Z_CRLF: LD A,13
        CALL Z_CHROUT
        LD A,10
        JP Z_CHROUT
Z_PRBYTE:
        PUSH AF
        RRCA
        RRCA
        RRCA
        RRCA
        CALL Z_PRHEX
        POP AF
Z_PRHEX:
        PUSH AF
        AND 0Fh
        ADD A,90h
        DAA
        ADC A,40h
        DAA
        CALL Z_CHROUT
        POP AF
        RET
; PRSTR: cadena terminada en 0, A = byte bajo, X (B) = byte alto
Z_PRSTR:
        PUSH HL
        LD L,A
        LD H,B
Z_PRS1: LD A,(HL)
        OR A
        JR Z,Z_PRS2
        CALL Z_CHROUT
        INC HL
        JR Z_PRS1
Z_PRS2: POP HL
        RET
Z_MON:  JP 0
