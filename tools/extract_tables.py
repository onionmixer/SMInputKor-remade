#!/usr/bin/env python3
"""
extract_tables.py — 정본 SMHangul 바이너리에서 자동자(Automata/NoCheckAutomata)
가 참조하는 조합/인코딩 테이블을 추출해 C 배열(data/automata_tables.m)로 생성한다.

IP 위생: 벤더 데이터표는 소스에 verbatim 커밋하지 않는다. 이 도구는 사용자의
정본 바이너리를 빌드 시점에 읽어 data/(gitignore)에 테이블을 재생성한다. 표
주소·원소폭·개수는 IDA 정적분석으로 실측 확정(doc/RE_ANALYSIS.md).

주소는 VM(imagebase 0x2000). thin i386 Mach-O(magic feedface, cputype 7)를 직접
파싱해 VM→파일오프셋 매핑을 만든다.

사용: extract_tables.py [SMHangul_binary] [out.m]
기본 입력: extracted/live/SMHangul/SMHangul.app/SMHangul
"""
import sys, os, struct

# --- 확정된 테이블 명세: (C이름, VM주소, 원소수). 전부 unsigned short. ---
TABLES = [
    # 2벌식 분류/결합
    ("token_tbl", 0xb330, 128), ("cho_tbl", 0xb430, 128),
    ("jung_tbl",  0xb530, 128), ("jong_tbl", 0xb630, 128),
    # make_two 비트팩킹 (표준: i<<10 / i<<5 / i — 참고용, 정본값 그대로 추출)
    ("cho_val",   0xb730, 32),  ("jung_val", 0xb770, 32), ("jong_val", 0xb7b0, 32),
    # 단독 조합중/완성 코드
    ("cho_two",   0xb7f0, 32),  ("jaeum_two", 0xb830, 32), ("moeum_two", 0xb870, 32),
    # 액션표 (5 status x 5 token)
    ("act_tbl",   0xb8b0, 25),
    # 복종성/복모음/복자음 결합쌍
    ("bok_ja1",   0xb8e2, 11),  ("bok_ja2", 0xb8f8, 11), ("bok_ja", 0xb90e, 11),
    ("bok_mo1",   0xb924, 13),  ("bok_mo2", 0xb93e, 13), ("bok_mo", 0xb958, 13),
    ("bok_jaeum1",0xb972, 11),  ("bok_jaeum2",0xb988,11),("bok_jaeum",0xb99e,11),
    # 3벌식 (NoCheckAutomata)
    ("oneOfToken",0x41ed6,128), ("oneOfCho", 0x41fd6,128),
    ("oneOfJung", 0x420d6,128), ("oneOfJong",0x421d6,128),
    ("twoOfCho",  0x422d6,32),  ("actionTbl",0x42316,45),
    # ks: KS(EUC 완성형)→표준 유니코드. unicodeFromKS: 는 ks[code-0x8144].
    #   원본 실측(0x540c): `*(WORD*)&stru_20D0.segname[2*code - 8]`,
    #   &stru_20D0.segname = 0x20D0+0x10 = 0x20E0 → 유효 base = 0x20E0-8 = 0x20D8.
    #   따라서 ks[0](code 0x8144) VM = 0x20D8 + 2*0x8144 = 0x12360 (0x12358 아님 —
    #   이전 값은 8바이트=4코드 빨라 한→d54f 처럼 유니코드가 어긋났음). 검증:
    #   가0xB0A1→AC00, 하0xC7CF→D558, 한0xC7D1→D55C, 글0xB1DB→AE00, 은0xC0BA→C740.
    #   개수는 Uni_to_FullKorean_Table(0x21ED6) 직전까지: (0x21ED6-0x12360)/2 = 32187.
    ("ks",                    0x12360, 32187),
    # Uni_to_FullKorean_Table: FullKorean 역방향. ksFromUnicode: 가 [uni] 로 직접 인덱싱.
    ("Uni_to_FullKorean_Table", 0x21ed6, 65536),
    # SMcode_Hanja_Table: 내장 한자 코드표. 114 ushort/행 × 484행(행[0]=한글 KS 키,
    #   행[1..113]=한자 KS 후보, 0 종료). HanjaConverter hanjaWithString:index: 가 조회.
    ("SMcode_Hanja_Table", 0x42370, 114 * 484),
]
MAP_IDX = 0xb270    # 32개 행배열 포인터
MAP_CNT = 0xb2f0    # 32개 행별 카운트(ushort)


def macho_vm2off(data):
    """thin 32-bit Mach-O의 LC_SEGMENT를 읽어 vm->fileoff 세그먼트 리스트 반환."""
    magic = struct.unpack_from("<I", data, 0)[0]
    if magic != 0xfeedface:
        raise SystemExit("not a thin 32-bit Mach-O (magic=0x%x)" % magic)
    ncmds = struct.unpack_from("<I", data, 16)[0]
    off = 28  # mach_header(32-bit) = 28 bytes
    segs = []
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, off)
        if cmd == 0x1:  # LC_SEGMENT
            vmaddr, vmsize, fileoff, filesize = struct.unpack_from("<IIII", data, off+24)
            segs.append((vmaddr, vmsize, fileoff, filesize))
        off += cmdsize
    def vm2off(vaddr):
        for vmaddr, vmsize, fileoff, filesize in segs:
            if vmaddr <= vaddr < vmaddr + vmsize:
                o = fileoff + (vaddr - vmaddr)
                if o + 2 > len(data):
                    raise SystemExit("vm 0x%x maps past EOF" % vaddr)
                return o
        raise SystemExit("vm 0x%x not in any segment" % vaddr)
    return vm2off


def rd_ushorts(data, vm2off, vaddr, count):
    o = vm2off(vaddr)
    return list(struct.unpack_from("<%dH" % count, data, o))


def emit(name, vals, out):
    out.write("const unsigned short %s[%d] = {\n" % (name, len(vals)))
    for i in range(0, len(vals), 12):
        out.write("    " + " ".join("%5d," % v for v in vals[i:i+12]) + "\n")
    out.write("};\n\n")


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    binpath = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        root, "extracted/live/SMHangul/SMHangul.app/SMHangul")
    outpath = sys.argv[2] if len(sys.argv) > 2 else os.path.join(root, "data/automata_tables.m")
    os.makedirs(os.path.dirname(outpath), exist_ok=True)

    with open(binpath, "rb") as f:
        data = f.read()
    vm2off = macho_vm2off(data)

    with open(outpath, "w") as out:
        out.write("/* automata_tables.m — 정본 SMHangul 에서 추출(빌드 생성물, 커밋 금지).\n"
                  " * 생성: tools/extract_tables.py. 벤더 데이터 — 재배포 라이선스 검토 선행. */\n\n")
        for name, vaddr, cnt in TABLES:
            emit(name, rd_ushorts(data, vm2off, vaddr, cnt), out)

        # KS 매핑: 행배열 포인터를 따라 flat map_codes[] + map_cnt[32] 생성
        map_cnt = rd_ushorts(data, vm2off, MAP_CNT, 32)
        idx_off = vm2off(MAP_IDX)
        ptrs = list(struct.unpack_from("<32I", data, idx_off))
        flat = []
        for row in range(32):
            n = map_cnt[row]
            if n:
                flat.extend(rd_ushorts(data, vm2off, ptrs[row], n))
        emit("map_cnt", map_cnt, out)
        emit("map_codes", flat, out)
        out.write("/* map_codes total = %d (KS X 1001 완성형 순번) */\n" % len(flat))

    print("wrote %s (%d tables + map_codes[%d])" % (outpath, len(TABLES), len(flat)))


if __name__ == "__main__":
    main()
