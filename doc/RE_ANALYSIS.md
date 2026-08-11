# RE 분석 노트 — SMHangul (Phase 0)

정적 분석(IDA Pro, i386 Mach-O) 실측. 주소는 imagebase 0x2000 기준 VM 주소.
md5(바이너리) = 031519cc8068d171e98d619431fc4f0d. 함수 151개(전부 명명됨).

## 1. 데이터 테이블 맵 (__data, 이름·주소 실측)
자모 조합 상태기계가 참조하는 룩업 테이블 — **복원 시 정본에서 추출해 리소스로
재사용**(§PLAN 3.2 절차대로 원소폭/인덱스/센티넬 검증 후).

| 심볼 | 주소 | 추정 크기/용도 |
|---|---|---|
| `_token_tbl` | 0xb330 | 256B, ASCII→토큰 분류 |
| `_cho_tbl` | 0xb430 | 256B, ASCII→초성 인덱스 |
| `_jung_tbl` | 0xb530 | 256B, ASCII→중성 인덱스 |
| `_jong_tbl` | 0xb630 | 256B, ASCII→종성 인덱스 |
| `_cho_two` | 0xb7f0 | 초성 결합 |
| `_jaeum_two` | 0xb830 | 자음 결합 |
| `_moeum_two` | 0xb870 | 모음 결합 |
| `_act_tbl` | 0xb8b0 | 액션 테이블 |
| `_bok_ja1/2/ja` | 0xb8e2.. | 복자음 조합 |
| `_bok_mo1/2/mo` | 0xb924.. | 복모음 조합 |
| `_bok_jaeum1/2/jaeum` | 0xb972.. | 복자음(받침) |
| `_ks` | 0x12358 | ~0xf000(60KB), KS 코드표 |
| `_Uni_to_FullKorean_Table` | 0x21ed6 | 0x20000(128KB), Unicode→풀코리안 |
| `_oneOfToken/Cho/Jung/Jong` | 0x41ed6.. | 각 256B, 3벌식/멤버십 |
| `_twoOfCho` | 0x422d6 | |
| `_actionTbl` | 0x42316 | |
| `_SMcode_Hanja_Table` | 0x42370 | ~0x1b000(110KB), **내장 한자 코드표** |
| `_map_idx` | 0xb270 | 32행 코드배열 시작 포인터(조합코드→위치) |
| `_map_cnt` | 0xb2f0 | 32행 원소 수 |

### 인코딩 로직 (search_code: 실측)
조합 완성 코드 → EUC-KR 완성형: 코드 비트10-14를 행으로 map_idx/map_cnt 조회,
행내 위치 pos + 이전행 누적 → `((pos/94 + 0xB0)<<8) | (pos%94 + 0xA1)` (KS X 1001,
94자/행). 표 밖 특수음절 5개는 개별 상수 매핑. (Phase 2 착수, src/Automata.m)

### automata_init 초기값 (실측)
rest_flag=ret_flag=-1, finishRest=0, cho=1, jung=2, jong=1(빈 자모 센티넬),
jaso_temp=comp_code=unfn_code=asc_code=0, clearBackUp, status=0.

### korean: 상태기계 (실측 — src/Automata.m 에 복원 완료)
핵심 구동: `token = token_tbl[입력]` → `action = act_tbl[5*status + token]`
(status×token 2D 표, 5토큰/행) → action(0~13) 분기로 초/중/종성 전이.
- status 값: 0=빈,1=초성,2=초+중,3=초+중+종,4=초+중+복종성.
- ret_flag: 1=ASCII그대로, 2=조합중(미완성), 3=완성(comp_code) + 이전 잔여.
- rest_flag: 잔여(직전 확정 문자) 처리 신호(-1=없음, 2/3=잔여 종류).
- 결합 헬퍼: `make_two:cho:jung:jong`→조합코드, `search_code:`→EUC-KR,
  `make_bokmo:a:b:&out`/`make_bokja:a:b:&out`(성공 0 / 실패 -1).
- 액션 요지: 0 모음단독완성 · 1 비한글 · 2 초성시작 · 3 잔여후초성/모음 ·
  4 초+중 · 5 잔여후초성 · 6 복모음 · 7 잔여후비한글 · 8 종성 · 9 종성→다음초성
  이동(연서) · A 복종성 · B 종성확정 · C 복종성→다음초성 · D 복종성확정후새초성.

### message_refs 셀렉터 매핑 (0x5E378~, 바이트 실측 + otool 대조)
간접 셀렉터(IDA가 dword_5A79E+15322 식으로 표기)의 실제 대상:
entry0=clearBackUp, 1=saveBackUp, 2=make_two:::, 3=search_code:,
4=make_bokmo:::, 5=savePrevBack, 6=make_bokja:::. → korean: 헬퍼 호출 전부 해소.

### clearBackUp (실측)
count=-1; back[0..4]의 cho/jung/jong/code 클리어(status 필드는 보존).

### 결합 헬퍼 (실측 — 복원 완료)
- `make_two:c:j:g` = 비트팩킹: `(cho_val[c]|0x8000) | jung_val[j] | jong_val[g]`
  → 조합 한글 16비트 코드(신규표 _cho_val@0xb730/_jung_val@0xb770/_jong_val@0xb7b0).
- `make_bokmo/bokja/bokjaeum:a:b:&out` = 쌍 결합표 선형검색(bok_mo1/2/mo 13개,
  bok_ja1/2/ja 11개, bok_jaeum1/2/jaeum 11개). 성공 *out=결합값 반환0, 실패 -1.
- 백업링: `saveBackUp`=push(back[++count]에 cho/jung/jong/status/unfn_code),
  `savePrevBack`=종성→초성 이동용 새초성 push(code=cho_two[cho]),
  `reduceCount`=pop(--count, 상태 복원 = 백스페이스 역분해).

### NoCheckAutomata 차분 (실측 — 복원 완료)
Automata 상속, korean:/automata_init 재정의. **3벌식 직접배열**: 분류/결합표가
oneOfToken/actionTbl/oneOfCho/oneOfJung/oneOfJong/twoOfCho(자모 확정 → 검사 불필요).
**백업링 미사용**(clearBackUp/saveBackUp 호출 없음). 결합 헬퍼(make_*/search_code:)는
Automata 상속. init은 Automata init에서 clearBackUp만 뺀 것.

### 복원 진행표 (자동자 계열 — 전부 [OK])
Automata: automata_init, korean:, search_code:, clearBackUp, make_two:::,
make_bokja/bokjaeum/bokmo:::, saveBackUp, savePrevBack, reduceCount, 게터(추정).
NoCheckAutomata: automata_init, korean:. → **자동자 계열 복원 완결.**

### 추출 필요 데이터표 종합 (다음 단위, PLAN §3.2 절차)
2벌식: token_tbl/cho_tbl/jung_tbl/jong_tbl(각256), act_tbl, cho_two, moeum_two.
비트팩킹: cho_val@0xb730, jung_val@0xb770, jong_val@0xb7b0.
복합: bok_mo1/2/mo(13), bok_ja1/2/ja(11), bok_jaeum1/2/jaeum(11).
인코딩: map_idx@0xb270, map_cnt@0xb2f0.
3벌식: oneOfToken@0x41ed6, oneOfCho@0x41fd6, oneOfJung@0x420d6, oneOfJong@0x421d6,
twoOfCho@0x422d6, actionTbl@0x42316.
대형(FrontEnd용): ks@0x12358, Uni_to_FullKorean_Table@0x21ed6, SMcode_Hanja_Table@0x42370.

### 데이터표 구조·생성 전략 (실측)
- **비트팩킹(표준 공식 — 재생성):** `cho_val[i]=i<<10`, `jung_val[i]=i<<5`,
  `jong_val[i]=i` (각 32엔트리, 일부 인덱스는 미사용 0). make_two::: 검증 완료.
  → 표준 조합코드 `0x8000 | cho<<10 | jung<<5 | jong`. 공식으로 생성 가능.
- **KS 매핑(search_code:):** 원본은 `map_idx[32]`(행별 코드배열 포인터, __data)
  + `map_cnt[32]`(행별 카운트; 행2~20 nonzero, 합계≈2350=KS X 1001 완성형).
  행 = 조합코드 비트10-14. 재구성은 flat `map_codes[]`(행 순서 연접)로 평탄화,
  순번 flat→EUC-KR `((flat/94+0xB0)<<8)|(flat%94+0xA1)`. **KS X 1001 표준에서 생성.**
- **생성/추출 방침(IP 위생):** 데이터표는 소스에 verbatim 커밋하지 않는다.
  (a) 표준 공식으로 재생성 가능한 것(bit-packing, KS 매핑)은 생성 스크립트로,
  (b) 벤더 고유 배열(token_tbl/act_tbl/oneOf*/actionTbl/bok_*/대형 한자·글리프
  테이블)은 **사용자 정본 바이너리에서 빌드시 추출**(tools/extract_tables.py 예정)
  하여 `data/`(gitignore)에 둔다. 재배포 시 라이선스 검토 선행.
- **추출 도구 완성·검증:** `tools/extract_tables.py`(Mach-O 파싱→vm2off→추출).
  자동자 테이블 26종 + map_codes 생성. 원소폭 실측: token/cho/jung/jong_tbl·
  oneOf* = ushort[128](ASCII 0-127), cho/jung/jong_val·cho/jaeum/moeum_two·
  twoOfCho = ushort[32], act_tbl = ushort[25](5×5), actionTbl = ushort[45](9×5),
  bok_ja*/bok_jaeum* = 11, bok_mo* = 13. 검증: cho_val=i<<10, act_tbl 5×5,
  **map_codes 합계 = 2350(KS X 1001)**. → 자동자 계열 코드+데이터 확보.

> **한자: 내장+외부 병존(정정 확정).** 내장 `_SMcode_Hanja_Table`(코드↔한자) +
> 외부 사용자 사전(`SMHanjaDictionaryPath`, `dictionaryWithContentsOfFile:`,
> 기본 `/Library/Dictionary/…`). Preference가 사전 경로 관리. 둘 다 처리 필요.

## 2. 클래스별 메서드 인벤토리 (실측, 복원 체크리스트)
상위클래스는 __OBJC super_class 포인터로 확정(§PLAN §2).

### Automata : NSObject  (자모 상태기계, instance_size 0x74, 24 ivar)
ivar: token,action,status,count,cho,jung,jung1,bokmo,jong,jong1,bokja,ret_flag,
rest_flag,jaso_flag,bokjaeum,asc_code,unfn_code,comp_code,jaso_temp,comb_code,
save_jong,save_jong1,finishRest,back.
메서드: automata_init, korean:, saveBackUp, savePrevBack, reduceCount, backCount,
clearBackUp, returnFlag, restFlag, comp_code, unfn_code, asc_code, isFinishAndRest,
make_two:::, make_bokja:::, make_bokjaeum:::, make_bokmo:::, search_code:.

### NoCheckAutomata : Automata  (최소 오버라이드)
automata_init, korean: — 2개만 재정의(무검사 조합 모드). 차분만 복원.

### FrontEnd : NSObject  (조합 엔진/컨트롤러 — 두뇌)
initWithHanja:, setAutomata:, setWorkingInit, setInputUnit:, makeReplaceString:,
imProcessEvent:, inputString, imProcessBS, hanjaProc:, makeInputNonAutomata,
currentPos, afterStringLength, cursorMoveLeft, cursorMoveRight, changeInputMode,
isWorking, isInlineMode, clearCvtField, displayFEP, orderOutFEP, orderFrontFEP,
changedLanguage:, unfinishedUnicode:, ksFromUnicode:, unicodeFromKS:, unicodeString:,
ksString:, convertedToKSString:length:, dealloc.

### Dispatcher : NSApplication  (앱 객체 + NSInputServer 델리게이트)
initialize, init, changeIcon, configPreferenceValue, canBeDisabled,
wantsToInterpretAllKeystrokes, setActivated:sender:, setMarkedText:selectedRange:,
hasMarkedText, unmarkText, makeCompleteChar:, doCommandBySelector:sender:conversation:,
displayString:, insertText:sender:conversation:, markedTextWillBeAbandoned:conversation:,
markedTextSelectionChanged:sender:conversation:, hanjaConvert:, unicodeFromKS:,
ksFromUnicode:, applyHanja:isComplete:, dealloc, cancelInput:conversation:,
activeConversationWillChange:oldConversation:newConversation:, senderDidBecomeActive:,
senderDidResignActive:, showPreference:, terminate:, applicationWillBecomeActive:,
applicationDidFinishLaunching:, changeLanguage:.

### CvtField : NSTextField  (조합중 표시 + 캐럿)
initWithFrame:, acceptsFirstResponder, drawCaret:, setCaret:, showCaret, hideCaret, dealloc.

### LazyPanel : NSPanel  (지연 패널)
canBecomeKeyWindow, canBecomeMainWindow, acceptsFirstResponder, makeKeyWindow, sendEvent:.

### Preference : NSObject  (환경설정)
init, showUI, loadInputManagerInfo, setPopUpWithKeyBindingDictionaray:andKey:,
indexWithKey:, changeAttributeType:.

### HanjaConverter : NSObject
(survey root 목록에서 잘림 — Phase 후속에서 method_imp 재확인.
Hanja.nib에 outlet/action changeHangul:/changeHanja:/hanjapanel: 존재.)

## 2b. FrontEnd 조합 파이프라인 (실측 — src/FrontEnd.m 복원 완료)
- `imProcessEvent:code`: save_unfn=[myAutomata unfn_code] 백업 → `[myAutomata
  korean:code]` → 성공 시 `makeReplaceString:[returnFlag]`(현재) + `makeReplaceString:
  [restFlag]`(직전 잔여) → working=1, 비인라인이면 displayFEP.
- `makeReplaceString:flag`: flag==2(ret) → isFinishAndRest면 save_unfn 확정,
  unfn_code→astring[](조합중 marked); flag==3(rest) → comp_code 확정. 코드는
  범위판정 `(code+0x5B5F)>0x5D`(완성 EUC ↔ 미완성 자모)로 unicodeFromKS:/
  unfinishedUnicode: 선택 → completeChar[](확정)/astring[](조합중).
- 변환기(실측): `unicodeFromKS:c` = ks[c-0x8144](KS→FullKorean),
  `unfinishedUnicode:c` = c-0x7370(조합중 자모→글리프), `ksFromUnicode:u` =
  Uni_to_FullKorean_Table[u].
- **★인코딩 발견:** 메서드명은 "unicode"지만 실제 산출은 **표준 유니코드가 아니라
  "FullKorean" 글리프 인코딩**(패키지 FullKorean.glyphgenerator·한글 폰트가 렌더).
  실측: unicodeFromKS:(0xB0A1)=0xCEFC(표준 AC00 아님). 재구성은 주소-충실
  (0x8144 base). **완성 문자열의 실제 표시 검증은 동작 오라클로**(런타임 필요).
- 보조(실측 복원): `imProcessBS`(백스페이스: backCount==1→리셋 / <=1→확정문자 삭제 /
  >1→reduceCount pop+조합중 복원), `makeInputNonAutomata`(조합중 커밋+리셋),
  `setAutomata:`(모드별 Automata/NoCheckAutomata alloc/init), `setWorkingInit`(세션 리셋),
  `setInputUnit:`(inputUnit=), `isWorking`/`isInlineMode`(게터).
- 표시계(실측 복원): `inputString`(completeChar+astring→NSString stringWithCharacters:
  length: + stringByAppendingString:), `displayFEP`([cvtField setStringValue:inputString]),
  `clearCvtField`(비인라인 시 빈문자열), `orderFrontFEP`(cvtWin nil이면 frontEnd nib
  지연로드+플로팅설정 후 orderFront:; LazyPanel 유래), `orderOutFEP`([cvtWin orderOut:]).
- 진행표: [OK] imProcessEvent:, makeReplaceString:, unicodeFromKS:, unfinishedUnicode:,
  ksFromUnicode:, imProcessBS, makeInputNonAutomata, setAutomata:, setWorkingInit,
  setInputUnit:, isWorking, isInlineMode, inputString, displayFEP, clearCvtField,
  orderFrontFEP, orderOutFEP.
  + changeInputMode(inLineMode 토글→order{Out,Front}FEP), currentPos(=charSize),
  cursorMoveLeft(빈 스텁), convertedToKSString:length:(표시 NSString→EUC-KR 바이트,
  비ASCII는 Uni_to_FullKorean_Table로 2바이트), ksString:(KS NSString),
  unicodeString:(EUC바이트→FullKorean, ksString:의 역), hanjaProc:(한자문자열→
  completeChar/charSize 적재), initWithHanja:(super+inLineMode=1+setAutomata:0),
  changedLanguage:(언어 on/off→조합창 표시/숨김), afterStringLength(0), cursorMoveRight
  (빈 스텁), dealloc([myAutomata release]+super). **→ FrontEnd 전 메서드 복원 완결.**

## 2c. UI 소형 클래스 (실측 — 복원 완료)
- **CvtField : NSTextField** (src/CvtField.m): initWithFrame:(비편집·비선택·
  테두리, 20pt 한글폰트, caret=0), drawCaret:(DPS 세로캐럿 x=20*caret+5,y=5,높이20;
  mode0 그리기/1 지우기; lockFocus 감쌈), setCaret:(caret=x;showCaret), showCaret
  (drawCaret:0), hideCaret(drawCaret:1), acceptsFirstResponder(NO,추정).
  NOTE: 폰트명(off_5E03C) 확인 필요.
- **LazyPanel : NSPanel** (src/LazyPanel.m): canBecomeKeyWindow/MainWindow/
  acceptsFirstResponder 모두 NO(클라이언트 포커스 유지), makeKeyWindow 무력화(추정),
  sendEvent:([super]+[NSApp ...] 포커스 콜백; NSApp 셀렉터 확인 필요).

## 2d. Dispatcher — IM 프로토콜 핵심 (실측 — src/Dispatcher.m 복원 완료)
전역 `fep`(=FrontEnd, _fep@0x42348)를 구동. 조합 사이클:
- `insertText:sender:conversation:`: 꺼짐→통과; 영문자(A-Z/a-z)만 `[fep
  imProcessEvent:c]`+`displayString:`; 비문자→`makeCompleteChar:`(커밋) 후 통과;
  한자모드면 먼저 커밋. (c=[inString characterAtIndex:0])
- `displayString:sender`: `[fep isWorking]`→`[sender setMarkedText:[fep inputString]
  selectedRange:(len,0)]`; 아니면 `[fep setWorkingInit]`.
- `makeCompleteChar:sender`(flush): isWorking면 marked 비우고 `[sender insertText:
  [fep inputString]]` 커밋→`[fep setWorkingInit]`, HANJA/START 모드·hanjaConverter 리셋.
- 초기화(실측): `+initialize`(NSUserDefaults registerDefaults: — 색상+7 키/값 기본값),
  `init`(super→fep=[[FrontEnd allocWithZone:[self zone]]init]→preference 로드→
  engImage/korImage=initByReferencingFile: eng/kor TIFF), `applicationDidFinishLaunching:`
  (설정적용→initState==1이면 isTurnedOn=1·[fep setAutomata:1] else 0→changeIcon).
- **★등록 위치:** `main()`=NSApplicationMain(argc,argv). NSInputServer 생성이 init/
  +initialize/applicationDidFinishLaunching:/main 어디에도 **없음** → nib
  (NEXTSTEP_SMHangul, Dispatcher=File's Owner) 또는 입력기용 AppKit 자동 등록으로
  추정(Info ConnectionName "SoftMagicKoreanFrontendProcessor"). **확인 필요.**
- `doCommandBySelector:sender:conversation:`(실측): 자판 바인딩 액션 디스패처.
  toggleConversionMode:(한/영 토글+setAutomata:+changeIcon), inputModeChange:(벌식,
  makeCompleteChar:+[fep changeInputMode]), hanjaConvert:+moveLeft/Right/Up/Down:
  (한자 후보 탐색 hrepeatCount ±1/±10, START_MODE/HANJA_MODE), deleteBackward:
  ([fep imProcessBS]→displayString: / 빈 조합이면 forward), enteredSpace:(한자모드
  다음 후보), changeLanguage:. 미처리→makeCompleteChar: 후 [sender doCommandBySelector:].
- 상태변화 커밋 패턴(실측): setActivated:sender:(비활성→makeCompleteChar:),
  cancelInput:conversation:, markedTextWillBeAbandoned:conversation:,
  markedTextSelectionChanged:sender:conversation:(hasMarkedText+선택범위→커밋),
  activeConversationWillChange:...(이전 sender hasMarkedText→커밋) 모두
  makeCompleteChar: 로 조합 확정. wantsToInterpretAllKeystrokes=NO(자판 바인딩만).
- 진행표: [OK] insertText:sender:conversation:, displayString:, makeCompleteChar:,
  doCommandBySelector:sender:conversation:, +initialize, init,
  applicationDidFinishLaunching:, wantsToInterpretAllKeystrokes, setActivated:sender:,
  cancelInput:conversation:, markedTextWillBeAbandoned:conversation:,
  markedTextSelectionChanged:sender:conversation:, activeConversationWillChange:...
- 한자(실측): `hanjaConvert:`(START_MODE 첫 진입에 [fep inputString]→hanjaInputString
  포착; HanjaConverter 지연생성·setDispatcher:/setTextInput:; 길이1=문자별 convertChar:
  index:hrepeatCount-1 / 그 외 convertWord:index:hrepeatCount; applyHanja:isComplete:0
  + hanjapanel:index:), `applyHanja:isComplete:`(조합중이면 fep 조합문자 치환→complete면
  makeCompleteChar: / 아니면 displayString:; 아니면 [textInput insertText:]+hrepeatCount=0).
- 앱/모드(실측): `changeIcon`(isTurnedOn→kor/engImage setApplicationIconImage:),
  `changeLanguage:`(0/1 프로그램적 한영전환+[fep setAutomata:]+changeIcon),
  `setMarkedText:selectedRange:`(빈 스텁 — marked는 sender에 직접 설정),
  `senderDidResignActive:`(fep 비조합시 setWorkingInit 정리).
- 환경설정/메뉴(실측): `configPreferenceValue`(NSUserDefaults objectForKey:→isEqual:/
  intValue 로 initState/hanjaArea/inputUnit/hanjaRepeatCount/hanjaConversation 로드,
  [fep setInputUnit:] 반영), `showPreference:`(Preference 지연생성+showUI),
  `unicodeFromKS:`/`ksFromUnicode:`(fep 위임).
- 진행표: [OK] ...(위) + configPreferenceValue, showPreference:, unicodeFromKS:,
  ksFromUnicode:. **Dispatcher 실질 로직 완결.**
  + canBeDisabled(YES)/hasMarkedText(YES)/unmarkText(빈 스텁)/senderDidBecomeActive:
  (비조합 시 setWorkingInit) + terminate:(quitMenu면 종료확인 알림→super/아니면 fep)/
  applicationWillBecomeActive:(빈)/dealloc(eng·korImage release). **→ Dispatcher 완결.**
- NOTE(configPreferenceValue): 기본 키/비교값 문자열(off_5E048~) 정본 확정 필요.
- NOTE(한자 미결 셀렉터): hanjaConvert: 5794D/57951/57955/57959/57965/pool,
  applyHanja: 576D6(fep 치환).
- NOTE(미결 셀렉터): makeCompleteChar: 57EAE/57EB2/57EB6, init 581AB/preference·
  아이콘경로, applicationDidFinishLaunching: 5734A/572DA, +initialize 기본값 7쌍.
- NOTE: makeCompleteChar:의 57EAE(sender 무인자)·57EB2(sender bool)·57EB6
  (hanjaConverter setter) 셀렉터 확인 필요.

## 2e. HanjaConverter — 한자 변환 (실측 — src/HanjaConverter.m 복원 완료)
메서드(14): init, setDispatcher:, setResp:, _initMatrixWithFont:, frontHanja:,
orderOutPanel:, hanjapanel:index:, hanjaWithString:index:, hanjaWithStrings:index:,
findWord:index:, clearWordArray, changeHangul:, changeHanja:,
browser:createRowsForColumn:inMatrix:.
- **SMcode_Hanja_Table 구조(실측·검증):** 114 ushort/행 × 484행. 행[0]=한글 KS
  코드(키), 행[1..113]=그 독음의 한자 KS 후보(0 종료). 검증: 첫 행 키 유효
  KS/조합코드, 행0 후보 29개 후 0종료. → extract_tables.py에 추가(data/, gitignore,
  총 29표). **사전 데이터는 소스 비내장(정본 추출).**
- `hanjaWithString:index:`(실측): 한글자→[dispatcher ksFromUnicode:]→표에서 키
  행 검색(최대 484)→후보 수 카운트(0종료)→idx%수 선택→[dispatcher unicodeFromKS:]
  →1글자 NSString. cell_pos=idx%수.
- 단어 변환(실측, **외부 사전**): `hanjaWithStrings:index:`(preference 사전 경로
  변경 시 systemDictionary 재로드→findWord:index:로 wordArray 구성→objectAtIndex:
  idx%count), `findWord:index:`(외부 사전을 **중첩 딕셔너리=트라이**로 순회: 작업
  노드를 루트에서 시작해 각 글자로 setDictionary: 하위노드 하강, 끝에서 종료키
  off_5E36C의 후보 배열; 실패 시 wordArray=nil). 외부 사전은 외부 파일(비재현).
- UI(실측): `hanjapanel:index:`(idx>0: wordpanel 앞으로+브라우저 24pt 폰트·리로드·
  현재후보 선택; idx==0: 첫글자 KS→frontHanja: 단일자 경로), `changeHanja:`(선택 셀
  stringValue→[dispatcher applyHanja:isComplete:1] 확정), changeHangul:(거의 빈 본문),
  clearWordArray(wordArray=nil).
- init(Hanja.nib 로드+dict/path/cell 초기화), orderOutPanel:(panel·wordpanel 숨김),
  frontHanja:(KS코드 행 검색+매트릭스 채움+패널 표시) 복원.
- 진행표: [OK] hanjaWithString:index:, hanjaWithStrings:index:, findWord:index:,
  hanjapanel:index:, changeHanja:, changeHangul:, clearWordArray, setDispatcher:/setResp:,
  init, orderOutPanel:, frontHanja:.
  [TODO] _initMatrixWithFont:@0x8950, browser:createRowsForColumn:inMatrix:@0x91c8,
  fillMatrixRow:(frontHanja:의 55A5A). (AppKit 브라우저 플러밍 — nib 검사 단계 확정 권장.)
- ※ Dispatcher hanjaConvert: 셀렉터 정정 완료(setResp:/hanjaWithString:index:/
  hanjaWithStrings:index:).

## 2f. Preference — 환경설정 (실측 — src/Preference.m 복원 완료)
메서드(6): init, showUI, loadInputManagerInfo, setPopUpWithKeyBindingDictionaray:andKey:
(원본 오타), indexWithKey:, changeAttributeType:.
- `showUI`(UI 갱신+[panel orderFront:]), `indexWithKey:`(자판 액션키→인덱스 0~3,
  4개 액션문자열 compare:; 5E1C8→0/5E1D4→1/5E1BC→2/5E1E0→3),
  `setPopUpWithKeyBindingDictionaray:andKey:`(자판사전에서 물리키 값 읽어 engKor/
  hanja/inlineWin 팝업에 indexWithKey: 인덱스 선택 — indexWithKey:의 짝).
- `loadInputManagerInfo`([STRUCT] 대형): NSUserDefaults+설치 입력기 Info 로드→자판
  바인딩 4키 팝업 반영·DisplayName _imMap 저장·한자사전 경로→dictionaryPathTF/PU·
  initState/hanjaArea/inputUnit(setState:)·hanjaRepeatCount/hanjaConversion(setIntValue:)·
  배경색(colorWell)·[panel display]. ~40 msgref·다수 키/경로 문자열 미확정(구조만 복원).
- 진행표: [OK] showUI, indexWithKey:, setPopUpWithKeyBindingDictionaray:andKey:.
  [STRUCT] loadInputManagerInfo. [TODO] init, changeAttributeType:.

## 2g. 부분 컴파일 검증 (실기 cc -ObjC -c) — ★통과
`tools/build-check.sh`로 재구성 src/*.m + data/automata_tables.m 를 실기 OPENSTEP
cc 2.7.2.1 로 각각 컴파일. **8개 클래스 + 데이터표 전부 .o 생성 성공(오류 0).**
남은 것은 NOTE 미확정 메서드의 동적 디스패치 경고뿐(id/타입 수신자 → 경고, 컴파일 통과).
검증이 잡아 고친 실결함 5:
1. `out` 파라미터명 = ObjC DO 타입한정자 키워드 → parse error. make_bok*(3): out→dst.
2. FrontEnd.m 에 NoCheckAutomata 미import → setAutomata: undeclared. import 추가.
3. imProcessBS 헤더 void인데 Dispatcher가 반환값 사용 → void-not-ignored. int 로 정정.
4. HanjaConverter.m 에 Preference 미선언 → [Preference alloc] undeclared. @class 추가.
5. Automata.h reduceCount 선언 void ↔ 구현 unsigned short 불일치 → void-not-ignored.
   헤더를 unsigned short 로 정정(바이너리 반환형과 일치).
→ **재구성 소스의 시그니처·extern·헤더 정합성 실측 검증됨.** 완성 문자열 표시
(FullKorean)·nib 연결·NSInputServer 등록은 이후 동작 오라클(실기 GUI).

## 2h. 전체 링크 빌드 + 구조 비교 (실기) — ★통과
`tools/build-link.sh`로 8클래스 + data + `src/glue.m`(main·전역 fep/hanjaInputString·
draw 헬퍼 기능스텁)을 `cc -ObjC ... -framework AppKit Foundation`으로 링크 →
**SMHangul 실행파일 생성(384,420B, Mach-O i386, 미해결 심볼 0).** 정본 411,124B.
- glue 수정: dpsclient/wraps.h 제거(PS 단일op은 AppKit 경유), NXPing 제거.
- **구조 비교(otool -oV):** 잔여 35 메서드 상세화 후 재구성 __OBJC method_name
  **111 / 정본 119(93%)** — 8클래스 전부 상세화 완결, .app 번들 링크. (초기 84→111.)
  남은 8 차이는 일부 [STRUCT] UI 상세(loadInputManagerInfo 등)·카테고리성 항목 수준.
- (이력) 초기 링크 시점 재구성 __OBJC method_name 84 / 119(71%).
  8개 클래스 전부 존재(링크 성공이 보장). 차이 35 = [TODO]로 남긴 UI 플러밍·
  trivial 게터(HanjaConverter init/_initMatrixWithFont:/frontHanja:/orderOutPanel:/
  browser:, Preference loadInputManagerInfo 상세/init/changeAttributeType:, Dispatcher
  canBeDisabled/hasMarkedText/unmarkText/senderDidBecomeActive:/terminate:/dealloc,
  FrontEnd 커서·모드·문자열변환·initWithHanja:/dealloc, CvtField dealloc 등).
- 산출: `extracted/SMHangul.rebuilt.objc.txt`(재구성 __OBJC 덤프).
→ **핵심 입력기(조합·IM 프로토콜·한자) 완결, 링크 가능. 남은 35 메서드로 완전 등가.**

### 리소스(이미지·nib) 사용 — ★.app 번들 조립 완료
- **이미지 참조 실측:** off_5E0F0="eng"(len3), off_5E0FC="kor"(len3) →
  `engImage=[NSImage imageNamed:@"eng"]`, `korImage=[NSImage imageNamed:@"kor"]`
  (initByReferencingFile: 아님 — Dispatcher init 정정). 번들 Resources 의 eng.tiff/
  kor.tiff 를 이름 조회.
- **`tools/build-app.sh`**(실기): 실행파일 링크 + 정본 Resources(eng/kor/SMI.tiff +
  English.lproj nib 6개 + Info-nextstep.plist) 복사 → `SMHangul.app`(실행파일 384420B
  + Resources) 조립. **원본 이미지·nib 를 실제로 사용**(NSImage imageNamed:·nib 로드).
  NeXT mkdir -p 없음 → 단계별 mkdir.
- 정책: 벤더 리소스(이미지·nib·데이터표)는 정본에서 가져와 번들 조립에만 사용,
  **리포 비커밋(gitignore)**. 소스에 내용 비재현.

## 3. 링크·진입점 (실측)
- 클래스 참조: NSInputServer, NSApplication, NSApplicationMain, NSTextField,
  NSPanel, NSUnarchiver/NSArchiver, NSUserDefaults, NSFileManager, NSOpenPanel,
  NSColor/NSFont/NSImage, DPS(_DPSGetCurrentContext, _PSmoveto/_PSrlineto/
  _PSsetgray/_PSstroke = 캐럿 드로잉).
- 진입점: `start`→`_main`(0x92ec). `_drawStart/_drawEnd/_clearDraw`(캐럿 PS 그리기).
- 등록: NSInputServer(§PLAN §2, SDK HexInputServer.m:31 패턴).

## 4. 다음(Phase 1 수직 슬라이스)
IM 생명주기 실증 우선. 툴체인은 OnionPlayer(AppKit 앱)로 이미 검증됨 → 고유
불확실성은 NSInputServer 등록/활성화·nib 언아카이브. SDK HexInputServer 빌드로
NSInputServer 경로부터 실증.

## 5. Hang 근본원인·수정 (2026-08-10) — NSInputServer 생성 누락
- **증상:** 클라이언트(TextEdit)에서 입력기 선택 시 hang. 델리게이트 진입 프로브
  (SMHPROBE) 전무 → 델리게이트 도달 이전, **연결/등록 단계**에서 걸림.
- **실측 근본원인:** 원본 exe엔 `initWithDelegate:name:` 셀렉터 + `NSInputServer`
  참조 존재, **재구성 exe엔 0개** → 우리가 NSInputServer를 **한 번도 생성 안 함**.
  즉 서버가 연결을 vend하지 않아 클라이언트가 이름으로 붙을 때 무한 대기.
- **정본 레퍼런스 확보:** `/mnt/MAMEALL/.../hangul/JapaneseDeveloper.pkg` 안
  `NextDeveloper/Examples/Kanji/HexInputServer` (동작하는 표준 입력서버).
  - `HexInputServer_main.m`: `[HexInputServer new]` → `for(;;){[[NSRunLoop
    currentRunLoop] run];}` (+포트예외 무시). NSApplication 아님(NSObject).
  - `HexInputServer.m:29-32` `+new`: `self=[[HexInputServer alloc] init];
    return [[NSInputServer alloc] initWithDelegate:self name:SERVERNAME];`
    (SERVERNAME == Info ConnectionName).
  - `HexInputServer.h`: 델리게이트 프로토콜 전체 목록 → 우리 Dispatcher 12개
    시그니처와 1:1 대조 일치(conversation:(long)/(NSRange)/(SEL) 인코딩 동일).
- **수정:** `-[Dispatcher init]` 끝(엔진·이미지 셋업 후)에서 생성:
  `inputServer = [[NSInputServer alloc] initWithDelegate:self
     name:@"SoftMagicKoreanFrontendProcessor"];` (retained 전역, glue.m).
  근거: NSPrincipalClass=Dispatcher → NSApplicationMain이 sharedApplication으로
  -init 을 **반드시 호출**. NSInputServer 생성은 NSApp에 의존하지 않음(정본은
  NSApplication 없이 생성). 이후 [NSApp run] runloop이 vend된 연결을 서비스
  (정본의 [NSRunLoop run]과 동일 순서 — runloop 진입 이전 생성).
- **빌드 검증:** 링크 402820B. `strings`: initWithDelegate=1(이전 0),
  SoftMagicKoreanFrontendProcessor=1, NSInputServer=1. `SMHPROBE inputServer=%@`
  로그로 등록 성공(nil 여부) 확인 예정.
- **codex 교차검토(재검증):** 유효 지적 2건만 채택 —
  (1) **동일 이름 중복 등록 시 nil** → 구 프로세스 잔존(이전 2개 관측) 시 재등록
      실패 → **클린 단일 기동(재부팅) 필수**. (2) nil 반환 로그(반영).
  나머지(-init 타이밍/시그니처)는 정본·실측으로 반박·불필요 확인.
- **미해결(다음 사이클):** (2) Preference OK 미닫힘(정본 IMPreferences.m 확보 —
  writeDefaults:/writeToUserDefaults:/writeGlobalDefaults:/revertDefaults: 패턴;
  단 정본 OK는 패널을 닫지 않음 → 원본 Preference.writeDefaults:@0x83e4 디컴파일로
  닫기 동작 확인 필요), (3) 한/영 상태 이미지 미표시(hang 해소 후 재평가 —
  배경 서버라 setApplicationIconImage 비가시 가능 → LazyPanel 상태창 경로 조사).

## 6. 자모 표시 버그 — ks[] 추출 오프셋 오류 (2026-08-10)
- **증상:** "한글은"(키 gksrmfdms) → "핏그응". "한" 조합 시 ㅎ→핑→핏.
- **분리 진단(테스트 하니스):**
  - `tools/tmp/autotest.m` — Automata에 키 직접 투입. 각 단계 EUC 코드 덤프.
    결과: g→ㅎ(a4be), k→하(c7cf), s→**한(c7d1)**, r→ㄱ, m→그(b1d7),
    f→**글(b1db)**, d→ㅇ, m→으, s→**은(c0ba)**. **조합·search_code·EUC 완전 정확.**
  - `tools/tmp/disptest.m` — `unicodeFromKS:` 검증. 수정 전: 한→d54f, 글→adf8,
    은→c735 (어긋남). → 버그는 조합이 아니라 **EUC→표시 변환(ks[])**.
- **원본 실측(IDA 0x540c):** `unicodeFromKS(c)=*(WORD*)&stru_20D0.segname[2c-8]`.
  &stru_20D0.segname = 0x20D0+0x10 = 0x20E0 → 유효 base = **0x20D8**(0x20D0 아님).
  ks[0](code 0x8144) VM = 0x20D8+2·0x8144 = **0x12360**. 우리 추출은 0x12358(8B=
  4코드 빨랐음) → `unicodeFromKS(c)=correct(c−4)`, 유니코드 행 간격 탓에 들쭉날쭉.
- **판명:** 표시는 벤더 "FullKorean"이 아니라 **표준 유니코드**. 원본 ks 실측:
  가0xB0A1→AC00, 하0xC7CF→D558, 한0xC7D1→D55C, 글0xB1DB→AE00, 은0xC0BA→C740.
- **수정:** `extract_tables.py` ks (0x12358,32191) → **(0x12360,32187)**
  (개수는 Uni_to_FullKorean_Table 0x21ED6 직전까지). data/ 재생성 후 disptest 재실행:
  한→d55c, 글→ae00, 은→c740, 가→ac00, 각→ac01 **전부 정답**.
- **검증된 무관 함수:** `unfinishedUnicode(c)=c−0x7370`(일치),
  `ksFromUnicode(c)=Uni_to_FullKorean_Table[c]`(0x21ed6, 오프셋 없음 — 일치).
- 재빌드(402880B)·SMHangul.real 교체·구 서버 kill 완료 → 재선택 시 반영.

## 7. space 소실 버그 — enteredSpace: 특수처리 누락 (2026-08-10)
- **증상:** "한글은 아주 좋습니다" → "한글은아주좋습니다"(공백 소실). input unit=word.
- **경로:** KeyBindings `" " = "enteredSpace:"` → 클라이언트가 doCommandBySelector:
  enteredSpace: 를 서버로 전달. enteredSpace: 는 SMHangul 고유 셀렉터.
- **재구성 버그:** enteredSpace:(非한자)를 특수처리 없이 generic forward
  (`[sender doCommandBySelector:@selector(enteredSpace:)]`)로 보냄 → 클라이언트가
  모르는 셀렉터라 무시 → 공백 소실. **원본 버그 아님(우리 누락).**
- **원본 실측(IDA 0x6934):** enteredSpace: & !HANJA_MODE →
  `[self makeCompleteChar:sender]` 후 `[sender insertText:@" "]`(off_5E120=@" ",
  paInserttext, loc_69BB). 즉 forward가 아니라 **실제 공백 삽입**.
- **수정:** Dispatcher doCommandBySelector: enteredSpace: 非한자 분기에
  `[self makeCompleteChar:sender]; [sender insertText:@" "]; return;` 추가.
  (insertNewline: 등 표준 셀렉터는 forward로 정상 — 특수처리는 enteredSpace: 만.)
- 재빌드(402888B)·교체·구 서버 kill 완료.

## 8. Preference OK 미닫힘 — 분석 및 복원 (2026-08-10, §9에서 완료)
- **증상:** Preference 창에서 OK 클릭해도 안 닫힘.
- **원본 분석(IDA):**
  - nib(data.classes) Preference ACTIONS = changeAttributeType:/revertDefaults:/
    setPath:/updateDictionaryPopUpButton:/writeDefaults:/writeGlobalDefaults:.
    **close/performClose 액션 없음.**
  - writeDefaults:(0x83e4)·writeGlobalDefaults:(0x8314) 둘 다 유저디폴트 기록
    (setPersistentDomain:forName: + synchronize) 후 release — **패널 안 닫음.**
  - showUI(0x7410) = loadInputManagerInfo + [panel orderFront:] (비모달).
  - **결론: 원본도 적용 버튼으로 안 닫고, 타이틀바 닫기 상자로 닫는 설계.**
- **우리 결함:** Preference 액션 메서드 대부분 미구현(revertDefaults:/setPath:/
  updateDictionaryPopUpButton:/writeDefaults:/writeGlobalDefaults:)+loadInputManagerInfo
  스텁 → nib "Could not connect action" → 버튼 死(적용조차 안 됨).
- **복원 대상(원본 주소):** revertDefaults:(0x7d58)·writeToUserDefaults:(0x7d78)·
  writeGlobalDefaults:(0x8314)·writeDefaults:(0x83e4)·updateDictionaryPopUpButton:
  (0x84d8)·setPath:(0x8644)·dictionaryName(0x86d4)·dealloc(0x87cc)·
  loadInputManagerInfo(0x744c)·setPopUpWithKeyBindingDictionaray:andKey:(0x7b50).

## 9. Preference 복원 완료 + OK 개선 (2026-08-10)
- **faithful 복원(원본 주소)**: revertDefaults:(0x7d58)/writeToUserDefaults:(0x7d78)/
  writeGlobalDefaults:(0x8314)/writeDefaults:(0x83e4)/updateDictionaryPopUpButton:
  (0x84d8)/setPath:(0x8644)/dictionaryName(0x86d4)/dealloc(0x87cc)/loadInputManagerInfo
  (0x744c)/setPopUpWithKeyBindingDictionaray:andKey:(0x7b50)/indexWithKey:/init.
- **실측 문자열**: defaults 키 SMInitState/SMHanjaArea/SMInputUnit/SMHanjaRepeatCount/
  SMHanjaConversion/NSMarkedTextAttribute/NSMarkedTextColor; 값 English/Korean·
  None/Underline·Character/Word·Background/Underline; pref키 SMHanjaDictionaryPath·
  SMHanjaDictioanry(원본 오타)·SMHanjaDictionary; 자판키 keyDict={"^$ ","~ ","$ ","^ "," ",""};
  사전확장자 "dic". pref경로 ~/Library/Dictionary/SMInputManager.pref, 자판사전
  ~/Library/KeyBindings/SMHangul.dict.
- **원본 라운드트립 비대칭**(저장/로드 폴라리티 어긋남·pref dict 누수)은 원본 그대로
  재현하고 NOTE 표기(원본 버그 가능성). [INFER]: hanjaConversion 셀렉터·setPath
  NSOpenPanel 셋업·Underline 기본색.
- **[ENHANCE] 원본에 없는 개선(사용자 요청)**: confirmSavedAndClose — writeDefaults:/
  writeGlobalDefaults: 끝에서 NSRunAlertPanel("Preferences have been saved.") 모달 후
  [panel orderOut:] 로 패널 닫음. (원본은 적용 버튼이 저장만·닫기는 타이틀바 닫기상자.)
  문구는 실기 렌더 안전 위해 영문(소스 한글=UTF-8→EUC-KR 환경서 깨짐 우려).
- 빌드 412440B, SMHangul.real 교체.

> 절 10·11은 없다. 작성 중 번호가 건너뛰었고, 다시 매기면 이 문서를
> 가리키는 다른 곳(`HANDOFF.md` 의 §2g·§2h 등)이 깨지므로 그대로 둔다.

## 12. 연속 자음("ㅋㅋㅋ") 멈춤 — 원본 버그 수정 (2026-08-10)
- **증상:** "ㅋㅋㅋㅋ" 입력 시 첫 ㅋ 후 편집기 입력 멈춤. "ㅋ ㅋ ㅋ"(공백)은 정상.
- **원인(원본 버그, 충실 재현):** insertText:/displayString:/makeReplaceString:/
  hasMarkedText(항상 1)/automata 전부 원본과 **완전 일치** 확인(IDA 0x6a7c/0x69d0/
  0x4c6c/0x65f8). Word 모드에서 완성 안 되는 **단독 자모(호환자모 U+31xx)가 marked 에
  누적**(completeChar)되는데, 복수 단독 자모를 marked 로 두면 클라이언트가 멈춘다.
  공백 입력 시엔 makeCompleteChar 로 매번 커밋돼 누적 안 돼 정상. → **원본에 이미
  있던 버그.** (SMInputUnit 미설정=Word 모드 확인.)
- **수정([FIX]):** FrontEnd `finalizedIsJamo`(completeChar 전부 U+3130~U+318F인지)
  추가. Dispatcher insertText: 커밋 조건을 `inputUnit || [fep finalizedIsJamo]` 로 —
  **확정분이 단독 자모면 즉시 [sender insertText:] 로 커밋+drain**(marked 누적 회피,
  "ㅋ ㅋ"와 동일 결과). 완성 음절(U+AC00~)은 finalizedIsJamo=NO 라 Word 누적 유지.
- **트레이스 검증(worktest.m):** "zzz"→각 ㅋ 즉시 COMMIT, marked 자모 1개 유지;
  "gksrmfdms"(한글은)→finalizedIsJamo=0 전부, 누적 유지(정상). fat 재빌드·설치.

## 13. 오토마타 로직 정밀 검토 + codex 교차검토 (2026-08-10)
트레이스 실측 + codex 검토(정본/트레이스로 재검증). 조합 로직은 매우 견고 —
복모음/복종성/받침이월/복종성분해이월/ㅆ받침/무효조합분리/쌍자음/복모음BS 전부 정확.

**수정한 버그:**
- **[FIX] 백스페이스 초성-skip + 유령 자음** (FrontEnd.m imProcessBS): backCount 를
  "개수"로 오해해 backCount==1(=2자모 "가")에서 곧장 automata_init → 초성 상태 건너뜀
  (가→∅, 가→ㄱ→∅ 아님). 단독 초성(==0)에선 조합을 안 지워, 지운 뒤 다음 모음에
  초성이 되살아나는 **유령 자음**(ㄱ→BS→ㅏ = "가"). → backCount>0:reduceCount,
  ==0:automata_init(제거), <0:확정삭제 로 교정. 검증: 값→갑→가→ㄱ→∅, ㄱ→BS→ㅏ=ㅏ.
- **[FIX] completeChar[32] 오버플로** (FrontEnd.m makeReplaceString/makeInputNonAutomata):
  공백 없이 32+ 음절 연타 시 버퍼 초과(→afterString 손상). completeIndex<31 가드 3곳.
  검증: 가×40 → 31에서 캡, 오버런 없음.
- **[FIX] 방어 하드닝**: korean: 진입에서 a3>=128 또는 token>=5(제어문자)면 ASCII 통과
  (act_tbl/table OOB 방지). reduceCount count<=0 가드(back[-1] 언더플로 방지).
  (정상 경로엔 Dispatcher 필터로 도달 안 하지만 UB 제거.)

**버그 아님(codex 지적 확인):**
- `c % 0xFF`(FrontEnd.m:322): c<=0x7F 에서만 실행 → =c. 무해(제 초기 추정 철회).
- back[5] 충분(최대 index 4). search_code 매핑 정확(0x8861→0xB0A1 등). 둘 다 codex 동의.

**한계(버그 아님, 문서화):**
- **완성형 2350자 한계**: 왏/먮 등 KS X 1001 밖 음절은 조합 불가(분리). 완성형 인코딩의
  본질적 제약(원본 동일). 현대 유니코드 전체 조합이 목표라면 인코딩 교체 필요.
- **convertedToKSString: 미매핑 문자→NUL 절단**(legacy KS 변환 경로): 역표가 0인 문자
  입력 시 stringWithCString: 가 NUL에서 절단. 해당 경로에 미매핑 문자가 오면 발생 —
  현재 입력 흐름엔 도달 드묾. 필요 시 후속 하드닝.
- fat 재빌드·설치·재패키징 완료(3아치, 페이로드 22).

## 14. ★근본원인: Korean 입력이 NoCheckAutomata를 쓰던 문제 (2026-08-10)
- **증상:** "ㅋㅋㅋ"(연속 자음) 멈춤 + Hangul 모드 backspace 무동작. 조합 자체는 정상.
- **발견:** 진단 프로브(SMHBUG3 in Automata.korean:)가 Korean 입력 시 **안 찍힘** →
  실제 활성 automaton이 Automata가 아니라 **NoCheckAutomata**였음. `setAutomata:`가
  한/영 ON(setAutomata:1)에 NoCheckAutomata를 배정하고 있었다.
- **NoCheckAutomata의 한계(그 클래스가 활성일 때):** korean: case3(status1+자음)이
  `return 0`(연속 자음 무시), 백업 링 미사용(automata_init에 clearBackUp 없음,
  saveBackUp 안 함) → imProcessBS(backCount/reduceCount 기반) 무력. 이 둘이 정확히
  ㅋㅋㅋ 멈춤·backspace 실패의 원인.
- **수정:** FrontEnd `setAutomata:` 의 클래스 매핑을 교정 — **mode=1(Korean-ON)→
  Automata(완전한 2벌식), mode=0→NoCheckAutomata**. (이전 재구성이 두 클래스를 뒤바꿔
  배정.) Automata 는 복모음/복종성/받침이월/연속자음/백스페이스를 모두 올바로 처리(§12·§13
  실측 + 이 세션 트레이스). 스왑 후 SMHBUG3 정상 발화(Automata 활성)·백업링(cnt 증가)
  동작 확인, 사용자 실기에서 ㅋㅋㅋ·backspace·정상 조합 모두 확인.
- **의의:** §13의 오토마타 검토·수정(유령자음/초성-skip/오버플로/하드닝)은 전부 Automata
  대상이었는데, 스왑으로 Automata가 실제 활성 automaton이 되어 그 수정들이 이제 실효.
- 진단 프로브(SMHBUG/SMHBUG3)·로그 래퍼 제거, 클린 fat(3아치) 재빌드·설치·재패키징
  (페이로드 22, exe fat). SMHBUG 잔여 0.
