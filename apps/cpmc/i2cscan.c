/* I2CSCAN - busca dispositivos en el bus I2C y muestra el reloj DS1307 y su RAM
   I2CSCAN                       el mapa del bus, la hora y la RAM del DS1307
   I2CSCAN W reg byte...         escribe bytes (hex) en la RAM, desde reg (18-3F)
   I2CSCAN T reg texto           escribe texto en la RAM
   I2CSCAN Z                     pone a cero 18-3F
   La RAM 08-17 es la configuracion de ZIOS (con su suma): no se deja escribir. */
#include <string.h>
#include "cpm.h"
#define RTC 0xD0
static uint8_t ram[64];
static uint8_t i2c(uint8_t op, uint8_t addr, uint8_t n, uint8_t *b)
{
    return zios(34, op, (addr << 8) | n, (uint16_t)b);
}
static uint8_t rtcread(uint8_t reg, uint8_t n, uint8_t *b)
{
    if (i2c(0, RTC, 1, &reg)) return 1;
    return i2c(1, RTC, n, b);
}
static uint8_t rtcwrite(uint8_t reg, uint8_t n, uint8_t *b)
{
    static uint8_t t[65];
    t[0] = reg; memcpy(t + 1, b, n);
    return i2c(0, RTC, n + 1, t);
}
static uint8_t hexv(const char *s, uint8_t *v)
{
    uint8_t x = 0, n = 0;
    for (; *s; s++, n++) {
        char c = *s;
        if (c >= '0' && c <= '9') c -= '0';
        else if (c >= 'A' && c <= 'F') c -= 'A' - 10;
        else return 0;
        x = (x << 4) | c;
    }
    *v = x;
    return n && n <= 2;
}
static const char *what(uint8_t a)
{
    if (a == 0x68) return "DS1307 real time clock";
    if (a >= 0x50 && a <= 0x57) return "EEPROM (24Cxx)";
    if (a >= 0x20 && a <= 0x27) return "I/O expander (PCF8574 / MCP23017)";
    if (a >= 0x38 && a <= 0x3F) return "PCF8574A or display";
    if (a >= 0x48 && a <= 0x4F) return "temperature sensor or ADC";
    if (a == 0x3C || a == 0x3D) return "OLED display (SSD1306)";
    if (a == 0x76 || a == 0x77) return "pressure sensor (BMP/BME280)";
    return "";
}
static void dump(void)
{
    uint8_t i, j;
    if (rtcread(0, 64, ram)) { pstr("DS1307: no answer\n"); return; }
    pf("\nDS1307: 20%02X-%02X-%02X %02X:%02X:%02X  (%s, control %02X)\n",
       ram[6], ram[5] & 0x3F, ram[4] & 0x3F, ram[2] & 0x3F, ram[1], ram[0] & 0x7F,
       ram[0] & 0x80 ? "STOPPED" : "running", ram[7]);
    pstr("RAM (08-17: ZIOS settings, 18-3F: free)\n");
    for (i = 8; i < 64; i += 16) {
        pf("  %02X: ", i);
        for (j = 0; j < 16 && i + j < 64; j++) pf("%02X ", ram[i + j]);
        while (j++ < 16) pstr("   ");
        putch(' ');
        for (j = 0; j < 16 && i + j < 64; j++) { uint8_t c = ram[i + j]; putch(c < 32 || c > 126 ? '.' : c); }
        pstr("\r\n");
    }
}
static uint8_t chk(uint8_t reg, uint8_t n)
{
    if (reg < 0x18 || reg + n > 0x40 || !n) {
        pstr("Only registers 18-3F can be written (08-17 hold the ZIOS settings)\n");
        return 1;
    }
    return 0;
}
void main(void)
{
    char *p = args(), *a = nextarg(&p);
    uint8_t x, y, found = 0, reg, n = 0, v;
    static uint8_t b[64];
    if (a && (*a == 'W' || *a == 'T' || *a == 'Z') && !a[1]) {
        char *r;
        if (*a == 'Z') { memset(b, 0, 40); reg = 0x18; n = 40; }
        else {
            if (!(r = nextarg(&p)) || !hexv(r, &reg)) { pstr("Missing register (hex)\n"); return; }
            if (*a == 'T') { while (*p == ' ') p++; n = strlen(p); memcpy(b, p, n > 40 ? 40 : n); }
            else while ((r = nextarg(&p)) && n < 40) {
                if (!hexv(r, &v)) { pf("Bad byte: %s\n", r); return; }
                b[n++] = v;
            }
        }
        if (chk(reg, n)) return;
        if (rtcwrite(reg, n, b)) pstr("DS1307: no answer\n");
        else pf("%u bytes written at %02X\n", n, reg);
        dump();
        return;
    }
    if (a) {
        pstr("Usage: I2CSCAN            bus map, clock and RAM of the DS1307\n"
             "       I2CSCAN W reg b... write hex bytes to the RAM (18-3F)\n"
             "       I2CSCAN T reg text write text to the RAM\n"
             "       I2CSCAN Z          clear 18-3F\n");
        return;
    }
    pstr("     0  1  2  3  4  5  6  7  8  9  A  B  C  D  E  F\n");
    for (y = 0; y < 8; y++) {
        pf("%02X: ", y << 4);
        for (x = 0; x < 16; x++) {
            uint8_t ad = (y << 4) | x;
            if (ad < 8 || ad > 0x77) pstr("   ");
            else if (!i2c(2, ad << 1, 0, 0)) { pf("%02X ", ad); ram[found++] = ad; }
            else pstr("-- ");
        }
        pstr("\r\n");
    }
    if (!found) { pstr("No devices\n"); return; }
    for (x = 0; x < found; x++) pf("  %02X  %s\n", ram[x], what(ram[x]));
    for (x = 0; x < found; x++) if (ram[x] == 0x68) { dump(); break; }
}
