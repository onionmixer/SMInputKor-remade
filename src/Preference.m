/*
 * Preference.m — 환경설정 (복원)
 *
 * 입력 단위/초기 모드/한자 영역·반복/인라인·색상, 한자 사전 경로(외부 파일),
 * 그리고 설치된 입력기의 자판 바인딩을 읽어 팝업 UI 에 반영한다. 각 메서드는
 * IDA 디컴파일 대조([OK]) / 셀렉터 추정([INFER]).
 *
 * 정본 문자열 실측(NSConstantString → C문자열):
 *   NSUserDefaults 키: SMInitState, SMHanjaArea, SMInputUnit, SMHanjaRepeatCount,
 *     SMHanjaConversion, NSMarkedTextAttribute, NSMarkedTextColor.
 *   SMInputManager.pref 키: SMHanjaDictionaryPath, SMHanjaDictioanry(원본 오타),
 *     SMHanjaDictionary.
 *   값 상수: English/Korean, None/Underline, Character/Word, Background/Underline.
 *   자판키: "$ "(toggleConversionMode:), "^ "(inputModeChange:), "~ "(hanjaConvert:),
 *     " "(enteredSpace:), "^$ ". 사전 확장자 "dic".
 *
 * ※ 자판사전(SMHangul.dict)은 정본이 **keystroke→action** 방향이다(원본 13항목).
 *   재구성 초기엔 로드가 2항목만 담고 저장이 action→keystroke 로 뒤집어 3개만 써서,
 *   Set 저장 즉시 한/영 전환·공백·백스페이스 바인딩이 파괴됐다
 *   (doc/KEYBOARD_LAYOUT_PLAN.md §19). 지금은 dict
 *   전체를 보존하고 편집 대상 3종만 keystroke 키로 갱신하며, 손상된 dict 는
 *   repairKeyBindings 가 로드 시 자동 교정한다(멱등).
 */
#import "Preference.h"

/* 인라인 조합 기본 배경색(원본 __data 전역 _defaultbackground@0x42354).
 * init 에서 (1.0, 221/255, 85/255, 1.0) 크림/골드색으로 생성(정본 float 실측,
 * Kanji 예제 IMPreferences 의 _defaultbackground 와 동일 RGB). */
id defaultbackground = nil;

/* 팝업 선택 인덱스 → 자판키 문자열 (원본 _keyDict@0x42358, C 문자열 배열).
 * 인덱스: 0="^$ ", 1="~ ", 2="$ ", 3="^ ", 4=" ", 5="". indexWithKey: 의 역방향. */
static const char * const keyDict[] = { "^$ ", "~ ", "$ ", "^ ", " ", "" };

@implementation Preference

/*
 * [OK] 생성자(0x72c4): super init → Preference.nib 로드(owner=self) →
 * _imMap/_imArray 생성, panel 플로팅 설정, 기본 배경색 생성 → loadInputManagerInfo.
 * nib 실패 시 로그+nil.
 */
- init
{
    [super init];
    if (![NSBundle loadNibNamed:@"Preference" owner:self]) {
        NSLog(@"Cannot load Preferences NIB file.");
        return nil;
    }
    _imMap   = [[NSMutableDictionary alloc] init];
    _imArray = [[NSMutableArray alloc] init];
    [panel setFloatingPanel:YES];
    /* [ENHANCE] 타이틀바 닫기 상자 사용(Preference.nib styleMask 를 Titled|Closable=3
     * 으로 패치). 닫기 상자는 performClose:→close 이므로, 패널을 재사용(showPreference:
     * 재표시)하려면 닫을 때 해제되지 않게 한다. */
    [panel setReleasedWhenClosed:NO];
    defaultbackground =
        [[NSColor colorWithCalibratedRed:1.0
                                   green:(221.0 / 255.0)
                                    blue:(85.0 / 255.0)
                                   alpha:1.0] retain];
    [self buildKeyboardTypeUI];        /* [ENHANCE] 자판 라디오(nib 미배치 시 코드로) */
    [self loadInputManagerInfo];
    return self;
}

/*
 * [ENHANCE] 자판 선택 라디오 매트릭스를 코드로 구성(headless — nib 바이너리 무편집).
 * keyboardType 아웃렛이 이미 있으면(추후 IB 배치) 생략해 공존. 하단 액션버튼 행
 * 바로 위에 2줄(캡션+라디오) 공간을 여는 방식:
 *   1) 패널을 H(=셀높이+28) 만큼 키움(하단 앵커 → 상단에 여백 생성),
 *   2) 버튼 행보다 위의 서브뷰(박스들)만 H 만큼 위로 이동 → 버튼 위에 틈 생성,
 *   3) 그 틈에 "Keyboard Layout:" 캡션(윗줄) + [2-set | 3-set 390 | 3-set final]
 *      1×3 전폭 라디오(아랫줄) 배치.
 * 하단 버튼 행 탐지는 **클래스 무관 최소 y** 기준 — 실측상 Set.../Cancel 은 NSButton
 * 이 아니라 NSMatrix 라서 클래스로 찾으면 실패한다(실기 뷰 덤프로 확인).
 * 라디오 셀·캡션 폰트는 패널의 기존 라디오(initState) 셀을 복제/상속해 창 안의 다른
 * 컨트롤과 서체·크기를 일치시킨다. 값은 selectedColumn(0/1/2).
 */
- (void)buildKeyboardTypeUI
{
    NSView       *cv;
    NSArray      *subs;
    NSRect        cvf;
    NSMatrix     *m;
    id            proto, tmpl;
    float         H, W, rowTop, rowBot, rowY, cellH;
    int           i, n;
    BOOL          haveRow;

    if (keyboardType || !panel)
        return;
    cv   = [panel contentView];
    cvf  = [cv frame];
    W    = cvf.size.width;
    subs = [cv subviews];
    n    = [subs count];
    tmpl  = initState ? initState : (hanjaArea ? hanjaArea : inputUnit);
    cellH = tmpl ? [tmpl cellSize].height : 18.0;
    H     = cellH + 28.0;              /* 라디오 1줄 + 캡션 1줄 + 여백 */

    /* (a) 하단 행(=최하단 y) 찾기 — 클래스 무관. 실측상 Set.../Cancel 버튼은
     *     NSButton 이 아니라 NSMatrix 라서, y 최소값으로 행을 잡아야 한다.
     *     같은 행(y<=minY+5) 서브뷰들의 top 최대값 = 행 상단(rowTop). */
    haveRow = NO;
    rowBot  = 0.0;
    for (i = 0; i < n; i++) {
        float y = [[subs objectAtIndex:i] frame].origin.y;
        if (!haveRow || y < rowBot) { rowBot = y; haveRow = YES; }
    }
    rowTop = 0.0;
    if (haveRow) {
        for (i = 0; i < n; i++) {
            NSRect f = [[subs objectAtIndex:i] frame];
            if (f.origin.y <= rowBot + 5.0) {              /* 같은 하단 행 */
                float t = f.origin.y + f.size.height;
                if (t > rowTop) rowTop = t;
            }
        }
    }

    /* (b) 패널 성장 + 버튼 행보다 위의 서브뷰만 H 위로 이동(틈 열기). */
    [cv setAutoresizesSubviews:NO];
    [panel setContentSize:NSMakeSize(W, cvf.size.height + H)];
    if (haveRow) {
        for (i = 0; i < n; i++) {
            id v = [subs objectAtIndex:i];
            NSRect f = [v frame];
            if (f.origin.y >= rowTop - 1.0) {              /* 버튼 위쪽 = 이동 */
                f.origin.y += H;
                [v setFrame:f];
            }
        }
        rowY = rowTop;                                     /* 틈 하단 = 버튼 행 위 */
    } else {
        rowY = cvf.size.height;                            /* 폴백: 상단 스트립 */
    }

    /* (c) 2줄 배치: 아랫줄 = 3개 라디오(전폭, 버튼 위), 윗줄 = 캡션 "Keyboard Layout:".
     *     라디오 셀은 패널의 실제 작동 라디오(initState) 셀을 복제해 렌더링(폰트/이미지
     *     위치/높이)을 일치시킨다. 캡션은 폭 제약상 라디오 위 별도 줄에 둔다. */
    if (tmpl) {
        proto = [[tmpl cellAtRow:0 column:0] copy];   /* 작동 라디오 셀 복제 */
        [proto setTitle:@""];
        [proto setTarget:nil];                         /* 원 셀 액션 제거(오발동 방지) */
        [proto setAction:(SEL)0];
    } else {
        proto = [[NSButtonCell alloc] initTextCell:@""];
        [proto setButtonType:NSRadioButton];
        [proto setBordered:NO];
        [proto setImagePosition:NSImageLeft];
    }
    m = [[NSMatrix alloc]
            initWithFrame:NSMakeRect(8.0, rowY + 5.0, W - 16.0, cellH)
                     mode:NSRadioModeMatrix
                prototype:proto
             numberOfRows:1
          numberOfColumns:3];
    [proto release];
    [m setCellSize:NSMakeSize((W - 16.0) / 3.0, cellH)];
    [m setIntercellSpacing:NSMakeSize(0.0, 0.0)];
    [[m cellAtRow:0 column:0] setTitle:@"2-set"];
    [[m cellAtRow:0 column:1] setTitle:@"3-set 390"];
    [[m cellAtRow:0 column:2] setTitle:@"3-set final"];
    [m selectCellAtRow:0 column:0];
    [m setTarget:self];
    [m setAction:@selector(changeKeyboardType:)];
    [cv addSubview:m];                 /* superview 가 retain */
    keyboardType = m;                  /* 아웃렛(비retain 관례)으로 보관 */
    [m release];                       /* [FIX codex#4] 생성 소유권 해제(누수 방지) */

    /* 캡션 — 라디오 윗줄 */
    {
        id label = [[NSTextField alloc]
                       initWithFrame:NSMakeRect(8.0, rowY + 5.0 + cellH + 2.0,
                                                W - 16.0, 15.0)];
        [label setStringValue:@"Keyboard Layout:"];
        [label setEditable:NO];  [label setSelectable:NO];
        [label setBordered:NO];  [label setBezeled:NO];
        [label setDrawsBackground:NO];
        /* [FIX] 폰트를 패널의 기존 컨트롤과 일치시킨다(systemFontOfSize:11 강제 시
         * 창 안 다른 텍스트와 서체/크기가 달라 보였음). 라디오 셀(=nib 원본 폰트)의
         * 폰트를 그대로 쓰고, 없으면 라벨 기본값을 유지. */
        if (tmpl) {
            id f = [[tmpl cellAtRow:0 column:0] font];
            if (f) [label setFont:f];
        }
        [cv addSubview:label];
        [label release];
    }
}

/*
 * [FIX] 손상된 자판사전 자동 교정 — 기존 dict 를 그대로 쓰되 안전하게.
 * 과거 재구성 버그(저장 시 action→keystroke 로 반전 + 나머지 바인딩 소실)로
 * 사용자 홈에 뒤집힌 dict 가 남아 한/영 전환·공백·백스페이스가 죽는다. 사용자가
 * 수동 복구할 필요 없이 로드 시 감지해 되돌린다:
 *   (1) 반전 항목(키가 "…:" 로 끝나는 셀렉터 모양) → 뒤집어 정본 방향으로 복원,
 *   (2) 필수 편집 바인딩(공백/엔터/백스페이스/화살표)이 없으면 정본값 보충.
 * 정상 dict 면 아무것도 바꾸지 않는다(멱등).
 */
- (void)repairKeyBindings
{
    /* 정본 필수 바인딩(keystroke→action). 편집키가 없으면 입력 자체가 불구가 된다. */
    static const char * const need[][2] = {
        { " ",      "enteredSpace:"   },
        { "\015",   "insertNewline:"  },
        { "\012",   "insertNewline:"  },
        { "\003",   "insertNewline:"  },
        { "\010",   "deleteBackward:" },
        { "\177",   "deleteBackward:" },
        { 0, 0 }
    };
    /* 화살표(정본 "\\UF700".."\\UF703")는 비ASCII라 unichar 로 구성한다.
     * C 소스에 \\U 이스케이프를 쓸 수 없고, UTF-8 바이트를 stringWithCString:
     * 으로 넣으면 3글자가 되어 바인딩이 어긋난다. */
    static const unsigned short arrowKey[4] = { 0xF700, 0xF701, 0xF702, 0xF703 };
    static const char * const arrowAct[4] =
        { "moveUp:", "moveDown:", "moveLeft:", "moveRight:" };
    id  keys, k, val;
    int i, n;

    /* (1) 반전 항목 복구: 키가 셀렉터(":"로 끝남)면 key/value 를 맞바꾼다. */
    keys = [_imMap allKeys];
    n = [keys count];
    for (i = 0; i < n; i++) {
        k = [keys objectAtIndex:i];
        if ([k length] > 1 && [k hasSuffix:@":"]) {
            val = [_imMap objectForKey:k];
            [_imMap removeObjectForKey:k];
            if ([val length])
                [_imMap setObject:k forKey:val];   /* keystroke=val, action=k */
        }
    }

    /* (2) 필수 편집 바인딩 보충(이미 있으면 건드리지 않음). */
    for (i = 0; need[i][0]; i++) {
        id key = [NSString stringWithCString:need[i][0]];
        if (![_imMap objectForKey:key])
            [_imMap setObject:[NSString stringWithCString:need[i][1]] forKey:key];
    }
    for (i = 0; i < 4; i++) {
        unichar u = (unichar)arrowKey[i];
        id key = [NSString stringWithCharacters:&u length:1];
        if (![_imMap objectForKey:key])
            [_imMap setObject:[NSString stringWithCString:arrowAct[i]] forKey:key];
    }
}

/*
 * [FIX] 자판사전(_imMap, keystroke→action)에서 한 액션의 바인딩을 새 키스트로크로
 * 옮긴다. 같은 액션에 걸린 기존 keystroke 항목을 모두 제거한 뒤 새 키를 등록 —
 * 그래야 방향(keystroke 가 키)이 정본과 일치하고 옛 바인딩이 남아 중복되지 않는다.
 * key 가 빈 문자열이면(팝업 "없음") 바인딩 제거만 한다.
 */
- (void)rebindAction:(NSString *)action toKey:(const char *)key
{
    id  keys = [_imMap allKeys];        /* 순회 중 변경 방지용 스냅샷 */
    int i, n = [keys count];
    id  k;

    for (i = 0; i < n; i++) {
        k = [keys objectAtIndex:i];
        if ([[_imMap objectForKey:k] isEqualToString:action])
            [_imMap removeObjectForKey:k];
    }
    if (key && *key) {
        id newKey = [NSString stringWithCString:key];
        /* [FIX] 편집키 보호: 그 키가 이미 편집 액션(공백/백스페이스/엔터/화살표)에
         * 묶여 있으면 덮어쓰지 않는다. 덮어쓰면 공백·백스페이스가 통째로 죽어
         * 입력 자체가 불구가 된다(codex 충돌 지적 검증 중 확인). 팝업끼리의 충돌은
         * 사용자의 명시적 선택이므로 나중 선택 우선(원래 동작 유지). */
        id cur = [_imMap objectForKey:newKey];
        if (cur && ![cur isEqualToString:action] && [self isEditingAction:cur])
            return;                       /* 편집키 유지 — 재바인딩 취소 */
        [_imMap setObject:action forKey:newKey];
    }
}

/* [FIX] 보호 대상 편집 액션인지(자판 팝업으로 재할당 못 하게). */
- (BOOL)isEditingAction:(NSString *)a
{
    return [a isEqualToString:@"enteredSpace:"]  ||
           [a isEqualToString:@"deleteBackward:"] ||
           [a isEqualToString:@"insertNewline:"]  ||
           [a isEqualToString:@"moveLeft:"]  || [a isEqualToString:@"moveRight:"] ||
           [a isEqualToString:@"moveUp:"]    || [a isEqualToString:@"moveDown:"];
}

/* [ENHANCE] 자판 라디오 액션 — 값은 writeDefaults: 시점에 읽으므로 여기선 무동작
 * (다른 라디오/팝업과 동일한 지연 적용). */
- (void)changeKeyboardType:sender
{
}

/* [OK] UI 갱신(loadInputManagerInfo) 후 패널을 앞으로(0x7410). 비모달. */
- (void)showUI
{
    [self loadInputManagerInfo];
    [panel orderFront:self];
}

/*
 * [OK] 자판키 문자열 → 팝업 인덱스(0~3)로 매핑(0x7c50). compare: 가 0(같음)이면
 * 해당 인덱스. "^$ "→0, "~ "→1, "$ "→2, "^ "→3, 미매칭 0.
 */
- (int)indexWithKey:key
{
    if (![key compare:@"^$ "]) return 0;
    if (![key compare:@"~ "])  return 1;
    if (![key compare:@"$ "])  return 2;
    if (![key compare:@"^ "])  return 3;
    return 0;
}

/*
 * [OK] 자판사전(dict)에서 key 의 액션 셀렉터 문자열을 읽어, 그 액션에 맞는 팝업
 * (영/한·한자·인라인)에 indexWithKey: 인덱스를 선택(0x7b50). compare: 사용.
 *   toggleConversionMode: → engKorSelectPopUp
 *   hanjaConvert:        → hanjaSelectPopUp
 *   inputModeChange:     → inlineWinSelectPopUp
 */
- (void)setPopUpWithKeyBindingDictionaray:dict andKey:key
{
    id action = [dict objectForKey:key];
    if (!action)
        return;
    if ([action compare:@"toggleConversionMode:"]) {          /* != toggle */
        if ([action compare:@"hanjaConvert:"]) {              /* != hanja */
            if (![action compare:@"inputModeChange:"])        /* == inputMode */
                [inlineWinSelectPopUp selectItemAtIndex:[self indexWithKey:key]];
        } else {                                              /* == hanja */
            [hanjaSelectPopUp selectItemAtIndex:[self indexWithKey:key]];
        }
    } else {                                                  /* == toggle */
        [engKorSelectPopUp selectItemAtIndex:[self indexWithKey:key]];
    }
}

/*
 * [FIX] 라디오 매트릭스에서 title 이 일치하는 셀을 선택(세로 2행 라디오 기준).
 * 원본 loadInputManagerInfo 는 selectCellAtRow:column: 로 행을 골랐으나 폴라리티가
 * 뒤집혀 있었다. title 기반이면 행 순서·폴라리티에 무관하게 올바로 선택된다.
 */
- (void)selectCell:matrix withTitle:title
{
    int r, n;
    if (!matrix || !title)
        return;
    n = [matrix numberOfRows];
    for (r = 0; r < n; r++) {
        id c = [matrix cellAtRow:r column:0];
        if ([[c title] isEqualToString:title]) {
            [matrix selectCellAtRow:r column:0];
            return;
        }
    }
}

/*
 * [OK] 설치된 입력기 자판사전 + NSUserDefaults 를 읽어 패널 컨트롤을 채운다(0x744c).
 *  1. ~/Library/KeyBindings/SMHangul.dict 우선, 없으면 /LocalLibrary·/NextLibrary
 *     밑의 KeyBindings/SMHangul.dict 스캔 → 자판 바인딩 팝업 반영.
 *  2. ~/Library/Dictionary/SMInputManager.pref 에서 한자 사전 경로/이름 반영.
 *  3. defaults 에서 초기모드/한자영역/입력단위/반복/변환/속성·색상 반영 후 panel display.
 * NOTE: 저장(writeToUserDefaults:)과 폴라리티가 어긋나는 지점은 원본 그대로 재현.
 */
- (void)loadInputManagerInfo
{
    id fm       = [NSFileManager defaultManager];
    id defaults = [NSUserDefaults standardUserDefaults];
    id kbDict   = nil;                 /* 로드한 SMHangul.dict */
    id prefDict = nil;                 /* 로드한 SMInputManager.pref */
    id attrVal, colorData, color = nil;
    id path, v;
    int i, cnt;
    BOOL isDir = NO;

    attrVal   = [defaults objectForKey:@"NSMarkedTextAttribute"];
    colorData = [defaults objectForKey:@"NSMarkedTextColor"];

    [_imArray removeAllObjects];
    [_imMap   removeAllObjects];

    /* 1) 자판사전 위치 결정 */
    path = [NSString stringWithFormat:@"%@%@",
              NSHomeDirectory(), @"/Library/KeyBindings/SMHangul.dict"];
    if ([fm fileExistsAtPath:path isDirectory:&isDir] && !isDir)
        kbDict = [NSDictionary dictionaryWithContentsOfFile:path];
    if (!kbDict) {
        /* [FIX] 홈 dict 가 없거나 **깨져서 파싱 실패**한 경우에도 시스템 dict 로
         * 폴백한다. 이전엔 홈 파일이 "존재"하기만 하면 폴백을 건너뛰어, 파싱 실패
         * 시 _imMap 이 빈 채로 남고 Set 저장이 3개짜리 반쪽 dict 를 써서 편집키가
         * 다시 통째로 날아갔다(codex 지적 검증됨). */
        id libs = [NSArray arrayWithObjects:@"/LocalLibrary", @"/NextLibrary", nil];
        cnt = [libs count];
        for (i = 0; i < cnt; i++) {
            id p = [[libs objectAtIndex:i]
                       stringByAppendingString:@"/KeyBindings/SMHangul.dict"];
            if ([fm fileExistsAtPath:p isDirectory:&isDir] && !isDir) {
                kbDict = [NSDictionary dictionaryWithContentsOfFile:p];
                if (kbDict)
                    break;
            }
        }
    }
    if (kbDict) {
        [self setPopUpWithKeyBindingDictionaray:kbDict andKey:@"$ "];
        [self setPopUpWithKeyBindingDictionaray:kbDict andKey:@"^$ "];
        [self setPopUpWithKeyBindingDictionaray:kbDict andKey:@"~ "];
        [self setPopUpWithKeyBindingDictionaray:kbDict andKey:@"^ "];
        /* [FIX] 자판사전 전체를 _imMap 에 보존(keystroke→action 방향 그대로).
         * 이전 재구성은 ""/" " 두 항목만 담고, 저장측은 action→keystroke 로 3개만
         * 써서 (a) 방향이 반전되고 (b) 나머지 바인딩(공백/엔터/백스페이스/화살표
         * 10종)이 통째로 소실 → Set 저장 후 한/영 전환·공백·백스페이스가 죽었다.
         * 정본 dict(extracted/live/SMHangul/KeyBindings/SMHangul.dict)는
         *   "$ " = "toggleConversionMode:"; ... "\010" = "deleteBackward:";
         * 처럼 keystroke 가 키다. 편집 대상 3종만 저장측에서 갱신한다. */
        [_imMap addEntriesFromDictionary:kbDict];
    }
    /* [FIX] dict 유무와 무관하게 항상 교정한다 — 손상(반전) 복구 + 필수 편집
     * 바인딩 보충. dict 가 전혀 없을 때도 Set 저장이 편집키 없는 반쪽 dict 를
     * 쓰지 않도록 보장(codex 지적 검증됨). 정상 dict 면 아무것도 안 바꾼다. */
    [self repairKeyBindings];

    /* 2) 한자 사전 pref */
    path = [NSString stringWithFormat:@"%@%@",
              NSHomeDirectory(), @"/Library/Dictionary/SMInputManager.pref"];
    if ([fm fileExistsAtPath:path isDirectory:&isDir] && !isDir)
        prefDict = [NSDictionary dictionaryWithContentsOfFile:path];
    if (prefDict) {
        [dictionaryPathTF setStringValue:[prefDict objectForKey:@"SMHanjaDictionaryPath"]];
        [self updateDictionaryPopUpButton:nil];
        for (i = 0; i < [dictionaryListPU numberOfItems]; i++) {
            id name  = [prefDict objectForKey:@"SMHanjaDictioanry"];  /* 원본 오타 키 */
            id title = [dictionaryListPU itemTitleAtIndex:i];
            if ([name isEqualToString:title]) {
                [dictionaryListPU selectItemAtIndex:i];
                break;
            }
        }
    }

    /* 3) 표시/상태 defaults
     * [FIX] 라디오 매트릭스 로드 — 저장된 title 과 일치하는 셀을 선택.
     * (원본/fork 는 setState: 를 썼으나 매트릭스엔 selectCellAtRow:column: 가 정본
     * 접근자. 저장측 title 저장과 대칭.) */
    v = [defaults objectForKey:@"SMInitState"];
    if (v) [self selectCell:initState withTitle:v];

    v = [defaults objectForKey:@"SMHanjaArea"];
    if (v) [self selectCell:hanjaArea withTitle:v];

    v = [defaults objectForKey:@"SMInputUnit"];
    if (v) [self selectCell:inputUnit withTitle:v];

    /* [ENHANCE] 자판(0=두벌 1=세벌390 2=세벌최종) — 1행×3열 가로 매트릭스: 열 인덱스.
     * [FIX codex#5] 열 인덱스 0..2 로 클램프(불량 defaults 값이 NSMatrix 범위 초과 방지). */
    v = [defaults objectForKey:@"SMKeyboardType"];
    if (v && keyboardType) {
        int col = [v intValue];
        if (col < 0 || col > 2) col = 0;
        [keyboardType selectCellAtRow:0 column:col];
    }

    v = [defaults objectForKey:@"SMHanjaRepeatCount"];
    if (v) [hanjaRepeatCount setIntValue:[v intValue]];

    v = [defaults objectForKey:@"SMHanjaConversion"];
    if (v) [hanjaConversion setIntValue:[v intValue]];

    if (colorData)
        color = [NSUnarchiver unarchiveObjectWithData:colorData];
    /* [FIX] 라운드트립 역전 교정. nib 팝업: 항목0="Selection"(저장값 "Background"),
     * 항목1="Undeline"(저장값 "Underline"). 저장측 idx0→"Background"/idx1→"Underline"
     * 과 대칭이 되도록 로드도 "Underline"→항목1, "Background"→항목0 으로. (원본은
     * "Underline"→항목0 이라 저장/로드가 매번 뒤집혔음.) 기본색도 각 속성에 맞춤. */
    if ([attrVal isEqualToString:@"Underline"]) {
        [attributePopUp selectItemAtIndex:1];       /* Underline = 항목1 */
        if (!color) color = [NSColor blackColor];   /* 밑줄 기본색 */
    } else {
        [attributePopUp selectItemAtIndex:0];       /* Background = 항목0 */
        if (!color) color = defaultbackground;      /* 배경 기본색(크림) */
    }
    [colorWell setColor:color];
    [panel display];
}

/*
 * [OK] 속성 팝업 변경 액션(0x7cf0). 선택 인덱스 1이면 시스템(선택) 색, 아니면 기본
 * 배경색을 colorWell 에 설정.
 */
- (void)changeAttributeType:sender
{
    if ([sender indexOfSelectedItem] == 1)
        [colorWell setColor:[NSColor selectedControlColor]];
    else
        [colorWell setColor:defaultbackground];
}

/* [OK] "취소/되돌리기"(0x7d58): 저장값으로 패널을 다시 로드. 패널을 닫지는 않는다. */
- (void)revertDefaults:sender
{
    [self loadInputManagerInfo];
}

/*
 * [OK] 패널 컨트롤 → (a) 자판사전 파일(~/Library/KeyBindings/SMHangul.dict),
 * (b) 한자 사전 pref 파일, (c) 전달된 defaults 사전(a3) 에 기록(0x7d78).
 * NOTE: 이 메서드는 패널을 닫지 않는다(원본도 동일 — OK 버튼은 적용만).
 */
- (void)writeToUserDefaults:(NSMutableDictionary *)defaults
{
    id kbfile = [[NSMutableDictionary alloc] init];   /* SMInputManager.pref 용 */
    id fm = [NSFileManager defaultManager];
    id base, dir, dictPath, prefPath, v, color;
    BOOL isDir = NO;
    int idx;

    /* (a) ~/Library/KeyBindings 디렉터리 보장 후 SMHangul.dict 경로 */
    base = [NSString stringWithString:NSHomeDirectory()];
    dir  = [base stringByAppendingString:@"/Library"];
    if (![fm fileExistsAtPath:dir isDirectory:&isDir])
        [fm createDirectoryAtPath:dir attributes:nil];
    if (!isDir)
        [fm createDirectoryAtPath:dir attributes:nil];
    dir = [dir stringByAppendingString:@"/KeyBindings"];
    if (![fm fileExistsAtPath:dir isDirectory:&isDir])
        [fm createDirectoryAtPath:dir attributes:nil];
    if (!isDir)
        [fm createDirectoryAtPath:dir attributes:nil];
    dictPath = [dir stringByAppendingString:@"/SMHangul.dict"];

    /* [FIX] 팝업 선택 → 자판키 → _imMap(**keystroke→action**, 정본 방향).
     * 이전 재구성은 action→keystroke 로 뒤집어 써서 저장 즉시 한/영 전환이 죽고
     * (조회는 keystroke 키로 함) 공백·엔터·백스페이스·화살표 바인딩까지 소실됐다.
     * 편집 대상 3종의 옛 keystroke 항목을 지우고 새 keystroke 로 재등록한다.
     * 나머지 바인딩은 loadInputManagerInfo 가 _imMap 에 보존해 둔 채 유지된다. */
    [self rebindAction:@"toggleConversionMode:" toKey:keyDict[[engKorSelectPopUp indexOfSelectedItem]]];
    [self rebindAction:@"inputModeChange:"      toKey:keyDict[[inlineWinSelectPopUp indexOfSelectedItem]]];
    [self rebindAction:@"hanjaConvert:"         toKey:keyDict[[hanjaSelectPopUp indexOfSelectedItem]]];
    if (dictPath)
        [_imMap writeToFile:dictPath atomically:YES];

    /* (c) 표시/상태 → defaults(a3)
     * [FIX] initState/hanjaArea/inputUnit 은 NSMatrix 라디오(English/Korean,
     * None/Mark, Character/Word). 원본은 `-state` 로 저장했는데 매트릭스에서
     * -state 는 선택 셀의 on 상태(항상 1)라 어느 항목을 골랐는지 못 잡는 버그였다.
     * → 선택 셀의 title 을 저장(셀 title 이 곧 비교값). 로드도 title 로 셀 선택. */
    [defaults setObject:[[initState selectedCell] title] forKey:@"SMInitState"];
    [defaults setObject:[[hanjaArea selectedCell] title] forKey:@"SMHanjaArea"];
    [defaults setObject:[[inputUnit selectedCell] title] forKey:@"SMInputUnit"];

    /* [ENHANCE] 자판 라디오: 선택 열(0/1/2)을 문자열로 저장(configPreferenceValue
     * 가 intValue 로 읽어 setKeyboardLayout: 반영). */
    if (keyboardType)
        [defaults setObject:[NSString stringWithFormat:@"%d", [keyboardType selectedColumn]]
                     forKey:@"SMKeyboardType"];

    idx = [hanjaRepeatCount intValue];
    v = (idx <= 0) ? (id)@"3" : (id)[NSString stringWithFormat:@"%d", idx];
    [defaults setObject:v forKey:@"SMHanjaRepeatCount"];

    idx = [hanjaConversion intValue];      /* [INFER] 56852: 정본은 별도 셀렉터 */
    if (idx >= 0)
        [defaults setObject:[NSString stringWithFormat:@"%d", idx]
                     forKey:@"SMHanjaConversion"];

    idx   = [attributePopUp indexOfSelectedItem];
    color = [colorWell color];
    v = idx ? (id)@"Underline" : (id)@"Background";
    [defaults setObject:v forKey:@"NSMarkedTextAttribute"];
    [defaults setObject:[NSArchiver archivedDataWithRootObject:color]
                 forKey:@"NSMarkedTextColor"];

    /* (b) 한자 사전 pref 파일 */
    prefPath = [NSString stringWithFormat:@"%@%@",
                  NSHomeDirectory(), @"/Library/Dictionary/SMInputManager.pref"];
    [kbfile setObject:[dictionaryListPU stringValue] forKey:@"SMHanjaDictioanry"];
    [kbfile setObject:[dictionaryPathTF stringValue] forKey:@"SMHanjaDictionaryPath"];
    if (prefPath)
        [kbfile writeToFile:prefPath atomically:YES];
    /* NOTE: 원본은 kbfile(v32) 을 해제하지 않는다(누수) — 그대로 재현. */
}

/*
 * [ENHANCE] 원본에 없는 개선(사용자 요청): 저장 후 "저장됨" 모달 확인을 띄우고
 * 패널을 닫는다. 원본은 적용 버튼이 저장만 하고 패널을 닫지 않았다(닫기는 타이틀바
 * 닫기 상자). writeDefaults:/writeGlobalDefaults: 끝에서 호출.
 * NOTE: 문구는 실기 렌더 안전을 위해 영문(소스 한글 리터럴은 UTF-8로 저장돼 EUC-KR
 * 기대 환경에서 깨질 수 있음). orderOut: 은 패널을 해제하지 않으므로 재열림 정상.
 */
- (void)confirmSavedAndClose
{
    /* [ENHANCE] 저장 즉시 반영: 실행 중인 Dispatcher(NSApp)가 defaults 를 다시 읽게
     * 한다. 원본은 시작 시(applicationDidFinishLaunching:)에만 읽어 재시작 전엔
     * 반영되지 않았다. configPreferenceValue 는 Dispatcher 메서드. */
    if ([NSApp respondsToSelector:@selector(configPreferenceValue)])
        [NSApp performSelector:@selector(configPreferenceValue)];
    NSRunAlertPanel(@"SMHangul", @"Preferences have been saved.",
                    @"OK", nil, nil);
    [panel orderOut:self];
}

/* [OK] "전역 적용"(0x8314): NSGlobalDomain 에 writeToUserDefaults: 결과 병합·저장. */
- (void)writeGlobalDefaults:sender
{
    id defaults = [NSUserDefaults standardUserDefaults];
    id dict = [[NSMutableDictionary alloc] init];
    [dict addEntriesFromDictionary:[defaults persistentDomainForName:NSGlobalDomain]];
    [self writeToUserDefaults:dict];
    [defaults setPersistentDomain:dict forName:NSGlobalDomain];
    [defaults synchronize];
    [dict release];
    [self confirmSavedAndClose];               /* [ENHANCE] */
}

/* [OK] "적용/OK"(0x83e4): 앱 도메인(processName)에 writeToUserDefaults: 결과 저장.
 * NOTE: 패널을 닫지 않는다(원본 동일 — 닫기는 타이틀바 닫기 상자). */
- (void)writeDefaults:sender
{
    id defaults = [NSUserDefaults standardUserDefaults];
    id appName  = [[NSProcessInfo processInfo] processName];
    id dict = [[NSMutableDictionary alloc] init];
    [dict addEntriesFromDictionary:[defaults persistentDomainForName:appName]];
    [self writeToUserDefaults:dict];
    [defaults setPersistentDomain:dict forName:appName];
    [defaults synchronize];
    [dict release];
    [self confirmSavedAndClose];               /* [ENHANCE] */
}

/*
 * [OK] 사전 경로 디렉터리에서 확장자 "dic" 파일을 모아 dictionaryListPU 재구성(0x84d8).
 */
- (void)updateDictionaryPopUpButton:sender
{
    id titles = [[NSMutableArray alloc] init];  /* 원본은 여기서 2회 alloc(1개 누수) */
    id fm     = [NSFileManager defaultManager];
    id files  = [fm directoryContentsAtPath:[dictionaryPathTF stringValue]];
    int i, n = [files count];
    for (i = 0; i < n; i++) {
        id f = [files objectAtIndex:i];
        if ([[f pathExtension] isEqualToString:@"dic"])
            [titles addObject:f];
    }
    [dictionaryListPU removeAllItems];
    [dictionaryListPU addItemsWithTitles:titles];
}

/*
 * [OK] 한자 사전 경로 선택(0x8644): NSOpenPanel 로 디렉터리 선택 → dictionaryPathTF 반영
 * → 팝업 갱신.
 */
- (void)setPath:sender
{
    id op = [NSOpenPanel openPanel];
    [op setCanChooseDirectories:YES];           /* [INFER] 55FC9: 셋업(arg YES) */
    if ([op runModal]) {                         /* [INFER] 55FCD: runModal */
        [dictionaryPathTF setStringValue:[op filename]];
    }
    [self updateDictionaryPopUpButton:nil];
}

/*
 * [OK] 현재 한자 사전 표시명(0x86d4): SMInputManager.pref 가 있으면
 * "<SMHanjaDictionary>/<SMHanjaDictionaryPath>" 형식 문자열, 없으면 nil.
 */
- dictionaryName
{
    id fm = [NSFileManager defaultManager];
    id path, dict, name, dpath;
    BOOL isDir = NO;

    path = [NSString stringWithFormat:@"%@%@",
              NSHomeDirectory(), @"/Library/Dictionary/SMInputManager.pref"];
    dict = [NSDictionary dictionaryWithContentsOfFile:path];
    if (![fm fileExistsAtPath:path isDirectory:&isDir] || isDir)
        return nil;
    name  = [dict objectForKey:@"SMHanjaDictionary"];
    dpath = [dict objectForKey:@"SMHanjaDictionaryPath"];
    return [NSString stringWithFormat:@"%@/%@", name, dpath];
}

/* [OK] 소멸자(0x87cc): 목록/맵 해제 후 상위 dealloc. */
- (void)dealloc
{
    [_imArray release];
    [_imMap   release];
    [super dealloc];
}

@end
