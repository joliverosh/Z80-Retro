# entrena un GPT de caracteres chico con El Quijote, para ZGPT en el Z80
import re, math, time, sys, torch, torch.nn as nn, torch.nn.functional as F
torch.manual_seed(1)
torch.set_num_threads(2)
CH = " \nabcdefghijlmnopqrstuvxyzáéíóúüñ,.;:?¿!¡-'\"()"
V, D, L, H, FF, T = len(CH), 32, 2, 4, 96, 48
def prep(path='/tmp/gpt/dl/quijote.txt'):
    t = open(path, 'rb').read().decode('latin-1').replace('\r', '')
    t = re.sub(r'\n\s*\n+', '\x00', t)
    t = re.sub(r'\s+', ' ', t).replace('\x00', '\n').lower()
    t = t.translate(str.maketrans({'«': '"', '»': '"', 'ï': 'i', 'ù': 'u', 'à': 'a', 'w': 'v', 'k': 'c'}))
    t = ''.join(c for c in t if c in CH)
    return t
class Blk(nn.Module):
    def __init__(s):
        super().__init__()
        s.ln1 = nn.LayerNorm(D); s.qkv = nn.Linear(D, 3 * D); s.proj = nn.Linear(D, D)
        s.ln2 = nn.LayerNorm(D); s.fc1 = nn.Linear(D, FF); s.fc2 = nn.Linear(FF, D)
    def forward(s, x):
        B, Tt, _ = x.shape
        q, k, v = s.qkv(s.ln1(x)).split(D, 2)
        q, k, v = [z.view(B, Tt, H, D // H).transpose(1, 2) for z in (q, k, v)]
        i = torch.arange(Tt)
        msk = (i[None, :] <= i[:, None]) & (i[:, None] - i[None, :] < T)   # ventana de T
        y = F.scaled_dot_product_attention(q, k, v, attn_mask=msk)
        x = x + s.proj(y.transpose(1, 2).reshape(B, Tt, D))
        return x + s.fc2(F.relu(s.fc1(s.ln2(x))))
class GPT(nn.Module):
    def __init__(s):
        super().__init__()
        s.tok = nn.Embedding(V, D); s.pos = nn.Embedding(T, D)
        s.blks = nn.ModuleList(Blk() for _ in range(L))
        s.lnf = nn.LayerNorm(D); s.head = nn.Linear(D, V)
    def forward(s, idx, phase=0):
        # la posicion es modulo T: en el Z80 la cache de K y V es un anillo de T
        x = s.tok(idx) + s.pos((torch.arange(idx.shape[1]) + phase) % T)
        for b in s.blks: x = b(x)
        return s.head(s.lnf(x))
if __name__ == '__main__':
    t = prep()
    data = torch.tensor([CH.index(c) for c in t], dtype=torch.long)
    n = int(len(data) * .95); tr, va = data[:n], data[n:]
    m = GPT()
    print(sum(p.numel() for p in m.parameters()), 'parametros', len(t), 'caracteres', flush=True)
    steps = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    opt = torch.optim.AdamW(m.parameters(), lr=3e-3, weight_decay=0.01)
    S = 2 * T
    def batch(d, bs=64):
        ix = torch.randint(len(d) - S - 1, (bs,))
        return torch.stack([d[i:i + S] for i in ix]), torch.stack([d[i + 1:i + S + 1] for i in ix])
    t0 = time.time()
    for it in range(steps + 1):
        lr = 3e-3 * (min(1, it / 200)) * (0.1 + 0.9 * 0.5 * (1 + math.cos(math.pi * it / steps)))
        for g in opt.param_groups: g['lr'] = lr
        x, y = batch(tr)
        loss = F.cross_entropy(m(x, int(torch.randint(T, (1,)))).view(-1, V), y.view(-1))
        opt.zero_grad(); loss.backward(); nn.utils.clip_grad_norm_(m.parameters(), 1.0); opt.step()
        if it % 500 == 0:
            with torch.no_grad():
                x, y = batch(va, 256); vl = F.cross_entropy(m(x, 17).view(-1, V), y.view(-1)).item()
            print(f'{it} train {loss.item():.3f} val {vl:.3f}  {time.time()-t0:.0f}s', flush=True)
            torch.save(m.state_dict(), '/tmp/gpt/model.pt')
