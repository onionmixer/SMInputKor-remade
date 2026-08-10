#!/bin/sh
cd /ndrv/SMInputKor-remade
cc -ObjC -Isrc -o /tmp/bstest tools/test/bstest.m src/FrontEnd.m src/Automata.m src/NoCheckAutomata.m data/automata_tables.m -framework AppKit -framework Foundation > /tmp/bs.log 2>&1
grep -i error /tmp/bs.log
for A in "gks 3" "rhk 3" "rkqt 4" "ekfr 4" "dksk 2"; do
  echo "===== $A ====="
  /tmp/bstest $A
done
