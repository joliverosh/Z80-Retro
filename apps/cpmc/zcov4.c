/* zcov4.c - parte de ZCALC que se carga de ZCALC.OVL: la ayuda y la pantalla de presentacion
   (C) OLIVEROS 2026 */
/* mk: --max-allocs-per-node 200000 */
#include "zcalc.h"

static void help(void)
{
    pstr(CLS SHOW
        "ZCALC " VERSION "                                                   (C) OLIVEROS 2026\n\n"
        " Arrows (^E ^X ^S ^D) move  PgUp/PgDn (^R ^C)  Home: A1  > go to  ! recalc\n"
        " ^L redraw  ^U undo  ^F find  ; other window\n"
        " A digit . + - ( @ = starts a number or formula; the rest is a label (\" forces\n"
        " it). Enter or an arrow stores; ESC cancels; arrows after an operator point.\n"
        "\n"
        " Formulas: + - * / ^ & (joins texts) = <> < > <= >=  A1 $A$1 A1:B5 names \"text\"\n"
        "  @SUM @AVG @MIN @MAX @COUNT @LOOKUP @ABS @INT @ROUND @SQRT @MOD @IF @AND @OR\n"
        "  @NOT @PI @NA @ERROR @ISNA @ISERROR @SIN @COS @TAN @ATAN @LN @LOG @EXP\n"
        "  @PMT(rate,n,pv) @PV(rate,n,pmt) @FV(rate,n,pmt) @NPV(rate,..) @IRR(guess,..)\n"
        "  @DATE(y,m,d) @TODAY @NOW @YEAR @MONTH @DAY @LEFT(s,n) @RIGHT @MID(s,i,n) @LEN\n"
        "  @UPPER @LOWER @PROPER @TRIM @VALUE @STRING(x,d) @FIND(s,t) @REPEAT(s,n)\n"
        "  @CHAR @CODE @EXACT @ISSTR @ISNUM\n"
        "\n"
        " /A about  /B blank  /C clear  /D delete row/col  /E edit  /F format, width\n"
        " /G global  /I insert  /K copy  /V paste  /L lock  /M move  /N names  /O sort\n"
        " /P print  /R replicate  /S load, save, CSV, 1-2-3 .WKS, quit  /T titles\n"
        " /W windows  /X bar chart  /- repeat a label  /Q quit\n"
        " Numbers have 9 decimal digits (money adds up exactly).  "
"Press any key.");
    getk();
    pstr(HIDE CLS);
    dirty = 1;
}
/* /A: acerca de ZCALC */
static void about(void)
{
    pstr(CLS INV
        ESC "[9;20H  ZCALC " VERSION "                             "
        ESC "[10;20H  Spreadsheet for CP/M 2.2, CP/M 3      "
        ESC "[11;20H  and MP/M II on the Z80-Retro          "
        ESC "[13;20H  (C) OLIVEROS 2026                     "
        ESC "[15;20H  ");
    pf("%5u bytes free for cells           " NORM ESC "[18;20HPress any key.", hfree);
    getk();
    pstr(CLS);
    dirty = 1;
}

void ovl_entry(uint8_t op)
{
    if (op == 1) help(); else about();
}
