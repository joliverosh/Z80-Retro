/* c/ejemplos/sed.c - sed-milla: filtro de stdin a stdout con sustitucion s/RE/repl/.
 * Proyecto Semilla, version 1. */
/* sed-milla: filtro de stdin a stdout.  La 1ra linea es el comando de
   sustitucion  s/RE/repl/[g]  (cualquier delimitador tras la s); el resto de
   las lineas se transforman.  RE: literales . * + ? ^ $ [..] \c (como grep).
   En repl, & es el texto casado y \& un & literal.  Igual en las 8 maquinas. */
#include <stdio.h>

int atomlen(char *re)
{
    int n;
    if (re[0] == '\\' && re[1]) return 2;
    if (re[0] == '[') {
        n = 1;
        if (re[n] == '^') n++;
        if (re[n] == ']') n++;
        while (re[n] && re[n] != ']') n++;
        return re[n] == ']' ? n + 1 : n;
    }
    return 1;
}
int matchatom(char *re, int L, int c)
{
    int i, neg, lo, ok;
    if (c == '\0') return 0;
    if (re[0] == '\\') return re[1] == c;
    if (re[0] == '.') return 1;
    if (re[0] == '[') {
        i = 1; neg = 0;
        if (re[i] == '^') { neg = 1; i++; }
        ok = 0;
        while (i < L - 1) {
            if (re[i + 1] == '-' && i + 2 < L - 1) {
                lo = re[i];
                if (c >= lo && c <= re[i + 2]) ok = 1;
                i += 3;
            } else { if (re[i] == c) ok = 1; i++; }
        }
        return neg ? !ok : ok;
    }
    return re[0] == c;
}
/* devuelve el puntero en text justo despues del match, o 0 si no casa aqui */
char *mh(char *re, char *text);
char *mrep(char *re, int L, char *resto, char *text, int min)
{
    char *t, *r;
    int n;
    t = text; n = 0;
    while (matchatom(re, L, *t)) { t++; n++; }
    while (n >= min) { r = mh(resto, text + n); if (r) return r; n--; }
    return 0;
}
char *mh(char *re, char *text)
{
    int L;
    char *r;
    if (re[0] == '\0') return text;
    if (re[0] == '$' && re[1] == '\0') return *text == '\0' ? text : 0;
    L = atomlen(re);
    if (re[L] == '*') return mrep(re, L, re + L + 1, text, 0);
    if (re[L] == '+') return mrep(re, L, re + L + 1, text, 1);
    if (re[L] == '?') {
        if (*text && matchatom(re, L, *text)) { r = mh(re + L + 1, text + 1); if (r) return r; }
        return mh(re + L + 1, text);
    }
    if (matchatom(re, L, *text)) return mh(re + L, text + 1);
    return 0;
}
char *leelinea(char *buf, int max)
{
    int c, n;
    n = 0; c = getchar();
    if (c < 0) return 0;
    while (c >= 0 && c != '\n') { if (n < max - 1) buf[n++] = c; c = getchar(); }
    buf[n] = '\0';
    return buf;
}
char re[128], repl[128];
int global;

/* parsea  s<d>RE<d>repl<d>[g]  ; devuelve 1 si ok */
int parsecmd(char *s)
{
    int d, i, n;
    if (s[0] != 's' && s[0] != 'S') return 0;   /* (S y G: CP/M pasa la linea en mayusculas) */
    d = s[1];
    i = 2; n = 0;
    while (s[i] && s[i] != d) re[n++] = s[i++];
    re[n] = '\0';
    if (s[i] != d) return 0;
    i++; n = 0;
    while (s[i] && s[i] != d) repl[n++] = s[i++];
    repl[n] = '\0';
    if (s[i] != d) return 0;
    i++;
    global = (s[i] == 'g' || s[i] == 'G');
    return 1;
}
/* emite repl, con & = texto casado [ini,fin) */
void ponrepl(char *ini, char *fin)
{
    int i;
    char *p;
    for (i = 0; repl[i]; i++) {
        if (repl[i] == '&') { for (p = ini; p < fin; p++) putchar(*p); }
        else if (repl[i] == '\\' && repl[i + 1]) { putchar(repl[i + 1]); i++; }
        else putchar(repl[i]);
    }
}
int main()
{
    char cmd[256], line[512];
    char *p, *e;
    int hizo;
    if (!leelinea(cmd, 256)) return 0;
    if (!parsecmd(cmd)) { puts("sed: comando invalido"); return 1; }
    while (leelinea(line, 512)) {
        p = line; hizo = 0;
        while (*p) {
            e = (hizo && !global) ? 0 : mh(re, p);
            if (e && (e > p || !hizo)) {         /* casa en p */
                ponrepl(p, e);
                hizo = 1;
                if (e > p) p = e; else { putchar(*p); p++; }   /* match vacio: avanza 1 */
                if (!global) { while (*p) putchar(*p++); }
            } else { putchar(*p); p++; }
        }
        putchar('\n');
    }
    return 0;
}
