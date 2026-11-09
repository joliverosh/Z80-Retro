import re, bisect, sys
labs=[]
for l in open(sys.argv[1]):
    m=re.match(r"^\s*\d+:\s+\S*\s*([0-9A-F]{4})'?\s+(?:[0-9A-F]+\s+)?([A-Z][A-Z0-9_]*):",l)
    if m: labs.append((int(m.group(1),16),m.group(2)))
labs.sort(); ad=[x for x,_ in labs]
agg={}; tot=0
for l in open(sys.argv[2]):
    a,c=l.split(); a=int(a,16); c=int(c); tot+=c
    i=bisect.bisect_right(ad,a)-1
    n=labs[i][1] if i>=0 else "?"; agg[n]=agg.get(n,0)+c
for n,c in sorted(agg.items(),key=lambda x:-x[1])[:12]: print(f"{n:10s} {c/tot*100:5.1f}%  {c/17576:8.0f} T/pos")
