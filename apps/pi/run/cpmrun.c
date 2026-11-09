// cpmrun: CP/M minimo para medir PI*.COM (BDOS 2 y 9, RST 30h C=28 da la hora segun los ciclos)
#include <stdio.h>
#include <stdlib.h>
#include "../../../../sim/z80core/z80.h"
static uint8_t m[65536];
static double mhz=7.3728;
static uint8_t rb(void*u,uint16_t a){return m[a];}
static void wb(void*u,uint16_t a,uint8_t v){m[a]=v;}
static uint8_t pin(z80*z,uint8_t p){return 0xff;}
static void pout(z80*z,uint8_t p,uint8_t v){}
static int bcd(int v){return (v/10)*16+v%10;}
int main(int c,char**v){
  FILE*f=fopen(v[1],"rb"); if(c>2)mhz=atof(v[2]);
  fread(m+0x100,1,0xFE00,f);
  z80 z; z80_init(&z); z.read_byte=rb; z.write_byte=wb; z.port_in=pin; z.port_out=pout;
  z.pc=0x100; z.sp=0xF000;
  m[0]=0x76; m[5]=0xC9; m[0x30]=0xC9; // HALT en 0, RET en 5 y en 30h
  for(;;){
    if(z.pc==0){fprintf(stderr,"\n[fin: %lu T = %.1f s a %.4f MHz]\n",z.cyc,z.cyc/(mhz*1e6),mhz);return 0;}
    if(z.pc==5){ if(z.c==2) putchar(z.e); else if(z.c==9){int a=(z.d<<8)|z.e; while(m[a]!='$') putchar(m[a++]);} }
    if(z.pc==0x30 && z.c==28){ long s=(long)(z.cyc/(mhz*1e6)) + 18*3600L+40*60; int a=(z.h<<8)|z.l;
      m[a]=bcd(s%60); m[a+1]=bcd(s/60%60); m[a+2]=bcd(s/3600%24); m[a+3]=8; m[a+4]=0x11; m[a+5]=0x26; }
    z80_step(&z);
  }
}
