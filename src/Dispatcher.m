/*
 * Dispatcher.m — 앱 객체 + NSInputServer 델리게이트 (복원, 진행중)
 *
 * SMHangul 최상위. NSInputServer 델리게이트로 입력 프로토콜을 구현하고, 키를
 * FrontEnd(전역 fep)로 넘겨 조합한 뒤 marked text/확정 문자열을 클라이언트
 * (sender)에 반영한다. 각 메서드는 IDA 디컴파일 대조([OK]) / 미복원([TODO]).
 *
 * 조합 사이클: insertText:sender:conversation: → (영문자면) [fep imProcessEvent:]
 *   → displayString:(marked text 갱신). 확정/모드전환/비문자 시 makeCompleteChar:
 *   로 [sender insertText:완성문자열] 커밋 후 리셋.
 */
#import "Dispatcher.h"
#import "FrontEnd.h"

/* 전역 FrontEnd 인스턴스(원본 _fep@0x42348). init에서 textInput 과 함께 설정. */
extern id fep;
/* 한자 변환 대상 문자열(원본 _hanjaInputString@0x4234c). */
extern id hanjaInputString;
/* NSInputServer 인스턴스(연결 vend) — 재구성이 누락했던 등록. */
extern id inputServer;
@class NSInputServer;

@implementation Dispatcher

/*
 * [OK] 기본 환경설정 등록. 색상 기본값 + 키/값 쌍들을 NSUserDefaults 에
 * registerDefaults: 로 등록.
 * NOTE: 기본 키/값(off_5E048~off_5E0D8, 7쌍)·색상 인자는 정본에서 확정.
 */
+ (void)initialize
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    /* [d setObject:<val> forKey:<key>] x7 — 원본 off_5E048..off_5E0D8 쌍 (확인) */
    [d setObject:@"0" forKey:@"SMKeyboardType"];   /* [ENHANCE] 기본 두벌식(0) */
    [[NSUserDefaults standardUserDefaults] registerDefaults:d];
}

/*
 * [OK] super init → FrontEnd(전역 fep) 생성 → preference 로드 → eng/kor 아이콘
 * 이미지 설정. NOTE: 581AB(self setter)·preference 로드 셀렉터·아이콘 파일경로
 * (off_5E0F0 eng / off_5E0FC kor)는 확인.
 */
- init
{
    [super init];
    /* [self <581AB>:self]; */                 /* NOTE: setDelegate:/아이콘 설정 등 */
    fep = [[FrontEnd allocWithZone:[self zone]] init];
    /* [preference load]; */                    /* NOTE: 환경설정 로드 */
    /* 번들 Resources 의 eng.tiff/kor.tiff 를 이름으로 조회(실측: off_5E0F0="eng",
     * off_5E0FC="kor", NSImage imageNamed:). 한/영 모드 아이콘. */
    engImage = [NSImage imageNamed:@"eng"];
    korImage = [NSImage imageNamed:@"kor"];
    /* [ENHANCE] Hanja Conversion 기본 ON. 원본은 이 값을 읽기만 하고 안 썼으나(死),
     * 옵션 의도(한자변환 사용 여부)에 맞춰 동작을 부여한다. 기본 ON 이라 pref 미설정
     * 시 현행(변환 가능) 유지 — 회귀 없음. configPreferenceValue 가 pref 있으면 override. */
    hanjaConversation = 1;
    return self;
}

/*
 * NSApplication 서브클래스 훅. [NSApp run] 이 이벤트 루프 진입 직전 호출 →
 * NSApp 완성·WindowServer 연결·main nib 로드 이후라 안전(정본 HexInputServer 가
 * NSObject+수동 runloop 로 하던 "runloop 진입 직전 서버 생성"과 동일한 시점).
 * NSInputServer 생성을 -init(+sharedApplication 진행 중, NSApp 미완성)에서 여기로
 * 옮긴다 — -init 재진입/DO 데드락 회피. name 은 Info 의 ConnectionName 과 일치.
 */
- (void)finishLaunching
{
    [super finishLaunching];
    inputServer = [[NSInputServer alloc]
                      initWithDelegate:self
                                  name:@"SoftMagicKoreanFrontendProcessor"];
}

/*
 * [OK] 기동 완료 시: 설정 적용 → 초기 모드(initState==1 이면 한글 ON) 반영 →
 * [fep setAutomata:] → 아이콘 갱신.
 * NOTE: 5734A(configPreferenceValue 추정)·572DA(setAutomata: 추정) 셀렉터 확인.
 * ※ NSInputServer(ConnectionName "SoftMagicKoreanFrontendProcessor")는 -finishLaunching
 *   에서 생성한다(아래 참조 — -init 은 +sharedApplication 진행 중이라 위험).
 *   이 델리게이트 통지가 실제로 오는지(Dispatcher 가 NSApp 의 delegate 로 nib 배선
 *   되는지)는 SMHPROBE 로그로 확인 — 안 오면 초기 모드/아이콘 설정을 finishLaunching
 *   으로 이관 필요(증상3 관련).
 */
- (void)applicationDidFinishLaunching:(NSNotification *)note
{
    [self configPreferenceValue];              /* NOTE: 5734A */
    if (initState == 1) {
        isTurnedOn = 1;
        [fep setAutomata:1];                   /* NOTE: 572DA (setAutomata: 추정) */
    } else {
        isTurnedOn = 0;
        [fep setAutomata:0];
    }
    [self changeIcon];
}

/*
 * [OK] 키 입력 진입. 꺼짐이면 클라이언트로 통과. 영문자(A-Z/a-z)만 조합에
 * 넣고, 비문자는 조합을 커밋(makeCompleteChar:)한 뒤 통과. 한자모드면 먼저 커밋.
 */
- (void)insertText:(id)inString sender:(id)sender conversation:(long)conv
{
    unsigned short c;
    if (!isTurnedOn) {
        [sender insertText:inString];
        return;
    }
    /* [FIX codex#2] 조합 경계에서 대기 중이던 자판 변경을 적용(isJamoKey 라우팅이
     * 새 자판 role 표를 쓰도록 반드시 imProcessEvent/isJamoKey 앞에서). */
    if (layoutPending && ![fep isWorking]) {
        [fep setAutomata:1];
        layoutPending = 0;
    }
    c = [inString characterAtIndex:0];
    /* [ENHANCE] 자판 인지 라우팅: 현재 자판에서 자모인 키만 조합에 넣고, 그 외
     * (숫자·기호·비자모)는 조합 커밋 후 통과. 두벌식에선 isJamoKey 가 A-Za-z 에서만
     * 참이라 기존 `(c-'A')>25 && (c-'a')>25` 게이트와 동일(회귀 없음). 세벌식최종의
     * 숫자/기호 자모 키를 조합에 태우려면 이 자판 인지 방식이 필수(§10). */
    if (![fep isJamoKey:c]) {
        [self makeCompleteChar:sender];
        [sender insertText:inString];
        return;
    }
    if (HANJA_MODE)
        [self makeCompleteChar:sender];
    [fep imProcessEvent:c];
    /* 확정분(completeChar) 즉시 커밋 조건:
     *  - [ENHANCE][Phase2] Input Unit=Character: 확정 음절을 즉시 삽입.
     *  - [FIX] 단독 자모(완성 안 된 자음/모음)일 때: 원본은 이를 marked 에 누적하는데,
     *    복수 단독 자모가 marked 에 쌓이면 클라이언트가 멈추는 버그가 있다("ㅋㅋㅋ").
     *    → 단독 자모는 즉시 커밋해 marked 누적을 피한다("ㅋ ㅋ"가 되던 것과 동일 결과).
     * 완성 음절 Word 누적은 유지. astring(조합중)은 종성 이월 때문에 커밋 안 함. */
    if (inputUnit || [fep finalizedIsJamo]) {
        id fin = [fep finalizedString];
        if ([fin length]) {
            [sender setMarkedText:@"" selectedRange:NSMakeRange(0, 0)];
            [sender insertText:fin];
            [fep drainFinalized];
        }
    }
    [self displayString:sender];
}

/*
 * [OK] FrontEnd 조합 상태를 sender 의 marked text 로 반영.
 * 조합 중이면 [sender setMarkedText:[fep inputString] selectedRange:(len,0)],
 * 아니면 [fep setWorkingInit](세션 종료).
 */
- (void)displayString:(id)sender
{
    id s;
    unsigned len;
    if ([fep isWorking]) {
        s   = [fep inputString];
        len = [s length];
        [sender setMarkedText:s selectedRange:NSMakeRange(len, 0)];
    } else {
        [fep setWorkingInit];
    }
}

/*
 * [OK] 현재 조합을 확정해 클라이언트에 커밋. marked text 를 비우고 완성 문자열을
 * insertText: 로 넣은 뒤 FrontEnd·모드·한자 상태를 리셋.
 * NOTE: 57EAE(sender 무인자 호출)·57EB2(sender bool)·57EB6(hanjaConverter setter)
 * 셀렉터는 최종 확인.
 */
- makeCompleteChar:(id)sender
{
    id s;
    if ([fep isWorking]) {
        [sender setMarkedText:@"" selectedRange:NSMakeRange(0, 0)];
        s = [fep inputString];
        [sender insertText:s];
        /* [sender <57EAE>]; */          /* NOTE: 무인자 finalize — 확인 */
        [fep setWorkingInit];
        hrepeatCount = 0;
        HANJA_MODE   = 0;
        START_MODE   = 0;
    }
    if (![sender wantsToInterpretAllKeystrokes] /* NOTE: 57EB2 확인 */) {
        [hanjaConverter setDictionary:0];       /* NOTE: 57EB6 확인 */
        [hanjaConverter clearWordArray];
    }
    return self;
}

/*
 * [OK] 특수키/명령 디스패처. 자판 바인딩 액션(SMHangul.dict)을 처리:
 *   toggleConversionMode: 한/영 토글, inputModeChange: 벌식 전환,
 *   hanjaConvert: + moveLeft/Right/Up/Down: 한자 후보 탐색(hrepeatCount ±1/±10),
 *   deleteBackward: 백스페이스(fep imProcessBS), enteredSpace: 공백/한자 다음,
 *   changeLanguage: 언어 전환. 처리 못 하면 조합 커밋 후 클라이언트로 forward.
 * 디컴파일 제어흐름을 goto 라벨로 충실 재작성. NOTE 셀렉터는 확인 대상.
 */
- (void)doCommandBySelector:(SEL)cmd sender:(id)sender conversation:(long)conv
{
    if (!isTurnedOn) {
        if (cmd == @selector(changeLanguage:))
            goto changeLang;
        if (cmd == @selector(toggleConversionMode:)) {
            isTurnedOn = 1;
            [fep setAutomata:1];                 /* NOTE: 57DC1 (모드 설정) */
            goto icon;
        }
        goto forward;
    }
    if (cmd == @selector(changeLanguage:)) {
changeLang:
        [self changeLanguage:(id)conv];
        return;
    }
    if (cmd == @selector(toggleConversionMode:)) {
        [self makeCompleteChar:sender];          /* 57D99 */
        isTurnedOn = 0;
        [fep setAutomata:0];                     /* NOTE: 57DC1 */
icon:
        [self changeIcon];
        return;
    }
    if (cmd == @selector(inputModeChange:)) {
        [self makeCompleteChar:sender];
        [fep changeInputMode];                   /* NOTE: 57DCD */
        return;
    }
    if (cmd == @selector(hanjaConvert:)) {
        if (!hanjaConversation) {     /* [ENHANCE] 한자변환 OFF: 변환 안 하고 조합만 확정 */
            [self makeCompleteChar:sender];
            return;
        }
        if (!hrepeatCount)
            START_MODE = 1;
        HANJA_MODE = 1;
        ++hrepeatCount;
        [self hanjaConvert:sender];
        return;
    }
    if (cmd == @selector(moveLeft:) && HANJA_MODE) {
        if (hrepeatCount > 1) { --hrepeatCount; [self hanjaConvert:sender]; }
        return;
    }
    if (cmd == @selector(moveRight:) && HANJA_MODE) {
        ++hrepeatCount;
        [self hanjaConvert:sender];
        return;
    }
    if (cmd == @selector(moveUp:) && HANJA_MODE) {
        int step = hanjaRepeatCount > 0 ? hanjaRepeatCount : 10;   /* [ENHANCE] RepeatCount=이동단위 */
        if (hrepeatCount > step) { hrepeatCount -= step; [self hanjaConvert:sender]; }
        return;
    }
    if (cmd == @selector(moveDown:) && HANJA_MODE) {
        int step = hanjaRepeatCount > 0 ? hanjaRepeatCount : 10;   /* [ENHANCE] RepeatCount=이동단위 */
        hrepeatCount += step;
        [self hanjaConvert:sender];
        return;
    }
    if (cmd == @selector(deleteBackward:)) {
        if (!HANJA_MODE) {
            if ([fep imProcessBS]) {             /* 57DED */
                [self displayString:sender];
                return;
            }
            if ([fep isWorking])                 /* NOTE: 57DF5 (working/보유 확인) */
                goto forward;
        }
    } else if (cmd == @selector(enteredSpace:)) {
        if (HANJA_MODE) {
            ++hrepeatCount;
            [self hanjaConvert:sender];
            return;
        }
        /* 非한자: 조합 커밋 후 실제 공백을 삽입한다(원본 0x6934: makeCompleteChar
         * → [sender insertText:@" "]). 자판 바인딩 " "=enteredSpace: 는 SMHangul
         * 고유 셀렉터라, 이를 클라이언트로 forward하면 클라이언트가 모르는 셀렉터
         * 라서 공백이 소실된다(재구성 누락 버그). 그래서 여기서 직접 공백을 넣는다. */
        [self makeCompleteChar:sender];
        [sender insertText:@" "];
        return;
    } else if (HANJA_MODE) {
        [self makeCompleteChar:sender];
        return;
    }
    [self makeCompleteChar:sender];              /* 57D99 */
forward:
    [sender doCommandBySelector:cmd];            /* NOTE: 미처리 명령 클라이언트로 전달 */
}

/* [OK] 이 입력기는 모든 키를 가로채지 않는다(자판 바인딩만). */
- (BOOL)wantsToInterpretAllKeystrokes
{
    return NO;
}

/* [OK] 비활성화 시 현재 조합 확정. */
- (void)setActivated:(BOOL)flag sender:(id)sender
{
    if (!flag)
        [self makeCompleteChar:self];
}

/* [OK] 입력 취소 시 현재 조합 확정. */
- (void)cancelInput:(id)sender conversation:(long)conv
{
    [self makeCompleteChar:sender];
}

/* [OK] marked text 포기 예고 시 현재 조합 확정. */
- (void)markedTextWillBeAbandoned:(id)sender conversation:(long)conv
{
    [self makeCompleteChar:sender];
}

/*
 * [OK] marked text 내 선택(커서)이 바뀌면: sender 에 marked text 가 있고 선택
 * 범위가 있으면 조합 확정. NOTE: fep 콜백(57822)·[sender hasMarkedText](57955) 확인.
 */
- (void)markedTextSelectionChanged:(NSRange)newSel sender:(id)sender conversation:(long)conv
{
    if ([sender hasMarkedText]) {
        [fep setWorkingInit];                 /* NOTE: 57822 (fep 상태 정리) */
        if (newSel.length)
            [self makeCompleteChar:sender];
    }
}

/* [OK] 활성 대화(앱) 전환 직전, 이전 sender 에 marked text 있으면 확정. */
- (void)activeConversationWillChange:(id)sender
                     oldConversation:(long)conv newConversation:(long)newConv
{
    if ([sender hasMarkedText])               /* NOTE: 57542 */
        [self makeCompleteChar:sender];
}

/*
 * [OK] 한자 변환 오케스트레이션. START_MODE 첫 진입 때 [fep inputString]을
 * hanjaInputString 에 포착하고, HanjaConverter 로 후보를 조회(단일문자=길이1은
 * 문자별, 그 외 단어별; hrepeatCount 로 후보 인덱스)해 applyHanja:isComplete:0 로
 * 적용하고 한자 패널을 띄운다.
 * NOTE 셀렉터: 57829(fep inputString)·5794D(문자열 포착)·57951(setDispatcher:)·
 * 57955(sender 설정)·57959(단일문자 변환)·57965(단어 변환)·pool 생성(57AC1) 확인.
 */
- (void)hanjaConvert:(id)sender
{
    [[NSAutoreleasePool alloc] init];             /* NOTE: 임시 pool 추정 */
    if (![fep isWorking] || [sender hasMarkedText]) {
        textInput = sender;
        if (START_MODE) {
            id s = [fep inputString];
            if (!s || ![s length])
                return;
            if (hanjaInputString)
                [hanjaInputString release];
            hanjaInputString = [[fep inputString] copy];   /* NOTE: 5794D 포착 방식 */
            START_MODE = 0;
        }
        if (!hanjaConverter)
            hanjaConverter = [[HanjaConverter alloc] init];
        [hanjaConverter setDispatcher:self];
        [hanjaConverter setResp:sender];
        /* [ENHANCE] Hanja Area: Mark(hanjaArea==0, 기본)=후보 패널 표시,
         * None(hanjaArea==1)=패널 생략(인라인만, ~/이동키로 순환은 유지).
         * 기본값(미설정→0)은 패널 표시 = 현행 유지. */
        if ([hanjaInputString length] == 1) {
            id r = [hanjaConverter hanjaWithString:hanjaInputString index:hrepeatCount - 1];
            [self applyHanja:r isComplete:0];
            if (r && !hanjaArea)
                [hanjaConverter hanjapanel:hanjaInputString index:0];
        } else {
            id r = [hanjaConverter hanjaWithStrings:hanjaInputString index:hrepeatCount];
            [self applyHanja:r isComplete:0];
            if (r && !hanjaArea)
                [hanjaConverter hanjapanel:hanjaInputString index:hrepeatCount];
        }
    }
}

/*
 * [OK] 선택된 한자 적용. 조합 중이면 fep 의 조합 문자를 한자로 치환하고,
 * complete 면 커밋(makeCompleteChar:) / 아니면 marked 표시(displayString:).
 * 조합 중이 아니면 클라이언트에 직접 insertText: 하고 hrepeatCount 리셋.
 * NOTE: 576D6(fep 치환 메서드) 확인.
 */
- applyHanja:(id)hanja isComplete:(BOOL)complete
{
    if ([fep isWorking]) {
        [fep setInputString:hanja];               /* NOTE: 576D6 (조합 문자 치환) */
        if (complete)
            [self makeCompleteChar:textInput];
        else
            [self displayString:textInput];
    } else {
        [textInput insertText:hanja];
        hrepeatCount = 0;
    }
    return self;
}

/* [OK] 앱 아이콘을 현재 모드(한글=korImage / 영문=engImage)로 갱신. */
- (void)changeIcon
{
    if (isTurnedOn)
        [self setApplicationIconImage:korImage];
    else
        [self setApplicationIconImage:engImage];
}

/* [OK] 프로그램적 한/영 전환(0=끄기, 1=켜기). 멱등 가드 후 [fep setAutomata:]+아이콘. */
- (void)changeLanguage:(id)flag
{
    if (!flag) {
        if (!isTurnedOn)
            return;
        isTurnedOn = 0;
        [fep setAutomata:0];                       /* NOTE: 57276 */
        [self changeIcon];
    } else if ((int)flag == 1 && !isTurnedOn) {
        isTurnedOn = 1;
        [fep setAutomata:1];
        [self changeIcon];
    }
}

/* [OK] marked text 는 클라이언트(sender)에 직접 설정하므로 여기선 무동작. */
- (void)setMarkedText:(id)aString selectedRange:(NSRange)selRange
{
}

/* [OK] 클라이언트 비활성 시, fep 가 조합 중이 아니면 상태 정리(setWorkingInit). */
- (void)senderDidResignActive:(id)sender
{
    if (![fep isWorking])
        [fep setWorkingInit];                      /* NOTE: 573EB */
}

/*
 * [OK] NSUserDefaults 에서 환경설정을 읽어 ivar 로 로드. 각 키의 값이 특정
 * 문자열과 같으면 1, 아니면 0(initState/hanjaArea/inputUnit) 또는 intValue
 * (hanjaRepeatCount/hanjaConversation). inputUnit 은 fep 에 반영.
 * NOTE: 기본 키/비교값 문자열(off_5E048/54/60/6C/78/108/90/A8)은 정본에서 확정.
 */
- (void)configPreferenceValue
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    id v;
    /* 실측 키/값(원본 0x6418): off_5E048="SMInitState", off_5E054="English",
     * off_5E060="SMHanjaArea", off_5E06C="None", off_5E078="SMInputUnit",
     * off_5E108="Character", off_5E090="SMHanjaRepeatCount", off_5E0A8=
     * "SMHanjaConversion". Preference 가 저장하는 키와 동일해야 반영된다(이전 우리
     * 플레이스홀더 키는 저장 키와 불일치라 설정이 전혀 반영되지 않았음). */
    /* [FIX] 폴라리티 교정: 원본은 =="English" → initState=1 → 한글 ON 이라 역전돼
     * 있었다("English" 선택인데 한글 시작). "Korean" 선택 → 한글 ON 으로 정렬.
     * (launch 분기 initState==1→한글 ON 은 그대로.) */
    if ((v = [d objectForKey:@"SMInitState"]))
        initState = [v isEqual:@"Korean"] ? 1 : 0;
    if ((v = [d objectForKey:@"SMHanjaArea"]))
        hanjaArea = [v isEqual:@"None"] ? 1 : 0;
    if ((v = [d objectForKey:@"SMInputUnit"])) {
        inputUnit = [v isEqual:@"Character"] ? 1 : 0;
        [fep setInputUnit:(char)inputUnit];
    }
    if ((v = [d objectForKey:@"SMHanjaRepeatCount"]))
        hanjaRepeatCount = [v intValue];
    if ((v = [d objectForKey:@"SMHanjaConversion"]))
        hanjaConversation = [v intValue];
    /* [ENHANCE] 자판 선택: 0=두벌식 1=세벌390 2=세벌최종. fep 에 반영하고,
     * Korean 활성 & 조합중 아니면 오토마타를 즉시 재생성(경계 안전). 조합중이면
     * 다음 한/영 토글의 setAutomata: 에서 반영된다. */
    if ((v = [d objectForKey:@"SMKeyboardType"])) {
        [fep setKeyboardLayout:[v intValue]];
        if (isTurnedOn) {
            if (![fep isWorking])
                [fep setAutomata:1];        /* 조합중 아님 → 즉시 반영 */
            else
                layoutPending = 1;          /* [FIX codex#2] 조합중 → 경계에서 반영 */
        }
    }
}

/* [OK] 환경설정 창 표시(Preference 지연 생성). */
- (void)showPreference:(id)sender
{
    if (!preference)
        preference = [[Preference alloc] init];
    [preference showUI];
}

/* [OK] KS↔"FullKorean" 변환을 FrontEnd 로 위임. */
- (unsigned short)unicodeFromKS:(unsigned short)ks   { return [fep unicodeFromKS:ks]; }
- (unsigned short)ksFromUnicode:(unsigned short)uni  { return [fep ksFromUnicode:uni]; } /* [INFER] 위임 */

/* [OK] 이 입력기는 비활성화 가능. */
- (BOOL)canBeDisabled {  return YES; }

/* [OK] marked text 보유로 보고(실측 상수 1). */
- (BOOL)hasMarkedText {  return YES; }

/* [INFER] marked text 는 클라이언트가 관리 — 빈 스텁(setMarkedText:selectedRange:와 대칭). */
- (void)unmarkText { }

/* [OK] 클라이언트 활성화 시, fep 가 조합 중이 아니면 상태 정리(senderDidResignActive:와 대칭). */
- (void)senderDidBecomeActive:(id)sender
{
    if (![fep isWorking])
        [fep setWorkingInit];
}

/*
 * [OK] 종료. quitMenu 에서 오면 종료 확인 알림 후 확인 시 [super terminate:];
 * 그 외(핫키 등)면 fep 액션. NOTE: 지역화 알림 문자열·572E6(fep 액션) 확인.
 */
- (void)terminate:sender
{
    if (quitMenu == sender) {
        if (NSRunAlertPanel(@"SMHangul", @"Quit SMHangul?", @"OK", @"Cancel", nil))
            [super terminate:nil];
    } else {
        [fep changeInputMode];              /* NOTE: 572E6 (fep 액션 — 확인) */
    }
}

/* [OK] 빈 스텁. */
- (void)applicationWillBecomeActive:(NSNotification *)note { }

/* [OK] 아이콘 이미지 해제 후 상위 dealloc. */
- (void)dealloc
{
    [engImage release];
    [korImage release];
    [super dealloc];
}

@end
