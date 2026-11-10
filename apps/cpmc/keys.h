/* keys.h - teclas de flecha (ESC [ A..D) para los juegos */
#define K_UP    0x81             /* (no 1-4: 3 es ^C y los juegos salian) */
#define K_DOWN  0x82
#define K_RIGHT 0x83
#define K_LEFT  0x84
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
    if (k >= 'A' && k <= 'D') return K_UP + k - 'A';
    return 0;
}
