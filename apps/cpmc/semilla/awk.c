/* c/ejemplos/awk.c - awk-milla: un awk pequeno, filtro de stdin a stdout.
 * Proyecto Semilla, version 1. */
/* awk-milla: un awk pequeno.  Filtro de stdin a stdout; la 1ra linea de la
   entrada es el programa awk, el resto son los datos.  Numeros en double.
   Soporta: campos $0..$n, NF, NR; reglas patron{accion}, BEGIN, END, /re/;
   print (lista con comas), aritmetica + - * / %, comparaciones, && || !,
   concatenacion, ~ !~, variables, arreglos a[k], if/else, while, for(;;),
   for(k in a), y length/substr/index/int/split.  Mismo resultado en las 8
   maquinas; probado contra el awk real. */
#include <stdio.h>

#define MAXS 64            /* largo maximo de una cadena/campo */
#define MAXF 32            /* campos por linea */
#define NV 48              /* variables escalares */
#define NAE 64             /* entradas de arreglo en total */
#define NN 500             /* nodos del arbol */
#define SP 3000            /* pool de caracteres (nombres, cadenas, regex) */
#define NT 600             /* tokens */
#define LINEA 1024         /* la linea de datos y la del programa */
#ifdef __SDCC              /* el Z80 de MP/M: 47 KB para todo */
#undef MAXS
#undef LINEA
#define LINEA 256
#undef MAXF
#undef NV
#undef NAE
#undef NN
#undef SP
#undef NT
#define MAXS 40
#define MAXF 16
#define NV 24
#define NAE 24
#define NN 160
#define SP 1000
#define NT 200
#endif

/* ---------- valores awk (numero y/o cadena) ---------- */
struct val { double n; char s[MAXS]; int tipo; };   /* tipo: 0 num, 1 cadena, 2 numcadena */
/* prototipos (para SDCC, que no acepta llamadas sin declarar) */
double _atof(char *s);
double tonum(struct val *v);
char * tostr(struct val *v, char *buf);
int esverdad(struct val *v);
int atomlen(char *re);
int matchatom(char *re,int L,int c);
int mrep(char *re,int L,char *resto,char *text,int min);
int mhere(char *re,char *text);
int rematch(char *re,char *text);
int guarda(char *s);
int opch(int c);
int alnum(int c);
int alpha(int c);
void lexer(void);
int asteq(char *a,char *b);
int mk(int op);
char * tkstr(void);
int isop(char *o);
int iskw(char *k);
void adv(void);
int primary(void);
int postfix(void);
int term(void);
int adit(void);
int empieza_valor(void);
int concat(void);
int cmp(void);
int andx(void);
int orx(void);
int expr(void);
int stmtlist(int fin);
int stmt(void);
void parse_prog(void);
int varidx(char *nm);
int aidx(char *nm,char *key);
void setfields(char *s);
void copys(char *d,char *s);
char * evstr(int k, char *buf);
double evnum(int k);
int esverdad_k(int k);
int strlen_(char *s);
int strcmp_(char *a,char *b);
void setnum(struct val *R,double n);
void setstr(struct val *R,char *s);
void asigna(int lv, struct val *v);
void evx(int k, struct val *R);
void exec(int k);
void fputs_(char *s);
int leelinea(char *buf,int max);

double _atof(char *s)
{
    double r, f; int sg, e, es;
    while (*s==' '||*s=='\t') s++;
    sg=1; if(*s=='-'){sg=-1;s++;} else if(*s=='+')s++;
    r=0; while(*s>='0'&&*s<='9') r=r*10+(*s++ -'0');
    if(*s=='.'){ s++; f=0.1; while(*s>='0'&&*s<='9'){ r+=(*s++ -'0')*f; f*=0.1; } }
    if(*s=='e'||*s=='E'){ s++; es=1; if(*s=='-'){es=-1;s++;}else if(*s=='+')s++; e=0;
        while(*s>='0'&&*s<='9')e=e*10+(*s++ -'0');
        while(e--){ if(es>0)r*=10; else r/=10; } }
    return sg*r;
}
/* cadena a numero, numero a cadena como awk (%.6g, enteros sin punto) */
double tonum(struct val *v){ return v->tipo==1||v->tipo==2 ? _atof(v->s) : v->n; }
char *tostr(struct val *v, char *buf)
{
    double n; long e; int i,j; char t[MAXS];
    if(v->tipo){ i=0; while(v->s[i]){buf[i]=v->s[i];i++;} buf[i]=0; return buf; }
    n=v->n;
    if(n==0){ buf[0]='0'; buf[1]=0; return buf; }
    /* entero exacto y no enorme: sin decimales */
    e=(long)n;
    if((double)e==n && n<1e15 && n>-1e15){
        i=0; if(e<0){buf[i++]='-'; e=-e;} j=0; if(e==0)t[j++]='0'; while(e){t[j++]='0'+e%10; e/=10;} while(j)buf[i++]=t[--j]; buf[i]=0; return buf;
    }
    sprintf(buf,"%.6g",n);   /* no entero: como OFMT/CONVFMT */
    return buf;
}
int esverdad(struct val *v){ if(v->tipo==1) return v->s[0]!=0; if(v->tipo==2) return _atof(v->s)!=0; return v->n!=0; }

/* ---------- regex (de grep) ---------- */
int atomlen(char *re){int n;if(re[0]=='\\'&&re[1])return 2;if(re[0]=='['){n=1;if(re[n]=='^')n++;if(re[n]==']')n++;while(re[n]&&re[n]!=']')n++;return re[n]==']'?n+1:n;}return 1;}
int matchatom(char *re,int L,int c){int i,neg,lo,ok;if(c=='\0')return 0;if(re[0]=='\\')return re[1]==c;if(re[0]=='.')return 1;if(re[0]=='['){i=1;neg=0;if(re[i]=='^'){neg=1;i++;}ok=0;while(i<L-1){if(re[i+1]=='-'&&i+2<L-1){lo=re[i];if(c>=lo&&c<=re[i+2])ok=1;i+=3;}else{if(re[i]==c)ok=1;i++;}}return neg?!ok:ok;}return re[0]==c;}
int mhere(char *re,char *text);
int mrep(char *re,int L,char *resto,char *text,int min){char*t;int n;t=text;n=0;while(matchatom(re,L,*t)){t++;n++;}while(n>=min){if(mhere(resto,text+n))return 1;n--;}return 0;}
int mhere(char *re,char *text){int L;if(re[0]==0)return 1;if(re[0]=='$'&&re[1]==0)return *text==0;L=atomlen(re);if(re[L]=='*')return mrep(re,L,re+L+1,text,0);if(re[L]=='+')return mrep(re,L,re+L+1,text,1);if(re[L]=='?'){if(*text&&matchatom(re,L,*text)&&mhere(re+L+1,text+1))return 1;return mhere(re+L+1,text);}if(matchatom(re,L,*text))return mhere(re+L,text+1);return 0;}
int rematch(char *re,char *text){if(re[0]=='^')return mhere(re+1,text);do{if(mhere(re,text))return 1;}while(*text++!=0);return 0;}

/* ---------- tokens ---------- */
/* clases: 0 fin, 1 num, 2 cad, 3 nombre, 4 regex, 5 operador/puntuacion */
int tcls[NT]; double tnum[NT]; int tstr[NT]; int ntok;
char pool[SP]; int poolp;
int guarda(char *s){ int p=poolp,i=0; while(s[i]){pool[poolp++]=s[i++];} pool[poolp++]=0; return p; }

char *src; int sp;
int opch(int c){ return c=='{'||c=='}'||c=='('||c==')'||c=='['||c==']'||c==';'||c==','||c=='+'||c=='-'||c=='*'||c=='/'||c=='%'||c=='<'||c=='>'||c=='='||c=='!'||c=='&'||c=='|'||c=='~'||c=='$'||c=='^'; }
int alnum(int c){ return (c>='a'&&c<='z')||(c>='A'&&c<='Z')||(c>='0'&&c<='9')||c=='_'; }
int alpha(int c){ return (c>='a'&&c<='z')||(c>='A'&&c<='Z')||c=='_'; }

/* ¿puede aparecer un regex aqui? (no justo despues de valor) */
int prevval;
void lexer()
{
    int c,n; char b[MAXS];
    ntok=0; poolp=0; prevval=0;
    while((c=src[sp])){
        if(c==' '||c=='\t'||c=='\n'){sp++;continue;}
        if(c=='#'){ while(src[sp]&&src[sp]!='\n')sp++; continue; }
        if(c>='0'&&c<='9'||(c=='.'&&src[sp+1]>='0'&&src[sp+1]<='9')){
            n=0; while(alnum(src[sp])||src[sp]=='.'){b[n++]=src[sp++];} b[n]=0;
            tcls[ntok]=1; tnum[ntok]=_atof(b); ntok++; prevval=1; continue;
        }
        if(c=='"'){
            sp++; n=0;
            while(src[sp]&&src[sp]!='"'){
                if(src[sp]=='\\'){ sp++; c=src[sp++];
                    if(c=='n')c='\n'; else if(c=='t')c='\t'; else if(c=='\\')c='\\'; else if(c=='"')c='"'; else if(c=='r')c='\r';
                    b[n++]=c;
                } else b[n++]=src[sp++];
            }
            if(src[sp]=='"')sp++;
            b[n]=0; tcls[ntok]=2; tstr[ntok]=guarda(b); ntok++; prevval=1; continue;
        }
        if(alpha(c)){
            n=0; while(alnum(src[sp]))b[n++]=src[sp++]; b[n]=0;
            tcls[ntok]=3; tstr[ntok]=guarda(b); ntok++;
            prevval=1;
            /* keywords no son valor (permiten regex despues) */
            if(!asteq(b,"BEGIN")&&!asteq(b,"END")&&!asteq(b,"print")&&!asteq(b,"if")&&!asteq(b,"else")&&!asteq(b,"while")&&!asteq(b,"for")&&!asteq(b,"in")) ; else prevval=0;
            continue;
        }
        if(c=='/'&&!prevval){
            sp++; n=0;
            while(src[sp]&&src[sp]!='/'){ if(src[sp]=='\\'){b[n++]=src[sp++];} b[n++]=src[sp++]; }
            if(src[sp]=='/')sp++;
            b[n]=0; tcls[ntok]=4; tstr[ntok]=guarda(b); ntok++; prevval=1; continue;
        }
        /* operador: toma 2 chars si forma uno conocido */
        b[0]=c; b[1]=src[sp+1]; b[2]=0;
        if((b[0]=='='&&b[1]=='=')||(b[0]=='!'&&b[1]=='=')||(b[0]=='<'&&b[1]=='=')||(b[0]=='>'&&b[1]=='=')||
           (b[0]=='&'&&b[1]=='&')||(b[0]=='|'&&b[1]=='|')||(b[0]=='+'&&b[1]=='+')||(b[0]=='-'&&b[1]=='-')||
           (b[0]=='!'&&b[1]=='~')||(b[0]=='+'&&b[1]=='=')||(b[0]=='-'&&b[1]=='=')||(b[0]=='*'&&b[1]=='=')||
           (b[0]=='/'&&b[1]=='=')||(b[0]=='%'&&b[1]=='=')){ sp+=2; }
        else { b[1]=0; sp++; }
        tcls[ntok]=5; tstr[ntok]=guarda(b); ntok++;
        prevval = (b[0]==')'||b[0]==']');   /* tras ) ] viene valor */
        continue;
    }
    tcls[ntok]=0; tstr[ntok]=guarda(""); ntok++;
}
int asteq(char *a,char *b){int i=0;while(a[i]&&a[i]==b[i])i++;return a[i]==b[i];}

/* ---------- arbol ---------- */
int nop[NN],na[NN],nb[NN],nc[NN],ns[NN],nx[NN]; double nnum[NN]; int nn;
/* ops */
#define ENUM 1
#define ESTR 2
#define EVAR 3
#define EFLD 4      /* a = indice */
#define EARR 5      /* s = nombre, a = clave */
#define EBIN 6      /* c = '+' etc, a,b */
#define ECMP 7      /* c = op, a,b */
#define EAND 8
#define EOR 9
#define ENOT 10
#define EMATCH 11   /* a texto, s regex, c neg */
#define ECAT 12
#define EASN 13     /* a lval, b expr, c op(0 =, '+' += ...) */
#define EINCR 14    /* a lval, c '+'/'-', nb pre/post */
#define ECALL 15    /* c = id builtin, a,b,nb args */
#define ENEG 16
#define SPRINT 20   /* a = lista (ECAT-like via nb list) */
#define SIF 21
#define SWHILE 22
#define SFOR 23     /* a init, b cond, nc post? use ns=post, na=body */
#define SFORIN 24   /* s var, c arrname-node, a body */
#define SBLOCK 25   /* a = primer stmt, encadenados por nc */
#define SEXPR 26
#define SPRINTLIST 27
int mk(int op){ nop[nn]=op; na[nn]=nb[nn]=nc[nn]=ns[nn]=nx[nn]=-1; nnum[nn]=0; return nn++; }

/* parser */
int tk; /* token actual */
char *tkstr(){ return pool+tstr[tk]; }
int isop(char *o){ return tcls[tk]==5 && asteq(pool+tstr[tk],o); }
int iskw(char *k){ return tcls[tk]==3 && asteq(pool+tstr[tk],k); }
void adv(){ if(tcls[tk]!=0) tk++; }
int expr();
int primary()
{
    int k,x,i;
    if(tcls[tk]==1){ k=mk(ENUM); nnum[k]=tnum[tk]; adv(); return k; }
    if(tcls[tk]==2){ k=mk(ESTR); ns[k]=tstr[tk]; adv(); return k; }
    if(tcls[tk]==4){ k=mk(EMATCH); ns[k]=tstr[tk]; na[k]=mk(EFLD); na[na[k]]=mk(ENUM); nnum[na[na[k]]]=0; nc[k]=0; adv(); return k; } /* /re/ => $0 ~ re */
    if(isop("$")){ adv(); k=mk(EFLD); na[k]=primary(); return k; }
    if(isop("!")){ adv(); k=mk(ENOT); na[k]=primary(); return k; }
    if(isop("-")){ adv(); k=mk(ENEG); na[k]=primary(); return k; }
    if(isop("+")){ adv(); return primary(); }
    if(isop("(")){ adv(); x=expr(); if(isop(")"))adv(); return x; }
    if(isop("++")||isop("--")){ i=isop("++")?'+':'-'; adv(); k=mk(EINCR); na[k]=primary(); nc[k]=i; nb[k]=1; return k; }
    if(tcls[tk]==3){
        char nm[MAXS]; int n=0; char *s=tkstr(); while(s[n]){nm[n]=s[n];n++;} nm[n]=0;
        /* builtins */
        adv();
        if(isop("(")){
            int id=-1;
            if(asteq(nm,"length"))id=1; else if(asteq(nm,"substr"))id=2; else if(asteq(nm,"index"))id=3;
            else if(asteq(nm,"int"))id=4; else if(asteq(nm,"split"))id=5;
            adv();
            k=mk(ECALL); nc[k]=id; na[k]=-1; nb[k]=-1; ns[k]=-1;
            if(!isop(")")){ na[k]=expr(); if(isop(",")){adv(); nb[k]=expr();} if(isop(",")){adv(); ns[k]=expr();} }
            if(isop(")"))adv();
            return k;
        }
        if(isop("[")){ adv(); k=mk(EARR); ns[k]=guarda(nm); na[k]=expr(); if(isop("]"))adv(); return k; }
        k=mk(EVAR); ns[k]=guarda(nm); return k;
    }
    k=mk(ENUM); nnum[k]=0; return k;  /* vacio */
}
int postfix()
{
    int k,a;
    a=primary();
    if(isop("++")||isop("--")){ int i=isop("++")?'+':'-'; adv(); k=mk(EINCR); na[k]=a; nc[k]=i; nb[k]=0; return k; }
    return a;
}
int term()   /* * / % */
{
    int a=postfix(),k,o;
    while(isop("*")||isop("/")||isop("%")){ o=tkstr()[0]; adv(); k=mk(EBIN); nc[k]=o; na[k]=a; nb[k]=postfix(); a=k; }
    return a;
}
int adit()   /* + - */
{
    int a=term(),k,o;
    while(isop("+")||isop("-")){ o=tkstr()[0]; adv(); k=mk(EBIN); nc[k]=o; na[k]=a; nb[k]=term(); a=k; }
    return a;
}
/* concatenacion: adit adyacentes */
int empieza_valor(){ return tcls[tk]==1||tcls[tk]==2||tcls[tk]==3||tcls[tk]==4||isop("$")||isop("(")||isop("!")||isop("-")||isop("++")||isop("--"); }
int concat()
{
    int a=adit(),k;
    while(empieza_valor() && !iskw("in")){ k=mk(ECAT); na[k]=a; nb[k]=adit(); a=k; }
    return a;
}
int cmp()
{
    int a=concat(),k,r; char *o;
    if(isop("<")||isop("<=")||isop(">")||isop(">=")||isop("==")||isop("!=")){
        o=tkstr(); k=mk(ECMP); nc[k]=(o[0]<<8)|(o[1]?o[1]:' '); adv(); r=concat(); na[k]=a; nb[k]=r; a=k;
    }
    if(isop("~")||isop("!~")){ int neg=isop("!~"); adv(); k=mk(EMATCH); na[k]=a; nc[k]=neg; if(tcls[tk]==4){ns[k]=tstr[tk];adv();} else { nb[k]=concat(); ns[k]=-1; } a=k; }
    return a;
}
int andx(){ int a=cmp(),k; while(isop("&&")){adv(); k=mk(EAND); na[k]=a; nb[k]=cmp(); a=k;} return a; }
int orx(){ int a=andx(),k; while(isop("||")){adv(); k=mk(EOR); na[k]=a; nb[k]=andx(); a=k;} return a; }
int expr()
{
    int a=orx(),k; char *o;
    /* asignacion si a es lvalue y sigue = += ... */
    if((nop[a]==EVAR||nop[a]==EFLD||nop[a]==EARR) && (isop("=")||isop("+=")||isop("-=")||isop("*=")||isop("/=")||isop("%="))){
        o=tkstr(); k=mk(EASN); na[k]=a; nc[k]=(o[0]=='=')?0:o[0]; adv(); nb[k]=expr(); return k;
    }
    return a;
}
int stmt();
int stmtlist(int fin)
{
    int head=-1,last=-1,s;
    while(tcls[tk]!=0 && !isop(fin?"}":"\0")){
        if(fin && isop("}")) break;
        if(isop(";")){adv();continue;}
        s=stmt();
        if(head<0)head=s; else nx[last]=s;
        last=s;
        if(isop(";"))adv();
        if(!fin) break;
    }
    return head;
}
int stmt()
{
    int k,e;
    if(isop("{")){ adv(); k=mk(SBLOCK); na[k]=stmtlist(1); if(isop("}"))adv(); return k; }
    if(iskw("print")){ adv(); k=mk(SPRINT); na[k]=-1;
        if(!isop(";")&&!isop("}")&&tcls[tk]!=0){ int head=-1,last=-1,x;
            x=expr(); head=last=mk(SPRINTLIST); na[last]=x;
            while(isop(",")){adv(); x=expr(); nc[last]=mk(SPRINTLIST); last=nc[last]; na[last]=x;}
            na[k]=head; }
        return k; }
    if(iskw("if")){ adv(); if(isop("("))adv(); e=expr(); if(isop(")"))adv(); k=mk(SIF); nb[k]=e; na[k]=stmt(); nc[k]=-1; while(isop(";"))adv(); if(iskw("else")){adv(); nc[k]=stmt();} return k; }
    if(iskw("while")){ adv(); if(isop("("))adv(); e=expr(); if(isop(")"))adv(); k=mk(SWHILE); nb[k]=e; na[k]=stmt(); return k; }
    if(iskw("for")){ adv(); if(isop("("))adv();
        /* for(k in a) o for(init;cond;post) */
        if(tcls[tk]==3 && tcls[tk+1]==3 && asteq(pool+tstr[tk+1],"in")){
            k=mk(SFORIN); ns[k]=guarda(tkstr()); adv(); adv(); /* var, in */
            nc[k]=guarda(tkstr()); adv(); if(isop(")"))adv(); na[k]=stmt(); return k;
        }
        { int ini,cond,post; ini = isop(";")?-1:expr(); if(isop(";"))adv();
          cond = isop(";")?-1:expr(); if(isop(";"))adv();
          post = isop(")")?-1:expr(); if(isop(")"))adv();
          k=mk(SFOR); nb[k]=ini; nc[k]=cond; ns[k]=post; na[k]=stmt(); return k; }
    }
    e=expr(); k=mk(SEXPR); na[k]=e; return k;
}

/* reglas */
int rpat[64], ract[64], rkind[64], nr; /* kind:0 normal 1 BEGIN 2 END */
void parse_prog()
{
    nn=0; nr=0; tk=0;
    while(tcls[tk]!=0){
        if(isop(";")){adv();continue;}
        if(iskw("BEGIN")){ adv(); rkind[nr]=1; rpat[nr]=-1; ract[nr]=stmt(); nr++; continue; }
        if(iskw("END")){ adv(); rkind[nr]=2; rpat[nr]=-1; ract[nr]=stmt(); nr++; continue; }
        rkind[nr]=0;
        if(isop("{")){ rpat[nr]=-1; ract[nr]=stmt(); }
        else { rpat[nr]=expr(); if(isop("{")) ract[nr]=stmt(); else ract[nr]=-1; }
        nr++;
    }
}

/* ---------- evaluacion ---------- */
char line[LINEA]; char fld[MAXF][MAXS]; int NF; double NR_;
char vname[NV][24]; struct val vval[NV]; int nvar;
char aname[NAE][24]; char akey[NAE][MAXS]; struct val aval[NAE]; int nae;

int varidx(char *nm){ int i; for(i=0;i<nvar;i++)if(asteq(vname[i],nm))return i; i=nvar++; { int j=0; while(nm[j]){vname[i][j]=nm[j];j++;} vname[i][j]=0;} vval[i].tipo=2; vval[i].s[0]=0; vval[i].n=0; return i; }
int aidx(char *nm,char *key){ int i; for(i=0;i<nae;i++)if(asteq(aname[i],nm)&&asteq(akey[i],key))return i; i=nae++; {int j=0;while(nm[j]){aname[i][j]=nm[j];j++;}aname[i][j]=0;} {int j=0;while(key[j]){akey[i][j]=key[j];j++;}akey[i][j]=0;} aval[i].tipo=2; aval[i].s[0]=0; aval[i].n=0; return i; }

void setfields(char *s)
{
    int i,n; NF=0;
    i=0; { int j=0; while(s[j]){line[j]=s[j];j++;} line[j]=0; }
    while(s[i]){
        while(s[i]==' '||s[i]=='\t')i++;
        if(!s[i])break;
        n=0; while(s[i]&&s[i]!=' '&&s[i]!='\t'){ if(n<MAXS-1)fld[NF][n++]=s[i]; i++; } fld[NF][n]=0;
        NF++; if(NF>=MAXF)break;
    }
}
void copys(char *d,char *s){int i=0;while(s[i]){d[i]=s[i];i++;}d[i]=0;}

/* Evaluacion por puntero: evx escribe el resultado en *R.  Es recursiva, y
   C-milla devuelve structs por valor en un buffer fijo por funcion, asi que
   NO se puede 'return struct' aqui; cada nivel usa su propio local y pasa &. */
void evx(int k, struct val *R);
char *evstr(int k, char *buf){ struct val v; evx(k,&v); return tostr(&v,buf); }
double evnum(int k){ struct val v; evx(k,&v); return tonum(&v); }
int esverdad_k(int k){ struct val v; evx(k,&v); return esverdad(&v); }
int strlen_(char *s){int n=0;while(s[n])n++;return n;}
int strcmp_(char *a,char *b){int i=0;while(a[i]&&a[i]==b[i])i++;return (unsigned char)a[i]-(unsigned char)b[i];}

void setnum(struct val *R,double n){ R->tipo=0; R->n=n; R->s[0]=0; }
void setstr(struct val *R,char *s){ R->tipo=1; copys(R->s,s); }

void asigna(int lv, struct val *v)   /* guarda v en el lvalue lv */
{
    char kb[MAXS], nm[24]; int i;
    if(nop[lv]==EVAR){ i=varidx(pool+ns[lv]); vval[i]=*v; return; }
    if(nop[lv]==EARR){ struct val kv; evx(na[lv],&kv); tostr(&kv,kb); { char*s=pool+ns[lv];int j=0;while(s[j]){nm[j]=s[j];j++;}nm[j]=0;} i=aidx(nm,kb); aval[i]=*v; return; }
    if(nop[lv]==EFLD){ int f=(int)evnum(na[lv]); char b[MAXS]; tostr(v,b); if(f==0){copys(line,b); setfields(line);} else if(f>=1&&f<MAXF){ while(NF<f){fld[NF][0]=0;NF++;} copys(fld[f-1],b); } }
}

void evx(int k, struct val *R)
{
    struct val a,b; char ba[MAXS],bb[MAXS]; int i,o;
    if(k<0){ setnum(R,0); return; }
    switch(nop[k]){
    case ENUM: setnum(R,nnum[k]); return;
    case ESTR: setstr(R,pool+ns[k]); return;
    case EVAR: { char *nm=pool+ns[k];
        if(asteq(nm,"NR")){setnum(R,NR_);return;}
        if(asteq(nm,"NF")){setnum(R,NF);return;}
        i=varidx(nm); *R=vval[i]; return; }
    case EFLD: { int f=(int)evnum(na[k]); if(f==0){setstr(R,line);return;} if(f>=1&&f<=NF){ R->tipo=2; copys(R->s,fld[f-1]); return;} setstr(R,""); return; }
    case EARR: { char kb2[MAXS],nm[24]; struct val kv; evx(na[k],&kv); tostr(&kv,kb2); {char*s=pool+ns[k];int j=0;while(s[j]){nm[j]=s[j];j++;}nm[j]=0;} i=aidx(nm,kb2); *R=aval[i]; return; }
    case ENEG: setnum(R,-evnum(na[k])); return;
    case ENOT: setnum(R,!esverdad_k(na[k])); return;
    case EBIN: { double x=evnum(na[k]),y=evnum(nb[k]); o=nc[k];
        if(o=='+')setnum(R,x+y); else if(o=='-')setnum(R,x-y); else if(o=='*')setnum(R,x*y);
        else if(o=='/')setnum(R,x/y); else if(o=='%'){ long q=(long)(x/y); setnum(R,x-q*y); } else setnum(R,0); return; }
    case ECAT: { evx(na[k],&a); evx(nb[k],&b); tostr(&a,ba); tostr(&b,bb); { int j=0,m=0; while(ba[j]&&m<MAXS-1){R->s[m++]=ba[j++];} j=0; while(bb[j]&&m<MAXS-1){R->s[m++]=bb[j++];} R->s[m]=0; } R->tipo=1; return; }
    case ECMP: { int c; evx(na[k],&a); evx(nb[k],&b); o=nc[k];
        if((a.tipo==0||a.tipo==2)&&(b.tipo==0||b.tipo==2)){ double x=tonum(&a),y=tonum(&b); c=(x<y)?-1:(x>y)?1:0; }
        else { tostr(&a,ba); tostr(&b,bb); c=strcmp_(ba,bb); }
        { int hi=o>>8, lo=o&255; int r;
          if(hi=='<'&&lo==' ')r=c<0; else if(hi=='<'&&lo=='=')r=c<=0; else if(hi=='>'&&lo==' ')r=c>0;
          else if(hi=='>'&&lo=='=')r=c>=0; else if(hi=='='&&lo=='=')r=c==0; else r=c!=0;
          setnum(R,r); } return; }
    case EAND: setnum(R, esverdad_k(na[k]) && esverdad_k(nb[k])); return;
    case EOR: setnum(R, esverdad_k(na[k]) || esverdad_k(nb[k])); return;
    case EMATCH: { char *re; evx(na[k],&a); tostr(&a,ba); if(ns[k]>=0)re=pool+ns[k]; else { evx(nb[k],&b); tostr(&b,bb); re=bb; } i=rematch(re,ba); setnum(R,nc[k]?!i:i); return; }
    case EASN: { struct val rv; evx(nb[k],&rv); if(nc[k]){ double cur=evnum(na[k]),y=tonum(&rv),z; o=nc[k];
                 if(o=='+')z=cur+y; else if(o=='-')z=cur-y; else if(o=='*')z=cur*y; else if(o=='/')z=cur/y; else { long q=(long)(cur/y); z=cur-q*y; } setnum(&rv,z); }
                 asigna(na[k],&rv); *R=rv; return; }
    case EINCR: { double cur=evnum(na[k]); struct val nv; setnum(&nv,cur+(nc[k]=='+'?1:-1)); asigna(na[k],&nv); if(nb[k])setnum(R,cur); else *R=nv; return; }
    case ECALL: { int id=nc[k];
        if(id==1){ if(na[k]<0){setnum(R,strlen_(line));return;} evx(na[k],&a); tostr(&a,ba); setnum(R,strlen_(ba)); return; }
        if(id==2){ evx(na[k],&a); tostr(&a,ba); { int m=(int)evnum(nb[k]); int len=ns[k]>=0?(int)evnum(ns[k]):10000; int L=strlen_(ba),j,o2=0; if(m<1)m=1; for(j=m-1;j<L&&len>0&&o2<MAXS-1;j++,len--)R->s[o2++]=ba[j]; R->s[o2]=0; R->tipo=1; } return; }
        if(id==3){ evx(na[k],&a); tostr(&a,ba); evx(nb[k],&b); tostr(&b,bb); { int j,m; for(j=0;ba[j];j++){for(m=0;bb[m]&&ba[j+m]==bb[m];m++); if(bb[m]==0){setnum(R,j+1);return;}} setnum(R,0);} return; }
        if(id==4){ setnum(R,(double)(long)evnum(na[k])); return; }
        if(id==5){ evx(na[k],&a); tostr(&a,ba); { char nm[24]; int cnt=0,j=0,st; struct val av;
            if(nb[k]>=0&&nop[nb[k]]==EVAR){char*s=pool+ns[nb[k]];int q=0;while(s[q]){nm[q]=s[q];q++;}nm[q]=0;} else nm[0]=0;
            while(ba[j]){ while(ba[j]==' '||ba[j]=='\t')j++; if(!ba[j])break; st=j; while(ba[j]&&ba[j]!=' '&&ba[j]!='\t')j++; { char kb2[MAXS],fv[MAXS]; int q=0,m2; m2=cnt+1; { int t=m2,p=0; char tmp[16]; if(t==0)tmp[p++]='0'; while(t){tmp[p++]='0'+t%10;t/=10;} while(p)kb2[q++]=tmp[--p]; kb2[q]=0;} { int p=0; while(st<j)fv[p++]=ba[st++]; fv[p]=0;} { int ai=aidx(nm,kb2); av.tipo=2; copys(av.s,fv); aval[ai]=av; } } cnt++; }
            setnum(R,cnt); } return; }
        setnum(R,0); return; }
    }
    setnum(R,0);
}

int broke;
void exec(int k)
{
    char buf[MAXS];
    if(k<0||broke)return;
    switch(nop[k]){
    case SBLOCK: { int s=na[k]; while(s>=0&&!broke){ exec(s); s=nx[s]; } return; }
    case SEXPR: { struct val v; evx(na[k],&v); return; }
    case SPRINT: { int l=na[k]; if(l<0){ fputs_(line); putchar('\n'); return; }
        while(l>=0){ struct val v; evx(na[l],&v); fputs_(tostr(&v,buf)); l=nc[l]; if(l>=0)putchar(' '); } putchar('\n'); return; }
    case SIF: if(esverdad_k(nb[k]))exec(na[k]); else if(nc[k]>=0)exec(nc[k]); return;
    case SWHILE: while(esverdad_k(nb[k])&&!broke)exec(na[k]); return;
    case SFOR: { struct val v; if(nb[k]>=0)evx(nb[k],&v); while((nc[k]<0||esverdad_k(nc[k]))&&!broke){ exec(na[k]); if(ns[k]>=0)evx(ns[k],&v); } return; }
    case SFORIN: { char *nm=pool+nc[k]; char *vn=pool+ns[k]; int i,vi=varidx(vn);
        for(i=0;i<nae;i++){ if(asteq(aname[i],nm)){ struct val kv; kv.tipo=2; copys(kv.s,akey[i]); vval[vi]=kv; exec(na[k]); } } return; }
    default: { struct val v; evx(k,&v); return; }
    }
}
void fputs_(char *s){ while(*s)putchar(*s++); }

int leelinea(char *buf,int max){ int c,n=0; c=getchar(); if(c<0)return 0; while(c>=0&&c!='\n'){ if(n<max-1)buf[n++]=c; c=getchar(); } buf[n]=0; return 1; }

char prog[LINEA];
int main()
{
    int i;
    if(!leelinea(prog,LINEA))return 0;
    src=prog; sp=0; lexer();
    parse_prog();
    nvar=0; nae=0; NR_=0; broke=0;
    for(i=0;i<nr;i++) if(rkind[i]==1) exec(ract[i]);
    while(leelinea(line,LINEA)){
        setfields(line); NR_++;
        for(i=0;i<nr;i++){
            if(rkind[i]!=0)continue;
            if(rpat[i]<0 || esverdad_k(rpat[i])){ if(ract[i]<0){ fputs_(line); putchar('\n'); } else exec(ract[i]); }
        }
    }
    for(i=0;i<nr;i++) if(rkind[i]==2) exec(ract[i]);
    return 0;
}
