#!/bin/sh
ROOT=/tmp/smk_pkgroot
PKG=/tmp/smk_pkgout/Softmagic_Hangul.pkg
BT=/NextAdmin/Installer.app/installer_bigtar
cd $ROOT || exit 1
rm -f $PKG/Softmagic_Hangul.tar $PKG/Softmagic_Hangul.tar.Z
$BT cf $PKG/Softmagic_Hangul.tar .
echo "=== payload file count (bigtar) ==="
$BT tf $PKG/Softmagic_Hangul.tar | wc -l
echo "=== nib entries present? ==="
$BT tf $PKG/Softmagic_Hangul.tar | grep -i '\.nib/' 
/usr/ucb/compress $PKG/Softmagic_Hangul.tar
echo "=== final pkg ==="
ls -l $PKG
