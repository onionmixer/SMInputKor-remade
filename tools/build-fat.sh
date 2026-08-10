#!/bin/sh
# build-fat.sh — 다중 아키텍처(fat/MAB) SMHangul 빌드. 실기에 백엔드가 있는 아치만.
# 이 머신: i386/m68k/sparc OK, hppa 는 cc1obj 부재로 제외. 산출 /tmp/smk_fat/SMHangul.
cd /ndrv/SMInputKor-remade || exit 1
OUT=/tmp/smk_fat; rm -rf $OUT; mkdir $OUT
INCS="-Isrc"
SRCS="src/Automata.m src/NoCheckAutomata.m src/CvtField.m src/LazyPanel.m \
      src/FrontEnd.m src/HanjaConverter.m src/Preference.m src/Dispatcher.m \
      src/glue.m data/automata_tables.m data/layout_tables.m"
ARCHS="-arch i386 -arch m68k -arch sparc"
# CD의 멀티플랫폼 라이브러리(fat 프레임워크·crt·backend)를 시스템에 설치했으므로
# 설치 프레임워크로 직접 fat 링크. (hppa 는 cc1obj 부재로 제외.)
echo "===== fat link SMHangul ($ARCHS) ====="
cc -ObjC $ARCHS $INCS -o $OUT/SMHangul $SRCS \
   -framework AppKit -framework Foundation 2>&1 \
   | grep -vi warning | grep -vi 'In function' | head -40
echo "===== result ====="
ls -l $OUT/SMHangul
file $OUT/SMHangul
