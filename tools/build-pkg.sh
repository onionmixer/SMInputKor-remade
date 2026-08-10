#!/bin/sh
# build-pkg.sh — 재구성 SMHangul 을 원본과 구성 동일한 .pkg 로 묶는다(실기 OPENSTEP).
# 라이브 SMHangul 트리를 로컬 /tmp 로 복사(비파괴)해 실행파일만 우리 빌드본으로
# 교체하고, /NextAdmin/Installer.app/package 로 패키징. 모드는 원본 보존(교체 위해
# .app 디렉터리·실행파일만 일시 쓰기허용 후 원복). NeXT: mkdir -p 없음, dirname 없음.
ROOT=/tmp/smk_pkgroot
DEST=/tmp/smk_pkgout
IM=$ROOT/NextLibrary/InputManagers
APP=$IM/SMHangul/SMHangul.app
rm -rf $ROOT $DEST
mkdir $ROOT; mkdir $ROOT/NextLibrary; mkdir $IM; mkdir $DEST

echo "=== 라이브 SMHangul 트리 스테이징(모드 보존 cp -R) ==="
cp -R /NextLibrary/InputManagers/SMHangul $IM/SMHangul

echo "=== 실행파일만 우리 빌드본으로 교체(.app 일시 쓰기허용) ==="
chmod u+w $APP
rm -f $APP/SMHangul
cd /ndrv/SMInputKor-remade
cc -ObjC -Isrc -o $APP/SMHangul \
   src/Automata.m src/NoCheckAutomata.m src/CvtField.m src/LazyPanel.m src/FrontEnd.m \
   src/HanjaConverter.m src/Preference.m src/Dispatcher.m src/glue.m data/automata_tables.m data/layout_tables.m \
   -framework AppKit -framework Foundation 2>&1 | grep -i error
chmod 555 $APP/SMHangul      # 원본 실행파일 모드(r-xr-xr-x)
chmod 555 $APP               # .app 디렉터리 모드 원복
echo "staged exe:"; ls -l $APP/SMHangul

echo "=== package 실행 ==="
/NextAdmin/Installer.app/package $ROOT /ndrv/SMInputKor-remade/pkg/Softmagic_Hangul.info -d $DEST < /dev/null
echo "=== 산출물 ==="
ls -lR $DEST
