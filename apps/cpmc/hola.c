#include "cpm.h"
void main(void)
{
    pf("Hola %s, %d %u %x %ld\n", "MP/M", -12, 65000u, 0xBEEF, 123456L);
    pf("MP/M: %u, tics %u, tps %u\n", ismpm(), ticks(), tps());
}
