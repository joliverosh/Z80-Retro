/* zbov3.c - parte de ZBAS.OVL: los mensajes de error, RUN (donde estan las etiquetas,
   SUB y FUNCTION), RENUM y FILES
   (C) OLIVEROS 2026 */
/* mk: --max-allocs-per-node 200000 */
#include "zbas.h"
void resolve(void);

#define EMSGS "Out of memory\0" "Line too long\0" "Number too large\0" "Bad character\0" "Syntax error\0" "Number expected\0" "Text expected\0" "Already DIMmed\0" "Too many subscripts\0" "Bad subscripts\0" "Subscript out of range\0" "Type mismatch\0" "Not a value\0" "Overflow\0" "Division by zero\0" "Too many arguments\0" "Bad arguments\0" "No clock\0" "Bad function value\0" "Negative SQR\0" "File not open\0" "Empty text\0" "FOR without NEXT\0" "WHILE without WEND\0" "DO without LOOP\0" "IF without END IF\0" "SELECT without END SELECT\0" "Missing END SUB\0" "Variable expected\0" "Not a variable\0" "Disk full\0" "FOR INPUT, OUTPUT or APPEND\0" "Files are #1 to #4\0" "Bad file name\0" "Cannot create\0" "File not found\0" "Past end of file\0" "Not a number\0" "Break\0" "Out of DATA\0" "Too deep\0" "No such line\0" "No such label\0" "Label expected\0" "Too many locals\0" "Undefined function\0" "Undefined SUB\0" "END SUB without CALL\0" "NEXT without FOR\0" "Internal error\0" "WEND without WHILE\0" "LOOP without DO\0" "EXIT outside its block\0" "RETURN without GOSUB\0" "LOCAL outside SUB\0" "Cannot continue\0" "END in FUNCTION\0"
const char emsgs[] = EMSGS;
/* ---------------------------------------------------------------- las ordenes del interprete */
void renum(uint16_t st, uint16_t inc)
{
    uint8_t *l, *p, *q;
    uint16_t n = st, old, nw;
    /* primero las referencias: cada numero viejo pasa al nuevo */
    for (l = prog; l < pend; l += LLEN(l))
        for (p = LTOK(l); *p != T_END; p += tsize(p))
            if (*p == T_LNUM) {
                old = p[1] | p[2] << 8;
                nw = st;
                for (q = prog; q < pend && LNUM(q) != old; q += LLEN(q)) nw += inc;
                if (q < pend) { p[1] = nw; p[2] = nw >> 8; }
            }
    for (l = prog; l < pend; l += LLEN(l)) { l[2] = n; l[3] = n >> 8; n += inc; }
}
void files_(void)
{
    NAME12 *nl = xalloc(64 * sizeof(NAME12));
    uint8_t n, i, k;
    n = glob("*.*", nl, 64);
    for (i = 0; i < n; i++) {
        for (k = 1; k < 12; k++) { if (k == 9) conc('.'); conc(nl[i][k] & 0x7F); }
        cons(i % 5 == 4 ? "\n" : "   ");
    }
    if (n % 5) cons("\n");
    zfree(nl);
}
void startrun(void)
{
    clearvars();
    growvars();
    resolve();
    if (prog == pend) { running = 0; return; }
    goline(prog);
    jumped = 0;
    running = 1;
}


void ovl_entry(uint8_t op)
{
    switch (op) {
    case OV_ERR: {                       /* el mensaje errn (ovk: decir la linea) */
        const char *m = emsgs;
        uint8_t n = errn;
        while (--n) m += strlen(m) + 1;
        cons(m);
        if (errline && ovk) { char b[8]; cons(" in "); b[utoa_(errline, b)] = 0; cons(b); }
        cons("\n");
        break;
    }
    case OV_RUN: startrun(); break;
    case OV_RENUM: renum(ovn1, ovn2); break;
    case OV_FILES: files_(); break;
    }
}
