#!/bin/sh
# build-app.sh — 재구성 SMHangul 을 .app 번들로 조립(실기 OPENSTEP).
# 실행파일 링크 + 정본 Resources(eng/kor/SMI.tiff + nib) 복사 → NSImage imageNamed:
# 가 번들의 이미지를 실제로 사용. 벤더 리소스는 정본에서 가져옴(리포 비커밋).
# 출력은 /tmp(로컬, NFS 권한 회피).
cd /ndrv/SMInputKor-remade || exit 1
APP=/tmp/smk_app/SMHangul.app
rm -rf /tmp/smk_app; mkdir /tmp/smk_app; mkdir $APP   # NeXT mkdir 은 -p 없음
INCS="-Isrc"
SRCS="src/Automata.m src/NoCheckAutomata.m src/CvtField.m src/LazyPanel.m \
      src/FrontEnd.m src/HanjaConverter.m src/Preference.m src/Dispatcher.m \
      src/glue.m data/automata_tables.m data/layout_tables.m"
echo "===== link -> SMHangul.app/SMHangul ====="
cc -ObjC $INCS -o $APP/SMHangul $SRCS -framework AppKit -framework Foundation 2>&1 \
    | grep -i error
echo "===== 정본 Resources 복사(이미지+nib 실제 사용) ====="
cp -R extracted/live/SMHangul/SMHangul.app/Resources $APP/Resources
chmod -R u+w $APP
echo "===== 번들 구조 ====="
ls $APP
echo "--- Resources ---"
ls $APP/Resources
echo "===== 사용되는 이미지(imageNamed: eng/kor/SMI → Resources/*.tiff) ====="
ls -l $APP/Resources/eng.tiff $APP/Resources/kor.tiff $APP/Resources/SMI.tiff
echo "===== 실행파일 ====="
ls -l $APP/SMHangul; file $APP/SMHangul
