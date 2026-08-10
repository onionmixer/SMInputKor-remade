#!/bin/sh
cd /ndrv/SMInputKor-remade
cc -ObjC -Isrc -o /tmp/tr3 tools/test/tr3.m \
   src/NoCheckAutomata.m src/Automata.m \
   data/automata_tables.m data/layout_tables.m \
   -framework Foundation > /tmp/tr3.log 2>&1
grep -i 'error\|warning: implicit' /tmp/tr3.log
if [ -x /tmp/tr3 ]; then /tmp/tr3; else echo "BUILD FAILED"; tail -20 /tmp/tr3.log; fi
