#!/bin/sh
cd /ndrv/SMInputKor-remade
echo "=== fat 빌드(컴파일 확인) ==="
sh tools/build-fat.sh 2>&1 | grep -vi 'In function' | tail -3
echo "=== isJamoKey 동치 검증 ==="
cc -ObjC -Isrc -o /tmp/jk tools/test/jamokey.m src/Automata.m data/automata_tables.m -framework Foundation >/tmp/jk.log 2>&1
grep -i error /tmp/jk.log
/tmp/jk
