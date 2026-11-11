/* zbov1.c - parte de ZBAS.OVL: compilar las lineas que se escriben (y AUTO), guardarlas,
   DELETE y LOAD
   (C) OLIVEROS 2026 */
/* mk: --max-allocs-per-node 200000 */
#include "zbas.h"
void resolve(void);

extern const char kwp[];
const char *kw(uint8_t k);
/* busca o crea el nombre s (n letras) de la clase k (las de parentesis comparten nombre) */
uint16_t sym(const char *s, uint8_t n, uint8_t k)
{
    static uint8_t *p, i, pk;
    static uint16_t idx;
    pk = k >= S_NARR && k != S_LABEL;   /* nombre( : matriz, sub o funcion */
    for (p = names, idx = 0; p < nend; p += 2 + p[1], idx++) {
        if ((p[0] >= S_NARR && p[0] != S_LABEL) != pk || p[1] != n || (p[0] == S_LABEL) != (k == S_LABEL)) continue;
        for (i = 0; i < n && p[2 + i] == up(s[i]); i++) ;
        if (i == n) {
            if (k > p[0] && k != S_LABEL) p[0] = k;   /* una SUB o FUNCTION define la clase */
            return idx;
        }
    }
    if (nend + 2 + n >= dbase) {         /* sin lugar para el nombre: se corren los datos */
        if (freel == (fb *)dbase && freel->sz >= 128) {
            fb *f = (fb *)(dbase + 64);
            f->sz = freel->sz - 64; f->nx = freel->nx;
            freel = f; dbase += 64; hfree -= 64;
        } else clearvars();
        if (nend + 2 + n >= dbase) error(1);
    }
    p = nend;
    p[0] = k; p[1] = n;
    for (i = 0; i < n; i++) p[2 + i] = up(s[i]);
    nend += 2 + n;
    return nsym++;
}
uint8_t cb[256];          /* la linea compilada */
uint8_t cn;
void put(uint8_t b) { if (cn >= 250) error(2); cb[cn++] = b; }
/* compila lb en cb; devuelve el largo */
uint8_t compile(const char *s)
{
    static uint8_t k, n, i, j, prev, isstr, stmt, golist;
    static const char *t;
    static num v;
    cn = 0;
    prev = 0; stmt = 1; golist = 0;
    while (*s) {
        if (*s == ' ' || *s == '\t') { s++; continue; }
        if (*s == '"') {                         /* texto */
            s++;
            put(T_STR); j = cn; put(0);
            while (*s && *s != '"') { put(*s++); cb[j]++; }
            if (*s) s++;
            prev = T_STR; stmt = 0;
            continue;
        }
        if (*s == '\'') { put(T_RAW); while (*s) put(*s++); break; }   /* comentario */
        if (isdg(*s) || (*s == '.' && isdg(s[1]))) {
            if (prev == K_GOTO || prev == K_GOSUB || prev == K_THEN || prev == K_ELSE || prev == K_RESTORE || (prev == ',' && golist) ||
                (prev == T_LNUM && s[-1] != ' ' ) || (stmt && 0)) {
                uint16_t ln = 0;
                while (isdg(*s)) ln = ln * 10 + *s++ - '0';
                put(T_LNUM); put(ln); put(ln >> 8);
                prev = T_LNUM; stmt = 0;
                continue;
            }
            nerr = 0;
            t = pnum(s, &v);
            if (nerr) error(3);
            s = t;
            put(T_NUM); for (i = 0; i < 5; i++) put(((uint8_t *)&v)[i]);
            prev = T_NUM; stmt = 0;
            continue;
        }
        if (*s == '&' && (up(s[1]) == 'H')) {    /* &H1F */
            uint16_t hv = 0;
            s += 2;
            while (isdg(*s) || (up(*s) >= 'A' && up(*s) <= 'F')) { hv = hv * 16 + (isdg(*s) ? *s - '0' : up(*s) - 'A' + 10); s++; }
            nset(&v, 0); mk32(&v, hv, 0, 0);
            put(T_NUM); for (i = 0; i < 5; i++) put(((uint8_t *)&v)[i]);
            prev = T_NUM; stmt = 0;
            continue;
        }
        if (isal(*s)) {
            for (n = 0; isal(s[n]) || isdg(s[n]); n++) ;
            isstr = s[n] == '$';
            /* una palabra? (con $ si la tiene) */
            for (k = 0, t = kwp; k < NKW; k++, t += strlen(t) + 1) {
                const char *w = t;
                for (i = 0; w[i] && up(s[i]) == w[i]; i++) ;
                if (!w[i] && !(isal(s[i]) || isdg(s[i]) || (s[i] == '$' && w[i - 1] != '$'))) break;
            }
            if (k < NKW) {
                k += 0x80;
                s += strlen(kw(k - 0x80));
                if (k == K_REM) { put(T_RAW); while (*s == ' ') s++; while (*s) put(*s++); break; }
                put(k);
                if (k == K_DATA) { put(T_RAW); while (*s == ' ') s++; while (*s) put(*s++); break; }
                prev = k;
                stmt = k == K_THEN || k == K_ELSE;
                if (k == K_GOTO || k == K_GOSUB) golist = 1; else if (stmt) golist = 0;
                continue;
            }
            /* un nombre */
            t = s + n + isstr;
            while (*t == ' ') t++;
            if (stmt && *t == ':' && !isstr) {   /* una etiqueta */
                { uint16_t ix = sym(s, n, S_LABEL); put(T_ID); put(ix); put(ix >> 8); }
                put(':');
                s = t + 1;
                prev = ':'; stmt = 1;
                continue;
            }
            if (prev == K_GOTO || prev == K_GOSUB || prev == K_RESTORE || (prev == ',' && golist)) k = S_LABEL;
            else if (prev == K_SUB) k = S_SUB;
            else if (prev == K_FUNCTION) k = isstr ? S_SFUNC : S_FUNC;
            else if (*t == '(' || prev == K_CALL) k = isstr ? S_SARR : S_NARR;
            else k = isstr ? S_STR : S_NUM;
            if (k == S_SUB || k == S_FUNC || k == S_SFUNC || (prev == K_CALL)) { if (prev == K_CALL) k = S_SUB; }
            { uint16_t ix = sym(s, n + isstr, k); put(T_ID); put(ix); put(ix >> 8); }
            if (k == S_FUNC || k == S_SFUNC) sym(s, n + isstr, isstr ? S_STR : S_NUM);   /* su resultado */
            s += n + isstr;
            prev = T_ID; stmt = 0;
            continue;
        }
        /* signos */
        if (*s == '<' && s[1] == '=') { put(K_LE); s += 2; prev = K_LE; stmt = 0; continue; }
        if (*s == '>' && s[1] == '=') { put(K_GE); s += 2; prev = K_GE; stmt = 0; continue; }
        if (*s == '<' && s[1] == '>') { put(K_NE); s += 2; prev = K_NE; stmt = 0; continue; }
        if (*s == '?') { put(K_PRINT); s++; prev = K_PRINT; stmt = 0; continue; }
        if (strchr("+-*/^\\=<>(),;:#&", *s)) {
            put(*s);
            stmt = *s == ':';
            if (stmt) golist = 0;
            prev = *s++;
            continue;
        }
        error(4);
    }
    put(T_END);
    return cn;
}
/* pone la linea n con las palabras de cb (o la borra si cn es 1) */
void storeline(uint16_t n)
{
    static uint8_t *p;
    static uint16_t old, nw, d;
    clearvars();                         /* (cierra los archivos antes de mover nada) */
    p = findline(n, 0);
    old = (p < pend && LNUM(p) == n) ? LLEN(p) : 0;
    nw = cn > 1 ? cn + 6 : 0;
    if (nw > old) {
        d = nw - old;
        if (nend + d >= htop - 512) error(1);
        { uint8_t *q = nend + d, *e = p + d; while (q != e) { q--; *q = q[-d]; } }   /* hacia arriba */
    } else if (nw < old) {
        d = old - nw;
        memcpy(p, p + d, nend - (p + d));       /* (copia hacia abajo: sirve) */
    }
    pend += nw - old;
    names += nw - old;
    nend += nw - old;
    if (nw) {
        p[0] = nw; p[1] = nw >> 8; p[2] = n; p[3] = n >> 8;
        LJMP(p) = 0xFFFF;
        memcpy(p + 6, cb, cn);
    }
    heapinit();
}
FCB lf;
uint8_t lbuf[128], lpos;
uint16_t lrec;
uint8_t loadfile(const char *nm)  /* 0 bien, 1 no esta */
{
    int16_t c;
    uint8_t n;
    uint16_t num_, last = 0;
    char *s;
    if (!mkfcb(&lf, nm) || fopen(&lf)) return 1;
    newprog();
    lpos = 128; lrec = 0;
    for (;;) {
        n = 0;
        for (;;) {
            if (lpos == 128) { if (fread(&lf, lbuf)) { c = -1; break; } lpos = 0; }
            c = lbuf[lpos++];
            if (c == 0x1A) { c = -1; break; }
            if (c == 10) break;
            if (c != 13 && n < 250) lb[n++] = c;
        }
        lb[n] = 0;
        s = lb;
        while (*s == ' ' || *s == '\t') s++;
        if (*s) {
            num_ = 0;
            if (isdg(*s)) { while (isdg(*s)) num_ = num_ * 10 + *s++ - '0'; }
            else num_ = last + 10;
            if (num_ <= last) num_ = last + 1;
            errline = num_;
            compile(s);
            storeline(num_);
            last = num_;
        }
        if (c < 0) break;
    }
    fclose(&lf);
    errline = 0;
    return 0;
}
/* ---------------------------------------------------------------- el interprete */
void numline(char *s)     /* "120 PRINT ..." : guarda la linea */
{
    uint16_t n = 0;
    while (isdg(*s)) n = n * 10 + *s++ - '0';
    if (*s == ' ') s++;
    errline = n;
    if (!*s) { cn = 1; storeline(n); return; }
    compile(s);
    storeline(n);
}
/* una linea del teclado: la guarda si tiene numero, o la deja en direct y ovret 1 */
void oneline(void)
{
    char *s;
    if (autoon) {
        char *o = lb;
        o += utoa_(autonum, o); *o++ = ' '; *o = 0;
        if (!getline_(o - lb)) { autoon = 0; return; }
        if (!lb[o - lb]) { autoon = 0; prompt_ok(); return; }
        numline(lb);
        autonum += autoinc;
        return;
    }
    lb[0] = 0;
    if (!getline_(0)) return;
    s = lb;
    while (*s == ' ') s++;
    if (!*s) return;
    if (isdg(*s)) { numline(s); return; }
    errline = 0;
    cn = compile(s);
    if (cb[0] == K_AUTO || cb[0] == K_EDIT) {   /* AUTO [n[,i]] y EDIT n */
        uint8_t *t = cb + 1;
        uint16_t n1 = 10, n2 = 10;
        num x;
        if (*t == T_NUM) { memcpy(&x, t + 1, 5); n1 = ntoi(&x); t += 6; }
        if (*t == ',' && t[1] == T_NUM) { memcpy(&x, t + 2, 5); n2 = ntoi(&x); }
        if (cb[0] == K_AUTO) { autoon = 1; autonum = n1; autoinc = n2; return; }
        if (!findline(n1, 1)) error(42);
        ovn1 = n1; ovret = 2;            /* EDIT: la escribe zbov2 */
        return;
    }
    direct[0] = 0; direct[1] = 0; direct[2] = 0; direct[3] = 0;
    memcpy(LTOK(direct), cb, cn);
    if (!resolved && prog != pend) resolve();   /* para llamar a las SUB y saltar a las etiquetas */
    ovret = 1;
}
void ovl_entry(uint8_t op)
{
    switch (op) {
    case OV_LINE: oneline(); break;
    case OV_NUMLINE: numline(lb); break;
    case OV_LOAD: if (loadfile(fnb)) error(36); break;
    case OV_DELETE: {
        uint8_t *l;
        for (l = prog; l < pend; ) if (LNUM(l) >= ovn1 && LNUM(l) <= ovn2) { cn = 1; storeline(LNUM(l)); } else l += LLEN(l);
        break;
    }
    }
}
