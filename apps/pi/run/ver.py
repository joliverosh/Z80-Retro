import sys; sys.set_int_max_str_digits(0)
def at(x,u):
    s=t=u//x; k=1; x2=x*x; sg=-1
    while t: t//=x2; k+=2; s+=sg*(t//k); sg=-sg
    return s
n=int(sys.argv[2]); u=10**(n+20); ref=str(4*(4*at(5,u)-at(239,u)))[1:n+1]
o=open(sys.argv[1]).read(); body=o[o.index('3.')+2:o.index('End:')]
d=''.join(c for c in body if c.isdigit())
print(len(d), d==ref, "primera diferencia:", next((i for i,(a,b) in enumerate(zip(d,ref)) if a!=b),None))
