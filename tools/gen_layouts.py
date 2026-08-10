#!/usr/bin/env python3
"""
gen_layouts.py — 자판 레이아웃 3종(두벌식/세벌식390/세벌식최종)을 선언적으로 정의하고
automaton 이 쓰는 Johab 인덱스 표(cho/jung/jong/role)를 생성한다. (Phase 1)

- 키→자모 매핑 출처: libhangul (github.com/libhangul/libhangul)
  data/keyboards/hangul-keyboard-{39,3f}.xml.template 의 U+11xx 조합형 자모.
- 변환: U+11xx(초성 1100~, 중성 1161~, 종성 11A8~) → 본 automaton 의 Johab 인덱스
  (cho: (U-1100)+2 / jung: 표 / jong: 갭(18) 반영). 두벌식 추출표로 교차검증.
- 산출: role/cho/jung/jong 128-엔트리 표. role: 0=비자모(통과) 1=초성 2=중성 3=종성.
  (token/actionTbl 등 상태기계 결선은 Phase 3에서. 여기선 매핑·검증까지.)
"""

# --- U+11xx → Johab 인덱스 변환기 (두벌식 추출표로 검증) ---
JUNG_IDX = [3,4,5,6,7,10,11,12,13,14,15,18,19,20,21,22,23,26,27,28,29]  # 조합형 중성 0~20

def cho_index(u):
    if 0x1100 <= u <= 0x1112: return (u - 0x1100) + 2
    return None
def jung_index(u):
    if 0x1161 <= u <= 0x1175: return JUNG_IDX[u - 0x1161]
    return None
def jong_index(u):
    if 0x11A8 <= u <= 0x11C2:
        n = u - 0x11A8
        return n + 2 if u <= 0x11B7 else n + 3   # 종성 인덱스 갭(18) 반영
    return None

def role_and_index(u):
    """U+11xx → (role, index). role 1=초성 2=중성 3=종성, 아니면 (0,0)."""
    c = cho_index(u)
    if c is not None: return (1, c)
    j = jung_index(u)
    if j is not None: return (2, j)
    g = jong_index(u)
    if g is not None: return (3, g)
    return (0, 0)

# --- 레이아웃 정의: char(0~127) → U+11xx (자모만; 비자모 키는 생략=통과) ---
# 세벌식390 (libhangul hangul-keyboard-39)
S390 = {
 0x21:0x11BD,0x27:0x1110,0x2F:0x1169,0x30:0x110F,0x31:0x11C2,0x32:0x11BB,0x33:0x11B8,
 0x34:0x116D,0x35:0x1172,0x36:0x1163,0x37:0x1168,0x38:0x1174,0x39:0x116E,0x3B:0x1107,
 0x41:0x11AE,0x43:0x11B1,0x44:0x11B0,0x45:0x11BF,0x46:0x11A9,0x51:0x11C1,0x52:0x1164,
 0x53:0x11AD,0x56:0x11B6,0x57:0x11C0,0x58:0x11B9,0x5A:0x11BE,
 0x61:0x11BC,0x62:0x116E,0x63:0x1166,0x64:0x1175,0x65:0x1167,0x66:0x1161,0x67:0x1173,
 0x68:0x1102,0x69:0x1106,0x6A:0x110B,0x6B:0x1100,0x6C:0x110C,0x6D:0x1112,0x6E:0x1109,
 0x6F:0x110E,0x70:0x1111,0x71:0x11BA,0x72:0x1162,0x73:0x11AB,0x74:0x1165,0x75:0x1103,
 0x76:0x1169,0x77:0x11AF,0x78:0x11A8,0x79:0x1105,0x7A:0x11B7,
}
# 세벌식최종/391 (libhangul hangul-keyboard-3f)
SFIN = {
 0x21:0x11A9,0x23:0x11BD,0x24:0x11B5,0x25:0x11B4,0x27:0x1110,0x2F:0x1169,0x30:0x110F,
 0x31:0x11C2,0x32:0x11BB,0x33:0x11B8,0x34:0x116D,0x35:0x1172,0x36:0x1163,0x37:0x1168,
 0x38:0x1174,0x39:0x116E,0x3B:0x1107,0x40:0x11B0,0x41:0x11AE,0x43:0x11BF,0x44:0x11B2,
 0x45:0x11AC,0x46:0x11B1,0x47:0x1164,0x51:0x11C1,0x52:0x11B6,0x53:0x11AD,0x54:0x11B3,
 0x56:0x11AA,0x57:0x11C0,0x58:0x11B9,0x5A:0x11BE,
 0x61:0x11BC,0x62:0x116E,0x63:0x1166,0x64:0x1175,0x65:0x1167,0x66:0x1161,0x67:0x1173,
 0x68:0x1102,0x69:0x1106,0x6A:0x110B,0x6B:0x1100,0x6C:0x110C,0x6D:0x1112,0x6E:0x1109,
 0x6F:0x110E,0x70:0x1111,0x71:0x11BA,0x72:0x1162,0x73:0x11AB,0x74:0x1165,0x75:0x1103,
 0x76:0x1169,0x77:0x11AF,0x78:0x11A8,0x79:0x1105,0x7A:0x11B7,
}

# 두벌식(표준) — 교차검증용 char→U+11xx (초성/중성; 종성은 초성과 키 공유라 별도 아님)
# 2벌은 한 키가 초성·종성 겸용 → Automata(token_tbl 등)로 분류. 여기선 변환기 검증만.
DUB_CHO = {  # 자음 키 → 초성 U+110x
 'q':0x1107,'w':0x110C,'e':0x1103,'r':0x1100,'t':0x1109,'a':0x1106,'s':0x1102,'d':0x110B,
 'f':0x1105,'g':0x1112,'z':0x110F,'x':0x1110,'c':0x110E,'v':0x1111,'b':0x1111,'n':0x1102,
 'Q':0x1108,'W':0x110D,'E':0x1104,'R':0x1101,'T':0x110A,
}
DUB_JUNG = {
 'y':0x116D,'u':0x1167,'i':0x1163,'o':0x1162,'p':0x1166,'h':0x1169,'j':0x1165,'k':0x1161,
 'l':0x1175,'b':0x1172,'n':0x116E,'m':0x1173,'O':0x1164,'P':0x1168,
}

# 종성 U+11xx → 호환 자모 U+31xx (단독 자음 표시용). 겹받침 포함, 초성전용(ㄸㅃㅉ) 갭 반영.
JONG_COMPAT = {
 0x11A8:0x3131,0x11A9:0x3132,0x11AA:0x3133,0x11AB:0x3134,0x11AC:0x3135,0x11AD:0x3136,
 0x11AE:0x3137,0x11AF:0x3139,0x11B0:0x313A,0x11B1:0x313B,0x11B2:0x313C,0x11B3:0x313D,
 0x11B4:0x313E,0x11B5:0x313F,0x11B6:0x3140,0x11B7:0x3141,0x11B8:0x3142,0x11B9:0x3144,
 0x11BA:0x3145,0x11BB:0x3146,0x11BC:0x3147,0x11BD:0x3148,0x11BE:0x314A,0x11BF:0x314B,
 0x11C0:0x314C,0x11C1:0x314D,0x11C2:0x314E,
}

def jongtwo_for(layout):
    """ASCII→종성 단독 자음 표시코드(0xA4xx = 호환자모 + 0x7370, unfinishedUnicode 역).
    종성 놓을 자리 없을 때 자음을 잃지 않고 단독 확정하기 위함(잘못된 백스페이스 방지)."""
    t=[0]*128
    for ch,u in layout.items():
        if u in JONG_COMPAT:
            t[ch]=JONG_COMPAT[u]+0x7370
    return t

def gen(layout):
    role=[0]*128; cho=[0]*128; jung=[0]*128; jong=[0]*128
    for ch,u in layout.items():
        r,idx = role_and_index(u)
        role[ch]=r
        if r==1: cho[ch]=idx
        elif r==2: jung[ch]=idx
        elif r==3: jong[ch]=idx
    return role,cho,jung,jong

def verify_converters():
    """두벌식 추출표(data/automata_tables.m)와 대조해 변환기 정확성 확인."""
    import re,os
    p=os.path.join(os.path.dirname(__file__),'..','data','automata_tables.m')
    if not os.path.exists(p):
        print("[verify] data/automata_tables.m 없음 — 스킵"); return
    src=open(p).read()
    def arr(n):
        m=re.search(r'%s\[[0-9]*\]\s*=\s*\{([^}]*)\}'%n,src)
        return [int(x) for x in re.findall(r'-?\d+',m.group(1))] if m else None
    cho2=arr('cho_tbl'); jung2=arr('jung_tbl')
    ok=True
    for ch,u in DUB_CHO.items():
        exp=cho2[ord(ch)]; got=cho_index(u)
        if exp and got!=exp: print("  CHO mismatch %s: tbl=%d conv=%s"%(ch,exp,got)); ok=False
    for ch,u in DUB_JUNG.items():
        exp=jung2[ord(ch)]; got=jung_index(u)
        if exp and got!=exp: print("  JUNG mismatch %s: tbl=%d conv=%s"%(ch,exp,got)); ok=False
    print("[verify] 변환기 두벌식 대조:", "OK" if ok else "FAIL")

def dump(name,layout):
    role,cho,jung,jong=gen(layout)
    n=sum(1 for r in role if r)
    print("=== %s : 자모키 %d개 ==="%(name,n))
    for ch in range(0x21,0x7f):
        if role[ch]:
            rn={1:'초',2:'중',3:'종'}[role[ch]]
            print("  %c(%02x) %s idx=%d"%(ch,ch,rn, cho[ch] or jung[ch] or jong[ch]))

def emit_c(path):
    """방출: data/layout_tables.m — 390/최종의 role/cho/jung/jong 128표.
    role: 0 비자모(통과) 1 초성 2 중성 3 종성. cho/jung/jong: Johab 인덱스(해당 role일 때).
    Phase2/3에서 NoCheckAutomata(또는 3벌 엔진)가 layout에 따라 이 표를 참조."""
    def emit(f,nm,tab):
        f.write("const unsigned short %s[128] = {\n"%nm)
        for i in range(0,128,16):
            f.write("    "+",".join("%3d"%tab[j] for j in range(i,i+16))+",\n")
        f.write("};\n\n")
    with open(path,'w') as f:
        f.write("/* layout_tables.m — 자판별 자모 매핑(Phase1 생성물, gen_layouts.py).\n"
                " * 출처 libhangul(39/3f). role:0통과 1초 2중 3종. 커밋 금지(빌드 생성).\n"
                " * 두벌식은 기존 Automata(token_tbl 등) 사용 — 여기엔 3벌 2종만. */\n\n")
        for nm,lay in (('390',S390),('Fin',SFIN)):
            role,cho,jung,jong=gen(lay)
            emit(f,"lyRole_%s"%nm,role); emit(f,"lyCho_%s"%nm,cho)
            emit(f,"lyJung_%s"%nm,jung); emit(f,"lyJong_%s"%nm,jong)
            emit(f,"lyJongTwo_%s"%nm,jongtwo_for(lay))  # 종성 단독 자음 표시코드
    print("[emit] wrote",path)

if __name__=='__main__':
    import sys,os
    verify_converters()
    dump('sebeolsik390',S390)
    dump('sebeolsikFinal',SFIN)
    if len(sys.argv)>1:
        emit_c(sys.argv[1])
    else:
        emit_c(os.path.join(os.path.dirname(__file__),'..','data','layout_tables.m'))
