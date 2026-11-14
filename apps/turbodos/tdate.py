# tdate.py DATE.COM tdate.cim TDATE.COM : aplica el parche de tdate.z80 al DATE.COM de IMS
# (tdate.cim sale de: zmac -o tdate.cim tdate.z80)
import sys
d=bytearray(open(sys.argv[1],'rb').read()); p=open(sys.argv[2],'rb').read()
assert len(d)==0x580, 'no es el DATE.COM de IMS (1408 bytes)'
PRY=0x680; YFIX=0x680+p.index(bytes.fromhex('3af205fe30'))
assert d[0x335:0x33b]==bytes.fromhex('3af205cd5305') and d[0x2a5:0x2aa]==bytes.fromhex('061c3af205')
d[0x335:0x33b]=bytes([0xcd,PRY&255,PRY>>8,0,0,0])
d[0x2a5:0x2aa]=bytes([0xcd,YFIX&255,YFIX>>8,0,0])
open(sys.argv[3],'wb').write(d+p)
