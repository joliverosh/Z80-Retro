import sys, torch
from export import *
m = GPT(); m.load_state_dict(torch.load('/tmp/gpt/model.pt')); m.eval()
t = prep(); va = t[int(len(t) * .95):]
Q = build(m, calibrate(m, va))
print('bytes', write_bin(Q, '/tmp/gpt/ZGPT.BIN'))
print(repr(greedy(Q, sys.argv[1], int(sys.argv[2]))))
