#!/usr/bin/env python3
"""z80back.py - lleva a Z80 (CP/M) el ensamblador 6502 que genera COMPILATOR.

COMPILATOR (lang/compiler.py del SBC 6502) es de una pasada y escribe codigo
65C02 mientras lee el fuente. En vez de un segundo generador de codigo, este
programa traduce esa salida (y su biblioteca RT_*) instruccion por instruccion:

  registros   A -> A, X -> B, Y -> C; HL, DE y AF' son de trabajo
  acarreo     el C del Z80 lleva siempre el acarreo con el sentido del 6502:
              tras SUB/SBC/CP se invierte con CCF, CLC es SCF+CCF
  Z y N       el 6502 los pone al cargar (LDA, TAX, PLA...); el Z80 no. Antes de
              un BEQ/BNE/BMI/BPL que dependa de una carga se agrega INC r / DEC r,
              que pone Z y S sin tocar el acarreo
  AND ORA EOR el 6502 no toca el acarreo: se guarda y se repone (EOR #$FF es CPL)
  monitor     CHRIN, CHKIN, CHROUT, CRLF, PRBYTE y PRSTR pasan a rutinas que
              usan el BDOS de CP/M; MAIN vuelve a CP/M

  python3 z80back.py prog.s -o prog.z80     # despues: zmac prog.z80 -> prog.COM
"""
import re, sys

API = {0xFF00: "Z_MON", 0xFF03: "Z_CHRIN", 0xFF06: "Z_CHROUT", 0xFF09: "Z_CHKIN",
       0xFF0C: "Z_PRBYTE", 0xFF12: "Z_CRLF", 0xFF15: "Z_PRSTR"}
APIN = {"CHRIN": "Z_CHRIN", "CHROUT": "Z_CHROUT", "CHKIN": "Z_CHKIN", "CRLF": "Z_CRLF",
        "PRBYTE": "Z_PRBYTE", "PRSTR": "Z_PRSTR"}
REG = {"a": "A", "x": "B", "y": "C"}


class Err(Exception):
    pass


def num(tok):
    """$FF -> 0FFh, %0101 -> 0101b, 'A' tal cual"""
    tok = re.sub(r"\$([0-9A-Fa-f]+)", lambda m: "0" + m.group(1).upper() + "h", tok)
    tok = re.sub(r"%([01]+)", r"\1b", tok)
    return tok


def expr(e, scope):
    e = e.strip()
    e = re.sub(r"@(\w+)", lambda m: f"{scope}_{m.group(1)}", e)
    if e.startswith("<"):
        return f"0+(({num(e[1:])}) & 255)"
    if e.startswith(">"):
        return f"0+(({num(e[1:])}) >> 8)"
    return num(e)


class Tr:
    def __init__(self):
        self.code, self.data, self.bss, self.consts = [], [], [], []
        self.seg = "CODE"
        self.scope = "G"
        self.flag = None        # registro cuyo valor deberia estar en Z/N (None = Z80 ya los tiene)
        self.pend_bne = None    # "bne *+5" esperando el jmp
        self.bss_off = 0

    def o(self, *l):
        self.code.extend("        " + x for x in l)

    def addr(self, op):
        """operando de memoria -> (expr de la direccion, indice)"""
        m = re.fullmatch(r"\((.+)\),\s*y", op, re.I)
        if m:
            return expr(m.group(1), self.scope), "indy"
        m = re.fullmatch(r"\((.+)\)", op)
        if m:
            return expr(m.group(1), self.scope), "ind"
        m = re.fullmatch(r"(.+),\s*([xy])", op, re.I)
        if m:
            return expr(m.group(1), self.scope), "idx" + m.group(2).lower()
        return expr(op, self.scope), "abs"

    def hl(self, op):
        """deja en HL la direccion efectiva (sin tocar A ni el acarreo)"""
        a, mode = self.addr(op)
        if mode == "abs":
            self.o(f"LD HL,{a}")
        elif mode == "ind":
            self.o(f"LD HL,({a})")
        else:
            base = f"LD HL,({a})" if mode == "indy" else f"LD HL,{a}"
            r = "C" if mode in ("indy", "idxy") else "B"
            self.o("EX AF,AF'", base, f"LD E,{r}", "LD D,0", "ADD HL,DE", "EX AF,AF'")

    def src(self, op):
        """operando fuente para A: inmediato o (HL)"""
        if op.startswith("#"):
            return expr(op[1:], self.scope)
        self.hl(op)
        return "(HL)"

    def test_flags(self):
        if self.flag and self.flag != "?":
            r = self.flag
            self.o(f"INC {r}", f"DEC {r}")
            self.flag = None

    def logic(self, z80op, op):
        if op == "#$FF" and z80op == "XOR":
            self.o("CPL")
            self.flag = "A"
            return
        s = self.src(op)
        # guardar el acarreo en H... pero (HL) puede ser el operando: usar la pila
        self.o("PUSH AF")              # F con el acarreo en el byte bajo
        self.o(f"{z80op} {s}")
        self.o("EX (SP),HL", "LD H,A", "LD A,L", "RRA", "LD A,H", "POP HL")
        self.flag = "A"

    def ins(self, mn, op):
        mn = mn.lower()
        if self.pend_bne is not None:
            if mn == "jmp":
                self.o(f"JP {self.pend_bne},{expr(op, self.scope)}")
                self.pend_bne = None
                return
            raise Err("'*+5' sin jmp despues")
        if mn in ("lda", "ldx", "ldy"):
            r = REG[mn[2]]
            if op.startswith("#"):
                self.o(f"LD {r},{expr(op[1:], self.scope)}")
            elif r == "A":
                a, mode = self.addr(op)
                if mode == "abs":
                    self.o(f"LD A,({a})")
                else:
                    self.hl(op)
                    self.o("LD A,(HL)")
            else:
                self.hl(op)
                self.o(f"LD {r},(HL)")
            self.flag = r
        elif mn in ("sta", "stx", "sty", "stz"):
            r = {"sta": "A", "stx": "B", "sty": "C", "stz": "0"}[mn]
            a, mode = self.addr(op)
            if mode == "abs" and r == "A":
                self.o(f"LD ({a}),A")
            else:
                self.hl(op)
                self.o(f"LD (HL),{r}")
        elif mn in ("tax", "tay", "txa", "tya"):
            d, s = REG[mn[2]], REG[mn[1]]
            self.o(f"LD {d},{s}")
            self.flag = d
        elif mn == "pha":
            self.o("PUSH AF")
        elif mn == "pla":
            self.o("EX (SP),HL", "LD A,H", "POP HL")      # A del byte alto; F actual intacto
            self.flag = "A"
        elif mn == "phx":
            self.o("PUSH BC")
        elif mn == "plx":
            self.o("EX (SP),HL", "LD B,H", "POP HL")
            self.flag = "B"
        elif mn == "phy":
            self.o("PUSH BC")
        elif mn == "ply":
            self.o("EX (SP),HL", "LD C,L", "POP HL")
            self.flag = "C"
        elif mn in ("inx", "iny", "dex", "dey"):
            self.o(("INC " if mn[0] == "i" else "DEC ") + REG[mn[2]])
            self.flag = None
        elif mn in ("inc", "dec") and op.lower() in ("", "a"):
            self.o(f"{mn.upper()} A")
            self.flag = None
        elif mn in ("inc", "dec"):
            self.hl(op)
            self.o(f"{mn.upper()} (HL)")
            self.flag = None
        elif mn == "clc":
            self.o("SCF", "CCF")
        elif mn == "sec":
            self.o("SCF")
        elif mn == "adc":
            self.o(f"ADC A,{self.src(op)}")
            self.flag = None
        elif mn == "sbc":
            s = self.src(op)
            self.o("CCF", f"SBC A,{s}", "CCF")
            self.flag = None
        elif mn in ("cmp", "cpx", "cpy"):
            s = self.src(op)
            if mn == "cmp":
                self.o(f"CP {s}", "CCF")
            else:
                self.o("LD E,A", f"LD A,{REG[mn[2]]}", f"CP {s}", "CCF", "LD A,E")
            self.flag = None
        elif mn in ("and", "ora", "eor"):
            self.logic({"and": "AND", "ora": "OR", "eor": "XOR"}[mn], op)
        elif mn in ("asl", "lsr", "rol", "ror"):
            z = {"asl": "SLA", "lsr": "SRL", "rol": "RL", "ror": "RR"}[mn]
            if op.lower() in ("", "a"):
                self.o(f"{z} A")
            else:
                self.hl(op)
                self.o(f"{z} (HL)")
            self.flag = None
        elif mn == "bit":
            # N = bit 7 de la memoria, Z = (A AND M) = 0; V no se usa en lo generado
            self.hl(op)
            self.o("LD E,A", "LD A,(HL)", "OR A", "LD A,E")   # S = bit 7 de M (solo se usa BPL/BMI)
            self.flag = None
        elif mn in ("beq", "bne", "bmi", "bpl"):
            if op.replace(" ", "") == "*+5" and mn in ("bne", "beq"):
                self.test_flags()
                self.pend_bne = "Z" if mn == "bne" else "NZ"
                return
            self.test_flags()
            cc = {"beq": "Z", "bne": "NZ", "bmi": "M", "bpl": "P"}[mn]
            self.o(f"JP {cc},{expr(op, self.scope)}")
        elif mn in ("bcc", "bcs", "bvc", "bvs"):
            cc = {"bcc": "NC", "bcs": "C", "bvc": "PO", "bvs": "PE"}[mn]
            self.o(f"JP {cc},{expr(op, self.scope)}")
        elif mn in ("bra", "jmp"):
            self.test_flags()
            self.o(f"JP {self.target(op)}")
        elif mn == "jsr":
            self.test_flags()
            self.o(f"CALL {self.target(op)}")
            self.flag = None
        elif mn == "rts":
            self.test_flags()
            self.o("RET")
        elif mn == "nop":
            self.o("NOP")
        else:
            raise Err(f"instruccion 6502 sin traduccion: {mn} {op}")

    def target(self, op):
        try:
            v = int(op[1:], 16) if op.startswith("$") else None
        except ValueError:
            v = None
        if v in API:
            return API[v]
        if op in APIN:
            return APIN[op]
        return expr(op, self.scope)

    def directive(self, d, rest, label):
        d = d.lower()
        dst = self.code if self.seg == "CODE" else self.data
        if d in (".setcpu", ".include", ".export", ".import"):
            return
        if d == ".zeropage":
            self.seg = "DATA"
            return
        if d == ".segment":
            s = rest.strip().strip('"')
            if s == "VECTORS":
                raise Err("segmento VECTORS: el programa no es para una CPU sola")
            self.seg = {"CODE": "CODE", "RODATA": "DATA", "DATA": "DATA", "BSS": "BSS",
                        "ZEROPAGE": "DATA"}.get(s, "DATA")
            return
        if d == ".res":
            n = expr(rest.split(",")[0], self.scope)
            if self.seg == "BSS":
                self.bss.append(f"{label or ''}")
                self.bss.append(n)
                return
            dst.append(f"{label + ':' if label else ''}        DEFS {n}")
            return
        if d in (".byte", ".word"):
            items = []
            for it in re.findall(r'"[^"]*"|[^,]+', rest):
                it = it.strip()
                if it.startswith('"'):
                    items += [str(ord(c)) for c in it[1:-1]]
                else:
                    items.append(expr(it, self.scope))
            if self.seg == "CODE" and not label:
                raise Err("CODE [ ... ] inserta codigo de maquina 6502: no se puede llevar al Z80")
            dw = "DEFB" if d == ".byte" else "DEFW"
            dst.append(f"{label + ':' if label else ''}        {dw} {','.join(items)}")
            return
        raise Err(f"directiva sin traduccion: {d} {rest}")

    def line(self, ln):
        ln = re.sub(r";.*$", "", ln).rstrip()
        if not ln.strip():
            return
        m = re.match(r"^(\w+)\s*=\s*(.+)$", ln)
        if m:
            if m.group(1) in APIN:
                return
            if m.group(1).startswith(("V_", "A_")):
                print(f"aviso: {m.group(1)} esta en una direccion fija ({m.group(2)}); en CP/M "
                      "esa memoria puede ser del programa", file=sys.stderr)
            self.consts.append(f"{m.group(1)} EQU {expr(m.group(2), self.scope)}")
            return
        label = None
        m = re.match(r"^(@?\w+):\s*(.*)$", ln)
        if m:
            label, ln = m.group(1), m.group(2)
            if label.startswith("@"):
                label = f"{self.scope}_{label[1:]}"
            else:
                self.scope = label
        parts = ln.split(None, 1)
        if parts and parts[0].startswith("."):
            self.directive(parts[0], parts[1] if len(parts) > 1 else "", label)
            return
        if label:
            if self.seg == "CODE":
                if self.flag not in (None, "?"):
                    self.test_flags()
                self.code.append(f"{label}:")
                self.flag = "?"
            elif self.seg == "BSS":
                self.bss.append(label)
                self.bss.append("0")
            else:
                self.data.append(f"{label}:")
        if parts:
            if self.seg != "CODE":
                raise Err(f"instruccion fuera de CODE: {ln}")
            if self.flag == "?":
                self.flag = None
            self.ins(parts[0], parts[1].strip() if len(parts) > 1 else "")

    def finish(self):
        out = ["; traducido por z80back.py desde la salida de COMPILATOR (ACTIO)"]
        out += self.consts
        out += ["        ORG 100h", "        LD SP,Z_STACK", "        CALL Z_START", "        JP 0",
                "Z_START:"]
        out += self.code
        out += ["INCLUDE z80rt.inc"]
        out += self.data
        out += ["        DEFS 256", "Z_STACK:", "Z_BSS:"]
        lab = []
        for i in range(0, len(self.bss), 2):
            name, n = self.bss[i], self.bss[i + 1]
            if name:
                out.append(f"{name} EQU Z_BSS+{self.bss_off_expr(lab)}")
            lab.append(n)
        return "\n".join(out) + "\n        END\n"

    @staticmethod
    def bss_off_expr(sizes):
        return "+".join(["0"] + [f"({s})" for s in sizes])


def translate(text):
    t = Tr()
    for i, ln in enumerate(text.splitlines(), 1):
        try:
            t.line(ln)
        except Err as e:
            raise Err(f"linea {i}: {e}\n  {ln}")
    return t.finish()


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("-o", "--out")
    a = ap.parse_args()
    try:
        z = translate(open(a.src).read())
    except Err as e:
        sys.exit(f"z80back: {e}")
    open(a.out or re.sub(r"\.s$", "", a.src) + ".z80", "w").write(z)
