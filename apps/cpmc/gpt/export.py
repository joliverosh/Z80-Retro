# export.py: cuantiza el modelo a enteros, escribe ZGPT.BIN y es la referencia exacta
# de la inferencia del Z80 (las mismas cuentas enteras que zgpt.c)
import sys, math, struct, numpy as np, torch
from train import GPT, CH, V, D, L, H, FF, T, prep
HD = D // H
SX = 32                      # escala de la salida de las normas (Q5)
NEXP = 192
EXP7 = [min(127, int(round(127 * math.exp(-i / 32)))) for i in range(NEXP)]

def cdiv(a, b):              # division de C (trunca hacia cero)
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b > 0) else -q
def isqrt(n): return math.isqrt(n)
def clamp(x, lo, hi): return max(lo, min(hi, x))

class Lin:                   # una matriz cuantizada: y = ((sum w*x) * M >> 16) + B
    def __init__(s, W, b, sx, so, name):
        W = np.asarray(W, np.float64); b = np.asarray(b, np.float64)
        mx = np.abs(W).max(1); mx[mx == 0] = 1e-9
        sw = mx / 127
        s.W = np.round(W / sw[:, None]).astype(np.int64)
        s.M = np.round(sw * so / sx * 65536).astype(np.int64)
        s.B = np.round(b * so).astype(np.int64)
        assert s.M.max() < 32768 and s.M.min() > 0, (name, s.M.max())
        assert np.abs(s.B).max() < 32768, (name, np.abs(s.B).max())
        s.name = name
    def __call__(s, x):
        acc = s.W @ np.asarray(x, np.int64)
        return ((acc * s.M) >> 16) + s.B          # >> de numpy en int64: piso, como el asm
    def bytes(s):
        return (((s.W + 256) & 255) ^ 0x80).astype(np.uint8).tobytes() + \
            s.M.astype('<i2').tobytes() + s.B.astype('<i2').tobytes()

def fold(ln, lin, scale=1.0):  # la norma (gamma, beta) dentro de la matriz que sigue
    g = ln.weight.detach().double().numpy(); be = ln.bias.detach().double().numpy()
    W = lin.weight.detach().double().numpy(); b = lin.bias.detach().double().numpy()
    return (W * g[None, :]) * scale, (b + W @ be) * scale

def build(m, calib):
    """calib: activaciones del modelo de punto flotante, para elegir las escalas"""
    Q = {}
    tok = m.tok.weight.detach().double().numpy(); pos = m.pos.weight.detach().double().numpy()
    def emb(E):
        e = max(0, math.ceil(math.log2(np.abs(E).max() * 256 / 127)))
        return e, np.clip(np.round(E * 256 / 2 ** e), -127, 127).astype(np.int64)
    Q['et'], Q['tok'] = emb(tok); Q['ep'], Q['pos'] = emb(pos)
    Q['layers'] = []
    for li, bk in enumerate(m.blks):
        c = calib[li]
        Sq = 127 / c['q']; Sk = 127 / c['k']; Sv = 127 / c['v']; Sh = 127 / c['h']
        W, b = fold(bk.ln1, bk.qkv)
        W[:D] /= math.sqrt(HD); b[:D] /= math.sqrt(HD)
        lq = Lin(W[:D], b[:D], SX, Sq, 'q'); lk = Lin(W[D:2*D], b[D:2*D], SX, Sk, 'k')
        lv = Lin(W[2*D:], b[2*D:], SX, Sv, 'v')
        lo = Lin(bk.proj.weight.detach().double().numpy(), bk.proj.bias.detach().double().numpy(), Sv, 256, 'proj')
        W, b = fold(bk.ln2, bk.fc1)
        l1 = Lin(W, b, SX, Sh, 'fc1')
        l2 = Lin(bk.fc2.weight.detach().double().numpy(), bk.fc2.bias.detach().double().numpy(), Sh, 256, 'fc2')
        KE = int(round(65536 * 32 / (Sq * Sk)))
        assert 383 <= KE < 65536, KE
        Q['layers'].append(dict(q=lq, k=lk, v=lv, o=lo, f1=l1, f2=l2, KE=KE))
    W, b = fold(m.lnf, m.head)
    Q['head'] = Lin(W, b, SX, 256, 'head')
    return Q

def calibrate(m, text):
    acts = [dict(q=[], k=[], v=[], h=[]) for _ in range(L)]
    hooks = []
    for li, bk in enumerate(m.blks):
        def hq(mod, inp, out, li=li):
            q, k, v = out.split(D, -1)
            acts[li]['q'].append((q / math.sqrt(HD)).abs().flatten()); acts[li]['k'].append(k.abs().flatten()); acts[li]['v'].append(v.abs().flatten())
        def hh(mod, inp, out, li=li): acts[li]['h'].append(torch.relu(out).flatten())
        hooks += [bk.qkv.register_forward_hook(hq), bk.fc1.register_forward_hook(hh)]
    idx = torch.tensor([[CH.index(ch) for ch in text[i:i + 2 * T]] for i in range(0, 64 * 2 * T, 2 * T)])
    with torch.no_grad(): m(idx, 5)
    for h in hooks: h.remove()
    return [{k: float(torch.quantile(torch.cat(v)[:1000000], 0.9999)) for k, v in a.items()} for a in acts]

class Run:                   # la inferencia entera, una letra a la vez (como zgpt.c)
    def __init__(s, Q):
        s.Q = Q; s.t = 0
        s.K = np.zeros((L, T, D), np.int64); s.Vc = np.zeros((L, T, D), np.int64)
    @staticmethod
    def norm(r):
        sm = int(r.sum()); mean = sm >> 5
        d = r - mean
        var = int(((d * d) >> 5).sum())
        sd = max(32, isqrt(var))
        inv = (SX << 15) // sd
        return np.clip((d * inv) >> 15, -127, 127)
    def step(s, c):
        Q = s.Q; p = s.t % T
        r = (Q['tok'][c] << Q['et']) + (Q['pos'][p] << Q['ep'])
        n = min(s.t + 1, T)
        for li, ly in enumerate(Q['layers']):
            z = s.norm(r)
            q = np.clip(ly['q'](z), -127, 127)
            s.K[li, p] = np.clip(ly['k'](z), -127, 127)
            s.Vc[li, p] = np.clip(ly['v'](z), -127, 127)
            o = np.zeros(D, np.int64)
            for h in range(H):
                sl = slice(h * HD, h * HD + HD)
                sc = s.K[li, :n, sl] @ q[sl]
                mx = sc.max()
                idx = np.minimum(NEXP - 1, ((mx - sc) * ly['KE']) >> 16)
                pr = np.array([EXP7[i] for i in idx], np.int64)
                Z = int(pr.sum())
                num = pr @ s.Vc[li, :n, sl]
                o[sl] = [cdiv(int(x), Z) for x in num]
            r = np.clip(r + ly['o'](o), -16383, 16383)
            z = s.norm(r)
            h = np.clip(ly['f1'](z), 0, 127)
            r = np.clip(r + ly['f2'](h), -16383, 16383)
        s.t += 1
        return Q['head'](s.norm(r))           # logits en Q8

def write_bin(Q, path):
    b = bytearray(b'ZGPT')
    b += bytes([V, D, L, H, FF, T, Q['et'], Q['ep']])
    b += CH.encode('latin-1')
    b += bytes(EXP7)
    b += ((Q['tok'] + 256) & 255).astype(np.uint8).tobytes()
    b += ((Q['pos'] + 256) & 255).astype(np.uint8).tobytes()
    for ly in Q['layers']:
        b += struct.pack('<H', ly['KE'])
        for k in ('q', 'k', 'v', 'o', 'f1', 'f2'): b += ly[k].bytes()
    b += Q['head'].bytes()
    open(path, 'wb').write(b)
    return len(b)

if __name__ == '__main__':
    m = GPT(); m.load_state_dict(torch.load('/tmp/gpt/model.pt')); m.eval()
    t = prep(); va = t[int(len(t) * .95):]
    cal = calibrate(m, va)
    print('calibracion', [{k: round(v, 2) for k, v in c.items()} for c in cal])
    Q = build(m, cal)
    print('ZGPT.BIN', write_bin(Q, '/tmp/gpt/ZGPT.BIN'), 'bytes')
    # perdida del modelo entero contra el de punto flotante
    N = int(sys.argv[1]) if len(sys.argv) > 1 else 600
    seg = va[1000:1000 + N + 1]
    ids = [CH.index(c) for c in seg]
    R = Run(Q); li = 0.0
    for i in range(N):
        lg = R.step(ids[i]) / 256.0
        lg = lg - lg.max(); li += -(lg[ids[i + 1]] - math.log(np.exp(lg).sum()))
    with torch.no_grad():
        lg = m(torch.tensor([ids[:N]]), 0).squeeze(0)
        lfl = torch.nn.functional.cross_entropy(lg, torch.tensor(ids[1:N + 1])).item()
    print(f'entero: {li / N:.3f} nats/letra en {N} letras; punto flotante: {lfl:.3f}')

def greedy(Q, prompt, n):
    """lo que escribe ZGPT /T0 /Ln prompt (sin las mayusculas)"""
    R = Run(Q); lg = R.step(CH.index('\n'))
    for c in prompt: lg = R.step(CH.index(c))
    out = ''
    for i in range(n):
        c = int(np.argmax(lg)); out += CH[c]; lg = R.step(c)
    return out
