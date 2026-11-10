/* c/ejemplos/hanoi.c - Torres de Hanoi con 4 discos, recursivo.
 * Proyecto Semilla, version 1. */
/* Torres de Hanoi con 4 discos, recursivo. */
int movidas;
void puts_(char *s);

void puts_(char *s)
{       while(*s) putchar(*s++);
}
void printn(int n)
{       if(n/10) printn(n/10);
        putchar(n%10+'0');
}
void hanoi(int n, int de, int a, int por)
{       if(n==0) return;
        hanoi(n-1, de, por, a);
        movidas++;
        puts_("disco "); printn(n);
        puts_(": "); putchar(de); puts_(" -> "); putchar(a);
        putchar('\n');
        hanoi(n-1, por, a, de);
}
int main(void)
{       hanoi(4, 'A', 'C', 'B');
        printn(movidas); puts_(" movidas\n");
}
