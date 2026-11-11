' EJEMPLO.BAS - un poco de todo ZBAS: SUB y FUNCTION, recursion, SELECT CASE,
' matrices, textos y las finanzas de ZCALC. Correr con: ZBAS EJEMPLO
CLS
PRINT "ZBAS sample program"
PRINT STRING$(40, "-")

' la tabla de un prestamo (la cuota sale de PMT, como en ZCALC)
capital = 1000000: tasa = 0.015: meses = 6
cuota = ROUND(PMT(tasa, meses, capital), 2)
PRINT "Loan of"; capital; "at"; tasa * 100; "% a month:"; cuota; "a month"
saldo = capital
FOR m = 1 TO meses
  interes = ROUND(saldo * tasa, 2)
  saldo = saldo - (cuota - interes)
  IF m = meses THEN saldo = 0
  PRINT "  month"; m, FORMAT$(interes, 2), FORMAT$(saldo, 2)
NEXT

' recursion: las torres de Hanoi con 3 discos
movs = 0
CALL hanoi(3, "A", "C", "B")
PRINT "Hanoi with 3 disks:"; movs; "moves"

' una FUNCTION que se llama a si misma
PRINT "10! ="; fact(10)

' SELECT CASE con rangos y textos
FOR n = 1 TO 4
  READ animal$
  SELECT CASE LEN(animal$)
    CASE 1 TO 3: PRINT animal$; " is short"
    CASE IS > 5: PRINT animal$; " is long"
    CASE ELSE: PRINT animal$; " is medium"
  END SELECT
NEXT
DATA "cat", "horse", "elephant", "dog"

' una matriz y la burbuja
DIM v(9)
RANDOMIZE
FOR i = 0 TO 9: v(i) = INT(RND * 100): NEXT
DO
  cambio = 0
  FOR i = 0 TO 8
    IF v(i) > v(i + 1) THEN SWAP v(i), v(i + 1): cambio = 1
  NEXT
LOOP WHILE cambio
PRINT "Sorted:";
FOR i = 0 TO 9: PRINT v(i);: NEXT
PRINT
PRINT "Today is "; DATE$; ", "; TIME$
END

SUB hanoi(n, desde$, hasta$, por$)
  IF n = 0 THEN EXIT SUB
  CALL hanoi(n - 1, desde$, por$, hasta$)
  movs = movs + 1
  CALL hanoi(n - 1, por$, hasta$, desde$)
END SUB

FUNCTION fact(n)
  IF n <= 1 THEN RETURN 1
  fact = n * fact(n - 1)
END FUNCTION
