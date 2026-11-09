import sys, math
def ref(n):
    m=(n-1)//2; s=bytearray([1])*(m+1); s[0]=0
    for i in range(1,(math.isqrt(n)-1)//2+1):
        if s[i]:
            p=2*i+1; s[(p*p-1)//2::p]=bytes(len(range((p*p-1)//2,m+1,p)))
    big=2*max(i for i in range(m,-1,-1) if s[i] or i==0 and False) +1 if False else None
    i=m
    while not s[i]: i-=1
    return sum(s)+1, 2*i+1
if __name__=="__main__":
    print(*ref(int(sys.argv[1])))
