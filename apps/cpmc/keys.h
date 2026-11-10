/* keys.h - teclas de flecha (ESC [ A..D) para los juegos */
#define K_UP    1
#define K_DOWN  2
#define K_RIGHT 3
#define K_LEFT  4
static int key(void)
{
    int k = getkey(), n;
    if (k != 27) {
        switch (k | 32) {
        case 'w': case 'i': return K_UP;
        case 's': case 'k': return K_DOWN;
        case 'a': case 'j': return K_LEFT;
        case 'd': case 'l': return K_RIGHT;
        }
        return k;
    }
    for (n = 0; n < 200 && !(k = getkey()); n++) ;
    if (k != '[' && k != 'O') return 27;
    for (n = 0; n < 200 && !(k = getkey()); n++) ;
    if (k >= 'A' && k <= 'D') return k - 'A' + 1;
    return 0;
}
