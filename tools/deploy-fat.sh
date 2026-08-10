#!/bin/sh
# 새로 빌드한 fat SMHangul 을 설치본에 덮어쓴다(래퍼 없는 plain 방식 유지).
APP=/NextLibrary/InputManagers/SMHangul/SMHangul.app
for p in `ps -ax | grep SMHang | grep -v grep | awk '{print $1}'`; do kill -9 $p; done
chmod u+w $APP $APP/SMHangul
cp /tmp/smk_fat/SMHangul $APP/SMHangul
chmod 555 $APP/SMHangul $APP
echo "=== installed ==="
ls -l $APP/SMHangul
file $APP/SMHangul | head -1
echo "=== SMKeyboardType default registered? (defaults) ==="
dread=`defaults read SMHangul SMKeyboardType 2>/dev/null`
echo "SMKeyboardType(user)=${dread:-<unset,uses registerDefaults 0>}"
