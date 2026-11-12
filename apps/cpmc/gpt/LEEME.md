# ZGPT: entrenar y exportar

- `train.py [pasos]`: entrena el modelo con `quijote.txt` (El Quijote, en Latin-1; se baja de
  github.com/alexbertis/QuijoteNet) y guarda `model.pt`. Necesita PyTorch.
- `export.py`: lo pasa a enteros, escribe `ZGPT.BIN` y compara la pérdida del modelo entero con la
  del de punto flotante. Su clase `Run` hace las mismas cuentas que `zgpt.c`.
- `gentest.py "comienzo" N`: lo que escribe `ZGPT /T0 /LN comienzo`, para compararlo con el Z80.

Las rutas están en `/tmp/gpt/`; se cambian al principio de cada archivo.
