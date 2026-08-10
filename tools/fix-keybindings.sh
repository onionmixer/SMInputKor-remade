#!/bin/sh
# 손상된 ~/Library/KeyBindings/SMHangul.dict 복구.
# 증상: Preference 저장이 action->keystroke 로 뒤집어 쓰고 나머지 바인딩을 잃어
#       한/영 전환·공백·백스페이스·화살표가 죽음. 정본(keystroke->action, 13항목)으로 복원.
D="$HOME/Library/KeyBindings"
F="$D/SMHangul.dict"
echo "=== before ==="
cat "$F" 2>&1
cp "$F" "$F.broken" 2>/dev/null
cat > "$F" <<'EOF'
{
    "$ " = "toggleConversionMode:";
    "^ " = "inputModeChange:";
    "~ " = "hanjaConvert:";
    " " = "enteredSpace:";
    "\015" = "insertNewline:";
    "\012" = "insertNewline:";
    "\003" = "insertNewline:";
    "\010" = "deleteBackward:";
    "\177" = "deleteBackward:";
    "\UF702" = "moveLeft:";
    "\UF703" = "moveRight:";
    "\UF700" = "moveUp:";
    "\UF701" = "moveDown:";
}
EOF
echo "=== after ==="
cat "$F"
ls -l "$F"
