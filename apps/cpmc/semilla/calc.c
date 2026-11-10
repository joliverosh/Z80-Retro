/* c/ejemplos/calc.c - Calculadora de expresiones de 16 bits con signo, una por linea.
 * Proyecto Semilla, version 1. */
// Calculadora: lee expresiones, una por línea, y responde.
// Enteros de 16 bits con signo, + - * / % y paréntesis.
#include <stdio.h>
#include <ctype.h>
/* prototipos (para SDCC, que no acepta llamadas sin declarar) */
void espacios(void);
int factor(void);
int termino(void);
int expresion(void);

char linea[80];
int pos, error;

int expresion(void);

void espacios(void) { while (linea[pos] == ' ') pos++; }

int factor(void)
{
    int v = 0;
    espacios();
    if (linea[pos] == '(') {
        pos++;
        v = expresion();
        espacios();
        if (linea[pos] == ')') pos++; else error = 1;
    } else if (linea[pos] == '-') {
        pos++;
        v = -factor();
    } else if (isdigit(linea[pos])) {
        while (isdigit(linea[pos])) v = v * 10 + linea[pos++] - '0';
    } else
        error = 1;
    return v;
}

int termino(void)
{
    int v = factor(), w;
    for (;;) {
        espacios();
        switch (linea[pos]) {
        case '*': pos++; v *= factor(); break;
        case '/': case '%':
            w = linea[pos++];
            int d = factor();
            if (d == 0) { error = 2; return 0; }
            v = w == '/' ? v / d : v % d;
            break;
        default:
            return v;
        }
    }
}

int expresion(void)
{
    int v = termino();
    for (;;) {
        espacios();
        if (linea[pos] == '+') { pos++; v += termino(); }
        else if (linea[pos] == '-') { pos++; v -= termino(); }
        else return v;
    }
}

int main(void)
{
    while (gets(linea)) {
        if (linea[0] == 0) continue;
        pos = error = 0;
        int v = expresion();
        espacios();
        if (linea[pos]) error = 1;
        if (error == 2) printf("%s = division por cero\n", linea);
        else if (error) printf("%s = ?\n", linea);
        else printf("%s = %d\n", linea, v);
    }
    return 0;
}
