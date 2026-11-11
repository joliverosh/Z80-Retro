/* zbovk.c - las palabras de ZBAS, para las partes de ZBAS.OVL que compilan y que listan
   (C) OLIVEROS 2026 */
/* mk: --max-allocs-per-node 200000 */
#include "zbas.h"

/* las palabras, separadas por 0, en el orden de K_PRINT... */
const char kwp[] = "PRINT\0""INPUT\0""LET\0""IF\0""THEN\0""ELSE\0""ELSEIF\0""END\0""FOR\0""TO\0""STEP\0""NEXT\0""WHILE\0""WEND\0""DO\0""LOOP\0""UNTIL\0""EXIT\0""SELECT\0""CASE\0""IS\0""GOTO\0""GOSUB\0""RETURN\0""SUB\0""FUNCTION\0""CALL\0""LOCAL\0""DIM\0""DATA\0""READ\0""RESTORE\0""REM\0""STOP\0""CLS\0""LOCATE\0""COLOR\0""RANDOMIZE\0""OPEN\0""CLOSE\0""AS\0""OUTPUT\0""APPEND\0""LINE\0""SWAP\0""SLEEP\0""BEEP\0""ON\0""AND\0""OR\0""NOT\0""XOR\0""MOD\0""<=\0"">=\0""<>\0""RUN\0""LIST\0""NEW\0""LOAD\0""SAVE\0""FILES\0""SYSTEM\0""CONT\0""DELETE\0""RENUM\0""EDIT\0""TRON\0""TROFF\0""ERASE\0""USING\0""TAB\0""SPC\0""KILL\0""AUTO\0""ABS\0""INT\0""FIX\0""SGN\0""SQR\0""SIN\0""COS\0""TAN\0""ATN\0""LOG\0""LOG10\0""EXP\0""RND\0""PI\0""ROUND\0""PMT\0""PV\0""FV\0""DATE\0""TODAY\0""NOW\0""YEAR\0""MONTH\0""DAY\0""LEN\0""LEFT$\0""RIGHT$\0""MID$\0""INSTR\0""UCASE$\0""LCASE$\0""STR$\0""VAL\0""CHR$\0""ASC\0""SPACE$\0""STRING$\0""TRIM$\0""LTRIM$\0""RTRIM$\0""HEX$\0""DATE$\0""TIME$\0""INKEY$\0""EOF\0""FORMAT$\0""MIN\0""MAX\0""FRE\0""POS\0";
const char *kw(uint8_t k)   /* la palabra k (0 = PRINT) */
{
    const char *p = kwp;
    while (k--) p += strlen(p) + 1;
    return p;
}
