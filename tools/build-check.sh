#!/bin/sh
# build-check.sh — 재구성 소스 부분 컴파일 검증(실기 OPENSTEP).
# 각 .m 을 cc -ObjC -c 로 컴파일해 시그니처/extern/헤더 정합성을 확인한다.
# (미확정 NOTE 메서드는 ObjC 동적 디스패치라 경고로 통과; 진짜 오류는 구문·
#  미선언 C 심볼·타입 불일치.) NFS .o 권한 회피 위해 /tmp 로 출력.
cd /ndrv/SMInputKor-remade || exit 1
OBJ=/tmp/smk_obj
rm -rf $OBJ; mkdir $OBJ
INCS="-Isrc"
SRCS="src/Automata.m src/NoCheckAutomata.m src/CvtField.m src/LazyPanel.m \
      src/FrontEnd.m src/HanjaConverter.m src/Preference.m src/Dispatcher.m \
      data/automata_tables.m data/layout_tables.m"
for f in $SRCS; do
    echo "===== $f ====="
    cc -ObjC $INCS -c $f -o $OBJ/`basename $f .m`.o 2>&1 | grep -vi warning | head -25
done
echo "===== 생성된 오브젝트 ====="
ls -l $OBJ 2>&1 | grep '\.o'
