/* c/ejemplos/primos.c - Criba de Eratostenes: los primos menores que 1000.
 * Proyecto Semilla, version 1. */
/* Criba de Eratostenes: los primos menores que 1000.
   Small-C 1.1 (Ron Cain, 1980) compilado a IR de Semilla. */
#define N 1000

char criba[N];
void puts_(char *s);

void printn(int n)
{       if(n/10) printn(n/10);
        putchar(n%10+'0');
}
int main(void)
{
        int i, j, cuantos;
        cuantos=0;
        i=2;
        while(i<N)
                {if(criba[i]==0)
                        {printn(i);
                        cuantos++;
                        if(cuantos%10) putchar(' ');
                        else putchar('\n');
                        j=i+i;
                        while(j<N) {criba[j]=1; j=j+i;}
                        }
                i++;
                }
        putchar('\n');
        printn(cuantos);
        puts_(" primos\n");
}
void puts_(char *s)
{       while(*s) putchar(*s++);
}
