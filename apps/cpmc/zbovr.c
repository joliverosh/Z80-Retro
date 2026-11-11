/* zbovr.c - para las partes de ZBAS.OVL que corren: donde estan las etiquetas, SUB y
   FUNCTION del programa (en sus variables)
   (C) OLIVEROS 2026 */
/* mk: --max-allocs-per-node 200000 */
#include "zbas.h"

void resolve(void)        /* etiquetas, SUB y FUNCTION: en que linea estan */
{
    uint8_t *l, *p;
    uint16_t ix;
    growvars();
    resolved = 1;
    for (l = prog; l < pend; l += LLEN(l)) {
        p = LTOK(l);
        if (*p == T_ID && p[3] == ':') { ix = p[1] | p[2] << 8; if (symat(ix)[0] == S_LABEL) var(ix)->u.f.l = l; }
        if ((*p == K_SUB || *p == K_FUNCTION) && p[1] == T_ID) {
            uint8_t *q, i = 0;
            uint16_t j = 0;
            ix = p[2] | p[3] << 8;
            var(ix)->u.f.l = l;
            if (*p == K_FUNCTION) {                /* la variable del resultado: el mismo nombre */
                uint8_t *nm = symat(ix);
                for (q = names; q < nend; q += 2 + q[1], j++)
                    if ((q[0] == S_NUM || q[0] == S_STR) && q[1] == nm[1] && !memcmp(q + 2, nm + 2, nm[1])) { var(ix)->u.f.r = j; i = 1; break; }
                if (!i) error(50);
            }
        }
    }
}
