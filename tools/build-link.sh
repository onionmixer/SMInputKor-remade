#!/bin/sh
# build-link.sh — 재구성 소스를 SMHangul 실행파일로 전체 링크(실기 OPENSTEP).
# 구조 등가 검증(정본 __OBJC diff)용. /tmp 로 출력(NFS 권한 회피).
cd /ndrv/SMInputKor-remade || exit 1
OUT=/tmp/smk_link; rm -rf $OUT; mkdir $OUT
INCS="-Isrc"
SRCS="src/Automata.m src/NoCheckAutomata.m src/CvtField.m src/LazyPanel.m \
      src/FrontEnd.m src/HanjaConverter.m src/Preference.m src/Dispatcher.m \
      src/glue.m data/automata_tables.m data/layout_tables.m"
echo "===== linking SMHangul ====="
cc -ObjC $INCS -o $OUT/SMHangul $SRCS -framework AppKit -framework Foundation 2>&1 \
    | grep -vi warning | head -40
echo "===== result ====="
ls -l $OUT/SMHangul 2>&1
file $OUT/SMHangul 2>&1
