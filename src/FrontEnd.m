/*
 * FrontEnd.m — 한글 조합 엔진/컨트롤러 (복원, 진행중)
 *
 * Dispatcher(입력서버 델리게이트)가 넘긴 키를 Automata 로 조합하고, 조합중
 * (marked)/확정 문자열을 만들며 KS↔Unicode 변환을 수행한다. 각 메서드는 IDA
 * 디컴파일 대조 후 clean 재작성([OK]) / 미복원([TODO], 주소 명기).
 *
 * 출력 경로: imProcessEvent: → [myAutomata korean:] → makeReplaceString:(ret_flag)
 * + makeReplaceString:(rest_flag) → 코드를 unicodeFromKS:/unfinishedUnicode: 로
 * Unicode 변환해 completeChar[](확정)·astring[](조합중)에 채움 → displayFEP.
 *
 * 대형 변환표는 정본 추출 리소스(data/, extract_tables.py). 소스 무내장.
 */
#import "FrontEnd.h"
#import "Automata.h"
#import "NoCheckAutomata.h"

/* KS(완성형 EUC)→"FullKorean" 글리프코드 표. 원본 주소산술은 0x20d0 + 2*code
 * (stru_20D0.segname = +8, [2*code-8]); 실데이터 ks@0x12358 = 가상인덱스 0x8144.
 * 재구성: 추출 ks[] 를 ks[code - KS_INDEX_BASE] 로 인덱싱(실측 확정 0x8144 —
 * 0xB0A1→0xCEFC 로 원본과 일치). 메서드명은 "unicode"지만 실제 산출은 벤더의
 * FullKorean 글리프 인코딩(FullKorean.glyphgenerator·한글 폰트가 렌더). */
#define KS_INDEX_BASE 0x8144
extern const unsigned short ks[];                      /* KS→FullKorean */
extern const unsigned short Uni_to_FullKorean_Table[]; /* FullKorean 역방향, 64K */

@implementation FrontEnd

/*
 * [OK] 키 1개 처리 — 조합 파이프라인 진입(Dispatcher가 호출).
 * 처리 전 현재 조합중 코드를 save_unfn 에 백업(교체 문자열 계산용).
 */
- imProcessEvent:(unsigned short)code
{
    save_unfn  = [myAutomata unfn_code];
    astring[0] = 0;
    if ([myAutomata korean:code]) {
        [self makeReplaceString:[myAutomata returnFlag]];  /* 현재(조합중/완성) */
        [self makeReplaceString:[myAutomata restFlag]];    /* 직전 잔여 확정 */
        working = 1;
        if (!inLineMode)
            [self displayFEP];
    }
    return self;
}

/*
 * [OK] 자동자 출력 코드를 Unicode로 변환해 확정/조합중 버퍼에 반영.
 *   flag==2: (ret) 필요 시 직전 잔여(save_unfn) 확정 + 현재 조합중(unfn_code)→astring
 *   flag==3: (rest) 완성 코드(comp_code) 확정
 * 범위판정 (code+0x5B5F)>0x5D 로 완성 EUC코드(→unicodeFromKS:)와 미완성 자모
 * (→unfinishedUnicode:)를 구분(디컴파일 상수 충실 보존).
 */
- makeReplaceString:(int)flag
{
    unsigned short c, u;

    if (flag == 2) {
        if ([myAutomata isFinishAndRest]) {
            c = ((unsigned short)(save_unfn + 0x5B5F) > 0x5D)
                ? [self unicodeFromKS:save_unfn]
                : [self unfinishedUnicode:save_unfn];
            /* [FIX] completeChar[32] 경계 가드: 공백 없이 32+ 음절 연타 시 버퍼
             * 오버플로(인접 ivar 손상/크래시)를 막는다. 극단적 경우만 해당. */
            if (c && completeIndex < 31) {
                completeChar[completeIndex++] = c;
                completeChar[completeIndex]   = 0;
                ++charSize;
            }
        }
        c = [myAutomata unfn_code];
        if (c) {
            u = ((unsigned short)(c + 0x5B5F) > 0x5D)
                ? [self unicodeFromKS:c]
                : [self unfinishedUnicode:c];
            if (u) { astring[0] = u; astring[1] = 0; }
        }
    } else if (flag == 3) {
        c = [myAutomata comp_code];
        u = ((unsigned short)(c + 0x5B5F) > 0x5D)
            ? [self unicodeFromKS:c]
            : [self unfinishedUnicode:c];
        if (u && completeIndex < 31) {          /* [FIX] 경계 가드(위 참조) */
            completeChar[completeIndex++] = u;
            completeChar[completeIndex]   = 0;
            ++charSize;
        }
    }
    return self;
}

/* [OK] KS(완성형 EUC)→Unicode: ks 표 룩업. */
- (unsigned short)unicodeFromKS:(unsigned short)code
{
    return ks[code - KS_INDEX_BASE];
}

/* [OK] 조합중 자모 코드→Unicode: 단순 오프셋. */
- (unsigned short)unfinishedUnicode:(unsigned short)code
{
    return code - 0x7370;
}

/* [OK] Unicode→KS(FullKorean): 표 룩업. */
- (unsigned short)ksFromUnicode:(unsigned short)uni
{
    return Uni_to_FullKorean_Table[uni];
}

/* [FIX+ENHANCE] 오토마타 생성·주입. Korean-ON(mode=1) 시 자판(keyboardLayout)에 따라:
 *   0=두벌식 → Automata(2벌 검사 조합: 복모음/복종성/받침이월/연속자음/백스페이스),
 *   1=세벌390 / 2=세벌최종 → NoCheckAutomata + setLayout:(위치고정 3벌, 이월 없음).
 * (이전엔 mode=1→항상 Automata 로 교정했었다. 이제 자판별로 분기.)
 * mode=0(영문/off)은 조합에 관여 안 하므로 NoCheckAutomata 로 두어도 무해. */
- (void)setAutomata:(int)mode
{
    [myAutomata release];              /* [FIX codex#3] 이전 오토마타 해제(교체 누수 방지) */
    myAutomata = nil;
    if (mode && keyboardLayout == 0) {
        myAutomata = [[Automata allocWithZone:[self zone]] init];
        [myAutomata automata_init];
    } else if (mode) {
        NoCheckAutomata *nc = [[NoCheckAutomata allocWithZone:[self zone]] init];
        [nc setLayout:keyboardLayout];      /* setLayout 후 init(layout 참조) */
        [nc automata_init];
        myAutomata = nc;
    } else {
        myAutomata = [[NoCheckAutomata allocWithZone:[self zone]] init];
        [myAutomata automata_init];
    }
}

/* [ENHANCE] 자판 선택 저장(0/1/2). 실제 오토마타 교체는 다음 setAutomata: 에서
 * 반영(Dispatcher 가 조합 경계에서 재적용). */
- (void)setKeyboardLayout:(int)l    /* [FIX codex#5] 0..2 로 클램프(불량값→두벌) */
{
    keyboardLayout = (l >= 0 && l <= 2) ? l : 0;
}
- (int)keyboardLayout           { return keyboardLayout; }

/* [OK] inputUnit 설정. */
- (void)setInputUnit:(int)unit
{
    inputUnit = unit;
}

/* [ENHANCE] 현재 자판에서 이 키가 자모인지(라우팅용) — 활성 automaton 에 위임. */
- (BOOL)isJamoKey:(unsigned short)c
{
    return [myAutomata isJamoKey:c];
}

/* [OK] 조합 세션 종료 시 상태·버퍼 전체 리셋. */
- (void)setWorkingInit
{
    if (working) {
        working = 0;
        [myAutomata automata_init];
        astring[0]     = 0;
        afterString[0] = 0;
        completeChar[0] = 0;
        charSize      = 0;
        completeIndex = 0;
        [self clearCvtField];
    }
}

/* [OK] 조합중 문자를 확정 버퍼에 커밋하고 오토마타 리셋. */
- makeInputNonAutomata
{
    unsigned short c, u;
    c = [myAutomata unfn_code];
    if (c) {
        u = ((unsigned short)(c + 0x5B5F) > 0x5D)
            ? [self unicodeFromKS:c]
            : [self unfinishedUnicode:c];
        if (u && completeIndex < 31) {          /* [FIX] 경계 가드(completeChar[32]) */
            completeChar[completeIndex++] = u;
            completeChar[completeIndex]   = 0;
            ++charSize;
        }
    }
    [myAutomata automata_init];
    return self;
}

/*
 * [FIX] 백스페이스. backCount 는 백업 링의 "최고 저장 인덱스"(개수 아님):
 *   >0  → 조합중 2+ 자모: reduceCount 로 한 자모 pop, 이전 상태를 astring 에 복원.
 *   ==0 → 조합중 단독 자모(초성/모음 하나): automata_init 로 제거 → 조합 비움.
 *         (원래는 이 상태에서 조합을 안 지워, 지운 뒤 다음 모음에 초성이 되살아나는
 *          유령 자음 버그가 있었다. 예: ㄱ→BS→ㅏ 하면 "가".)
 *   <0  → 조합중 아님: 확정 문자 1개 삭제(없으면 0 반환 → 클라이언트가 삭제).
 * 원래 코드는 backCount==1(=2자모, 예 "가")에서 곧장 automata_init 해 초성 상태를
 * 건너뛰고, 단독 초성(==0)에선 조합을 안 지웠다(유령 자음). 아래는 이를 교정.
 */
- (int)imProcessBS
{
    unsigned short c, u;
    astring[0] = 0;
    if ([myAutomata backCount] > 0) {
        c = [myAutomata reduceCount];
        u = ((unsigned short)(c + 0x5B5F) > 0x5D)
            ? [self unicodeFromKS:c]
            : [self unfinishedUnicode:c];
        astring[0] = u;
        astring[1] = 0;
    } else if ([myAutomata backCount] == 0) {
        [myAutomata automata_init];       /* 단독 자모 제거 → 조합 비움(유령 자음 방지) */
    } else {
        if (charSize <= 0)
            return 0;                     /* 조합 없음 — 클라이언트가 삭제 */
        [self makeInputNonAutomata];
        --completeIndex;
        completeChar[completeIndex] = 0;
        --charSize;
    }
    return 1;
}

/* [INFER] 단순 상태 게터 — 본문 대조 예정. */
- (char)isWorking    { return working; }
- (char)isInlineMode { return inLineMode; }

/* [OK] 확정+조합중 문자열을 NSString 으로 조립(표시/커밋용). */
- inputString
{
    id s = [NSString stringWithCharacters:completeChar length:charSize];
    if (astring[0]) {
        id a = [NSString stringWithCharacters:astring length:1];
        if (![s length])
            return a;
        return [s stringByAppendingString:a];
    }
    return s;
}

/*
 * [ENHANCE] Input Unit=Character 지원. completeChar 는 오토마타가 이미 확정한
 * 음절들(다음 음절 시작 시 makeReplaceString 가 채움) — 종성 이월/재조합 위험이
 * 없어 즉시 커밋해도 안전하다. astring 은 조합중(미확정)이라 커밋 금지.
 */
- (id)finalizedString      /* 확정 음절들(completeChar) */
{
    if (charSize <= 0)
        return @"";
    return [NSString stringWithCharacters:completeChar length:charSize];
}
- (id)composingString      /* 조합중 음절(astring) */
{
    if (!astring[0])
        return @"";
    return [NSString stringWithCharacters:astring length:1];
}
- (void)drainFinalized     /* 확정분을 문서에 커밋한 뒤 버퍼만 비움(조합/오토마타 보존) */
{
    completeChar[0] = 0;
    charSize        = 0;
    completeIndex   = 0;
}

/* [FIX] 확정분(completeChar)이 전부 한글 호환자모(U+3130~U+318F, 완성 안 된 단독
 * 자모)인지. 연속 자음("ㅋㅋㅋ") 등은 음절을 못 이뤄 단독 자모가 marked 에 누적되는데,
 * 이를 여러 개 marked 로 두면 클라이언트가 멈추는 원본 버그가 있어, 이 경우 즉시
 * 커밋하도록 판별에 쓴다. 완성 음절(U+AC00~)은 NO 라 Word 누적 동작 유지. */
- (BOOL)finalizedIsJamo
{
    int i;
    if (charSize <= 0)
        return NO;
    for (i = 0; i < charSize; i++) {
        unsigned short u = completeChar[i];
        if (u < 0x3130 || u > 0x318F)
            return NO;
    }
    return YES;
}

/* [OK] 조합중 문자열을 표시 필드에 반영(비인라인). */
- (void)displayFEP
{
    [cvtField setStringValue:[self inputString]];
}

/* [OK] 표시 필드 비우기(비인라인). */
- (void)clearCvtField
{
    if (!inLineMode)
        [cvtField setStringValue:@""];
}

/*
 * [OK] 조합 패널 지연 생성(nib 로드) 후 앞으로. cvtWin 이 없으면 nib 로드 →
 * 플로팅/키전용 설정. (그래서 "LazyPanel".)
 * NOTE: nib명(off_5E00C, frontEnd 추정), setFloatingPanel:/키설정 셀렉터
 * (591BD/591C1), 실패 경고 문자열은 최종 확인.
 */
- (void)orderFrontFEP
{
    if (!cvtWin) {
        if (![NSBundle loadNibNamed:@"frontEnd" owner:self])
            NSRunAlertPanel(@"SMHangul", @"cannot load frontEnd nib", nil, nil, nil);
        [cvtWin setFloatingPanel:YES];         /* NOTE: 591BD */
        [cvtWin setBecomesKeyOnlyIfNeeded:YES];/* NOTE: 591C1 */
    }
    [cvtWin orderFront:self];
}

/* [OK] 조합 패널 숨김. */
- (void)orderOutFEP
{
    [cvtWin orderOut:self];
}

/* [OK] 인라인/비인라인 모드 토글. 인라인이면 조합창 숨김, 아니면 표시. */
- (void)changeInputMode
{
    inLineMode = inLineMode ? 0 : 1;
    if (inLineMode)
        [self orderOutFEP];
    else
        [self orderFrontFEP];
}

/* [OK] 현재 확정 문자 수. */
- (int)currentPos { return charSize; }

/* [OK] 입력기는 버퍼내 커서 이동을 구현하지 않는다(클라이언트 담당) — 빈 스텁. */
- (void)cursorMoveLeft { }

/*
 * [OK] 표시 NSString → EUC-KR(KS) 바이트열(malloc). 비ASCII 문자는
 * Uni_to_FullKorean_Table 로 KS 2바이트, ASCII 는 1바이트. *len 에 바이트 수.
 * NOTE: 58E56(문자열 인코딩 판정 >2 = 멀티바이트) 셀렉터 확인.
 */
- (char *)convertedToKSString:(id)s length:(int *)len
{
    int n, i, out = 0;
    char *buf;
    unsigned short c;
    short v;

    if (!s || ![s length])
        return (char *)0;
    n = [s length];
    if ((unsigned)[s smallestEncoding] > 2) {     /* NOTE: 58E56 — 멀티바이트 */
        buf = (char *)malloc(2 * n + 1);
        for (i = 0; i < n; i++) {
            c = [s characterAtIndex:i];
            if (c > 0x7F) {
                v = Uni_to_FullKorean_Table[c];
                buf[out++] = (char)(v >> 8);       /* HIBYTE */
            } else {
                v = c % 0xFF;
            }
            buf[out++] = (char)v;
        }
        buf[out] = 0;
        *len = out;
    } else {
        buf = (char *)malloc(n + 1);
        strcpy(buf, [s cString]);
        buf[n] = 0;
        *len = n;
    }
    return buf;
}

/* [OK] KS 인코딩 NSString 반환. ASCII(<=2)면 그대로, 아니면 바이트변환 후 재생성. */
- ksString:s
{
    id v3, v4;
    char *b;
    int len;
    if ((unsigned)[s smallestEncoding] <= 2)
        return s;
    b  = [self convertedToKSString:s length:&len];
    v3 = b;                                        /* (사용 안 함, 대칭용) */
    v4 = [NSString stringWithCString:b];
    free(b);
    (void)v3;
    return v4;
}

/*
 * [OK] KS(EUC) 바이트열 NSString → FullKorean NSString. 고바이트(>0x80)면 다음
 * 바이트와 합쳐 2바이트 EUC 코드로, 완성형 범위면 ks표(unicodeFromKS:)로 변환.
 * ksString:/convertedToKSString: 의 역방향. NOTE: 58FEA(인코딩>3)·58FA6(바이트길이)·
 * 58FBA(바이트 접근) 셀렉터 확인.
 */
- unicodeString:s
{
    int i, n;
    unsigned short c;
    id out;

    if ((unsigned)[s smallestEncoding] > 3)      /* 이미 유니코드 */
        return s;
    n   = [s cStringLength];
    out = [NSMutableString stringWithCapacity:n];
    for (i = 0; i < n; i++) {
        c = [s characterAtIndex:i];
        if (c > 0x80)                            /* EUC 고바이트 → 2바이트 조립 */
            c = (c << 8) | [s characterAtIndex:++i];
        if ((unsigned short)(c + 0x7EBF) <= 0x7CBD)  /* 완성형 한글 범위 */
            c = [self unicodeFromKS:c];          /* ks표(stru_20D0[2c-8]) */
        [out appendString:[NSString stringWithCharacters:&c length:1]];
    }
    return out;
}

/* [OK] 한자 문자열을 확정 버퍼(completeChar/charSize)에 적재하고 잔여 버퍼 비움. */
- hanjaProc:hanja
{
    int i, n;
    if (!hanja)
        return self;
    n = [hanja length];
    if (n) {
        charSize = n;
        for (i = 0; i < n; i++)
            completeChar[i] = [hanja characterAtIndex:i];
        completeChar[n] = 0;
        afterString[0] = 0;
        astring[0]     = 0;
    }
    return self;
}

/* [OK] 생성자: super init → 인라인 모드 기본 → 초기화 헬퍼 → Automata(2벌식) 주입.
 * NOTE: 59897(무인자 초기화 헬퍼) 셀렉터 확인. */
- initWithHanja:(char)hanja
{
    [super init];
    inLineMode = 1;
    /* [self <59897>]; */                        /* NOTE: 초기화 헬퍼 */
    [self setAutomata:0];
    return self;
}

/* [OK] 언어 on/off 시 조합창 표시/숨김 관리. NOTE: 59002(on 시 갱신 호출) 확인. */
- (void)changedLanguage:(char)flag
{
    if (flag) {
        /* [self <59002>]; */                    /* NOTE: 갱신/리셋 */
        if (!inLineMode)
            [self orderFrontFEP];
    } else if (inLineMode) {
        [self orderOutFEP];
    }
}

/* [OK] 커서 뒤 문자열 길이 — 미추적(스텁 0). */
- (int)afterStringLength { return 0; }

/* [INFER] 버퍼내 커서 우이동 — cursorMoveLeft 와 대칭 빈 스텁(클라이언트 담당). */
- (void)cursorMoveRight { }

/* [OK] 오토마타 해제 후 상위 dealloc. */
- (void)dealloc
{
    [myAutomata release];
    [super dealloc];
}

@end
