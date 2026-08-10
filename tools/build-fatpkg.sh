#!/bin/sh
APP=/NextLibrary/InputManagers/SMHangul/SMHangul.app
# 1) fat 바이너리 설치(클린)
for p in `ps -ax | grep SMHang | grep -v grep | awk '{print $1}'`; do kill -9 $p; done
chmod u+w $APP $APP/SMHangul
rm -f $APP/SMHangul $APP/SMHangul.real
cp /tmp/smk_fat/SMHangul $APP/SMHangul
chmod 555 $APP/SMHangul $APP
echo "=== installed exe ==="; file $APP/SMHangul
# 2) 스테이징 + package
ROOT=/tmp/smk_pkgroot; DEST=/tmp/smk_pkgout
IM=$ROOT/NextLibrary/InputManagers
rm -rf $ROOT $DEST; mkdir $ROOT $ROOT/NextLibrary $IM $DEST
cp -R /NextLibrary/InputManagers/SMHangul $IM/SMHangul
/NextAdmin/Installer.app/package $ROOT /ndrv/SMInputKor-remade/pkg/Softmagic_Hangul.info -d $DEST </dev/null >/tmp/pkg.log 2>&1
# 3) bigtar 페이로드 교체
sh /ndrv/SMInputKor-remade/tools/fixtar.sh >/tmp/fixtar.log 2>&1
# 4) 검증
PKG=$DEST/Softmagic_Hangul.pkg
BT=/NextAdmin/Installer.app/installer_bigtar
uncompress -c $PKG/Softmagic_Hangul.tar.Z > /tmp/ourpay.tar 2>/dev/null
echo "=== payload 파일수(22 기대) ==="; $BT tf /tmp/ourpay.tar | wc -l
echo "=== 페이로드 내 exe 아치 ==="
cd /tmp; rm -rf pv; mkdir pv; cd pv
$BT xf /tmp/ourpay.tar ./NextLibrary/InputManagers/SMHangul/SMHangul.app/SMHangul 2>/dev/null
file ./NextLibrary/InputManagers/SMHangul/SMHangul.app/SMHangul
echo "=== pkg ==="; ls -l $PKG
