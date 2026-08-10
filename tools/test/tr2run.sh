#!/bin/sh
cd /ndrv/SMInputKor-remade
cc -ObjC -Isrc -o /tmp/tr2 tools/test/tr2.m \
   src/FrontEnd.m src/Automata.m src/NoCheckAutomata.m \
   data/automata_tables.m data/layout_tables.m \
   -framework AppKit -framework Foundation > /tmp/tr2.log 2>&1
grep -i 'error' /tmp/tr2.log
if [ -x /tmp/tr2 ]; then /tmp/tr2; else echo "BUILD FAILED"; tail -15 /tmp/tr2.log; fi
