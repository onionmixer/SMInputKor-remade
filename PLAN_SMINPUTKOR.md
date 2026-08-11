# PLAN — SMInputKor-remade: OPENSTEP 한글 입력기 소스 복원

> 상태: v0.3 (2026-08-11). **복원 완료·실기 동작** — 8클래스·119메서드 복원,
> fat(i386/m68k/sparc) 빌드·`.pkg` 배포, 원본 버그 다수 수정, **세벌식(390/최종)
> 자판 지원 추가**(계획·기록은 `doc/KEYBOARD_LAYOUT_PLAN.md`). 재개는 `HANDOFF.md`.
> 성격: **소스 없는 i386 Mach-O 바이너리 → 소스 레벨 복원**(리버스 엔지니어링)
> 후, 실기 검증 기반의 버그 수정·기능 확장(remade). "관찰·복원"이 핵심.

## 0. 목표 & 범위

**Softmagic 한글 입력기(SMHangul)를 OPENSTEP 4.2 상에서 다시 빌드 가능한
Objective-C 소스로 복원한다.** 최종 성공 기준:
- 복원 소스를 실기 OPENSTEP에서 컴파일 → 정품과 **동작 등가**인 입력기 생성
  (2벌식/3벌식 한글 조합, 한자 변환, 기호 입력이 실사용 수준으로 동일).
- 부차: `SymbolInput`/`DingbatInput` 번들, `FullKorean.glyphgenerator`도 가능 범위 복원.

**비범위(현 단계):** 폰트 자체(Capri/Heisei/명조/고딕 outline·CID)는 복원 대상이
아님(바이너리 폰트 리소스 — 보존만). 재배포/라이선스는 §9 참조.

## 1. 확보 자산 (실측 인벤토리)

원본 패키지 6종을 `orig/`에 보존. 핵심 페이로드는 비표준 NeXT tar(필드가
offset 224, 체크섬 방식이 표준과 달라 GNU/BSD/OPENSTEP tar 모두 거부)라
**전용 추출기 `tools/nxpkg_extract.py`**를 작성해 해제(재사용 가능).

### 1.1 RE 대상 바이너리 (정품 설치본 = 정본, `extracted/live/`)
| 바이너리 | 크기 | 아키 | 역할 |
|---|---|---|---|
| `SMHangul.app/SMHangul` | 411,124 | Mach-O **i386**(thin) | 한글 입력기 본체 |
| `SymbolInput.bundle/SymbolInput` | 95,800 | i386 | 기호 입력 번들 |
| `SymbolInput.bundle/DingbatInput` | 160,588 | i386 | 딩벳 입력(예제 소스 존재!) |
| `FullKorean.glyphgenerator/Rulebook` | — | 데이터 | 글리프 생성 룰북 |

SMHangul 세그먼트: `__TEXT` 32KB(코드) / `__DATA` 344KB / `__OBJC` 16KB.
**__DATA가 큰 이유 = 한글 조합표·한자 사전(KS X 1001) 등 내장 테이블**(→ 코드가
아니라 추출 대상 데이터).

### 1.2 API 스캐폴드 (JapaneseDeveloper SDK 예제 소스, `extracted/jdev_sdk/`)
OPENSTEP 입력기 **공식 예제 소스 전체**를 확보(89파일). 이게 RE의 로제타스톤:
- `HexInputServer/` — **입력서버 클라이언트-서버 완전 예제**(`Client.[hm]`,
  `HexInputServer.[hm]`, `_main.m`). 입력서버 프로토콜의 정본.
- `DingbatInput/`, `HexInputBundle/` — 입력 번들 예제(우리 DingbatInput 대응).
- `IMPreferences/`, `IMViewApp/`, `strconv/`(UniversalString 변환) — 부속.
- 확인된 입력서버 프로토콜(HexInputServer.h): `setActivated:sender:`,
  `wantsToInterpretAllKeystrokes`, `doCommandBySelector:sender:conversation:`,
  `insertText:sender:conversation:`, `markedTextWillBeAbandoned:conversation:`,
  `markedTextSelectionChanged:sender:conversation:`, `cancelInput:conversation:`,
  `activeConversationWillChange:...`, `senderDid{Become,Resign}Active:`.

### 1.3 리소스 (복원 참고, RE 불필요 — `extracted/live/`)
- `SMHangul/KeyBindings/SMHangul.dict` — **자판 배열(2/3벌식 매핑)**.
- `.nib`(frontEnd/Preference/Symbol/Hanja/NEXTSTEP_·WINDOWS_SMHangul) — UI 구성.
- `Info`, `SMHangul.rc`, `Localizable.strings`, `eng/kor/SMI.tiff`.
- Foundation `CharacterSets/{EUCToUnicode-L,UnicodeToEUC-L,CharacterSets}.data`
  — EUC-KR↔Unicode 변환표(입력기가 참조).

### 1.4 아키텍처 참조 (JapaneseUser, `orig/`)
일본어 입력기 **Clare**(ClareFrontend.app + 입력서버) = SMHangul과 동일 구조
(`frontEnd.nib` 공통). 동작 모델 대조군으로 활용.

## 2. 아키텍처 이해 (실측 기반)

SMHangul = **입력서버(NSInputServer) 델리게이트 + 조합엔진** 모델(HexInputServer
예제와 동형). 링크: AppKit / Foundation / System 만(사설 입력 프레임워크 없음).
등록 API 실증(SDK): `[[NSInputServer alloc] initWithDelegate:self name:...]`,
이름 `SoftMagicKoreanFrontendProcessor`(Info), 부팅 시 `SMHangul.rc`가 백그라운드
기동. ObjC 메타데이터로 확인한 **8개 클래스(=원본 .m 8개), 총 119 메서드**:

> **주의(교차검토로 정정):** 아래 상위클래스는 **바이너리 __OBJC의 실제
> super_class 포인터를 페어링해 확정**한 값이다(초기 순서기반 추정에서 Dispatcher/
> FrontEnd가 뒤바뀌어 있었음 — nib data.classes와도 일치 확인). §10 참조.

| 원본 모듈 | 클래스 : 상위 | 역할(실측) | 복원 난이도 |
|---|---|---|---|
| `Dispatcher.m` | **Dispatcher : NSApplication** | **앱 객체 + NSInputServer 델리게이트**(insertText:sender:conversation: 등 IM 프로토콜, showPreference:, quit/아이콘) | ★★★ 高 |
| `FrontEnd.m` | **FrontEnd : NSObject** | **한글 조합 엔진/컨트롤러**(imProcessEvent:, imProcessBS, makeReplaceString:, ksFromUnicode:, unicodeFromKS:, unfinishedUnicode:, convertedToKSString:length:, setAutomata:, hanjaProc:) | ★★★ 高 |
| `Automata.m` | Automata : NSObject | **자모 조합 상태기계**(초/중/종성) | ★★★ 高 |
| `NoCheckAutomata.m` | NoCheckAutomata : Automata | 무검사 조합(모드 변형) | ★★ |
| `HanjaConverter.m` | HanjaConverter : NSObject | 한자 변환(**외부 사전 파일** 조회) | ★★ |
| `CvtField.m` | CvtField : NSTextField | 조합중 텍스트 표시 필드 | ★ |
| `LazyPanel.m` | LazyPanel : NSPanel | 후보/한자 패널(지연생성) | ★ |
| `Preference.m` | Preference : NSObject | 환경설정(사전 경로 등) | ★ |

**실측 3계층 파이프라인:** Dispatcher(NSApp, NSInputServer 델리게이트, 키/이벤트
수신) → FrontEnd(NSObject, 조합 로직 + KS↔Unicode 변환) → Automata(자모 상태기계).
즉 조합의 두뇌는 FrontEnd이고 Dispatcher는 IM 프로토콜 경계다.

### 2.1 핵심: Automata 클래스 (실측 ivar/메서드)
instance_size 0x74(116B), 24 ivar. ivar가 한글 조합 상태를 그대로 드러냄:
`token, action, status, count, cho, jung, jung1, bokmo, jong, jong1, bokja,
ret_flag, rest_flag, jaso_flag, bokjaeum, asc_code, unfn_code, comp_code,
jaso_temp, comb_code, save_jong, save_jong1, finishRest, back`.
메서드: `search_code:, make_bokmo:::, make_bokjaeum:::, make_bokja:::,
make_two:::, isFinishAndRest, restFlag, returnFlag, clearBackUp, backCount,
reduceCount, savePrevBack, ...`.
→ 초성(cho)/중성(jung,복모음 bokmo)/종성(jong,복자음 bokja) 결합 상태기계.
`NoCheckAutomata`는 이를 상속해 조합 규칙 검사만 완화한 변형(예: 옛한글/자유조합).

### 2.2 Dispatcher (실측: NSApplication + NSInputServer 델리게이트)
`-[Dispatcher wantsToInterpretAllKeystrokes/setActivated:sender:/
doCommandBySelector:sender:conversation:/insertText:sender:conversation:/
markedTextWillBeAbandoned:conversation:/markedTextSelectionChanged:sender:
conversation:/cancelInput:conversation:]` 구현 확인 = **NSInputServer의
델리게이트 프로토콜**. nib(NEXTSTEP_SMHangul) 아웃렛 iconView/preference/
quitMenu + action showPreference: → 앱 객체 역할도 겸함. 클라이언트별 상태는
sender+conversation로 키잉(HexInputServer 예제 패턴). HexInputServer 예제가
이 클래스의 직접 대조군.

### 2.3 FrontEnd (실측: 조합 엔진 — 두뇌)
NSObject. 아웃렛 cvtField/cvtWin(조합중 표시). 조합 파이프라인 메서드:
`imProcessEvent:`(이벤트 처리), `imProcessBS`(백스페이스 분해), `makeReplaceString:`
(marked/replace 문자열 생성), `ksFromUnicode:`/`unicodeFromKS:`/`unfinishedUnicode:`/
`convertedToKSString:length:`(**KS↔Unicode 변환**), `setAutomata:`(오토마타 주입),
`hanjaProc:`/`initWithHanja:`(한자 연동), `makeInputNonAutomata`. Dispatcher가
받은 키를 FrontEnd가 Automata로 조합하고 marked text/확정 문자열을 만든다.

## 3. RE 방법론

### 3.1 이 작업이 유리한 이유(실측)
- **Objective-C = 반(半)자기문서화 바이너리.** 클래스명·상위·ivar(이름/타입/
  오프셋)·셀렉터·**원본 .m 파일명**까지 __OBJC에 평문 보존. 즉 **인터페이스
  (.h)는 사실상 공짜로 재구성**되고, 우리가 복원할 건 **메서드 본문 119개**뿐.
- **정본 실행 환경 보유.** 정품이 실기 OPENSTEP에 설치·동작 중 → 동적 분석
  (gdb-multiarch), 동작 대조, 입출력 관찰이 가능.
- **API 정본 보유.** SDK 예제 소스로 프레임워크 호출 관례가 확정적.

### 3.2 도구와 절차
- **정적**: Ghidra(MCP), IDA Pro(MCP) — i386 Mach-O 디컴파일. ObjC 셀렉터/
  send 흐름을 함수에 주석. 두 도구 교차(한쪽이 놓친 것 상호보완).
- **동적**: `gdb-multiarch`(i386). 라이브 디버깅 가능성은 §3.4 타당성 테스트로
  먼저 판정(원격 스텁 필요 — 무조건 되는 게 아님).
- **동작 오라클(프로토콜 트레이스)**: 최종 문자열만으론 불충분(marked text 수명·
  선택·취소·포커스·명령전달을 놓침). **SDK `IMViewApp`의 `IMView`**(이미
  `NSTextInput` 구현: setMarkedText:selectedRange:, unmarkText, hasMarkedText,
  conversationIdentifier)를 계기화해 **이벤트마다** 로깅: (test-id, 키/이벤트,
  conversation, 연산, insert UTF-16, marked UTF-16+range, selected range, 확정
  문서, 캐럿). 원본·복원본을 **분리된 청정 설정 환경**에서 돌려 **이벤트 단위
  diff**. 코퍼스: 모든 자모전이·복모음/복종성·백스페이스 역분해, 경계(자→모/
  모→자/비한글/문장부호/스페이스/리턴), 다문자 insertText(붙여넣기), 실제
  키바인딩 전부(토글/모드전환/한자/스페이스/개행/백스페이스/화살표), 선택변경·
  marked 포기·포커스/앱 전환·다중 conversation, 환경설정 교차곱(입력단위/인라인·
  비인라인/초기모드/한자설정).
- **데이터 추출(가정 금지 절차)**: "통째 덤프 후 재사용"은 각 후보가 포인터-프리
  고정포맷 상수표임을 입증한 뒤에만 안전. ① 실기 도구로 섹션별 파일오프셋/VM
  주소/초기화크기/zero-fill 기록, ② code→data xref 맵 작성(쓰기 있는 영역은
  상수표 후보 아님), ③ 명명 심볼앵커(`_jung_val`/`_jong_val`/`_Uni_to_FullKorean_
  Table`/`_SMcode_Hanja_Table`) 실주소·xref 확인(이름으로 크기 추정 금지),
  ④ 시작 직후 vs 워크로드 후 페이지 스냅샷 diff로 상수/스크래치 구분, ⑤ 소비
  코드에서 원소폭·인덱스연산·경계·센티넬·바이트오더 복원 → 버전/카운트 명시한
  리소스 포맷으로 export + 로더 작성. **한자 사전은 외부 파일**(`SMHanjaDictionaryPath`,
  `dictionaryWithContentsOfFile:`)이므로 실파일 확보가 우선.

### 3.3 메서드 본문 복원 절차(반복 단위)
1. 대상 클래스의 __OBJC 인터페이스 확정 → `.h` 재작성(ivar/셀렉터 그대로).
2. 각 method_imp 주소를 Ghidra/IDA로 디컴파일.
3. ObjC objc_msgSend 패턴을 셀렉터로 환원(어느 객체에 무슨 메시지인지).
4. 로직을 C/ObjC로 재서술 → `src/`에 작성.
5. **교차검증**: (a) 재컴파일 바이너리의 __OBJC/구조가 정본과 일치하는지,
   (b) 동작 오라클과 대조, (c) 필요시 gdb로 분기·상태 확인.

### 3.4 동적분석 타당성 테스트 (Phase 1에서 10분 선판정)
`gdb-multiarch`만으론 라이브 원격 디버깅이 성립하지 않음(타깃측 GDB remote
스텁 필요, 구형 OPENSTEP엔 호환 gdbserver가 보통 없음, 입력서버를 GUI/NSDO
호출 지점에서 멈추면 클라이언트 행/타임아웃 유발). 실효 옵션(현실성 순):
① 실기에서 네이티브 디버거로 서버 프로세스 attach(ptrace 허용 시, 주소/IMP
기준), ② 전체 QEMU VM이면 QEMU CPU GDB 스텁, ③ 호환 스텁 포팅(유지보수 각오),
④ **저침습 관찰 우선**(계기화 클라이언트/오라클, 정적 xref, 델리게이트 IMP
브레이크, 확인된 상태필드 워치포인트). **선판정**: attach/VM스텁으로
`-[Dispatcher insertText:sender:conversation:]`에 1회 브레이크→continue→해제 후
앱이 계속 쓸 만한지 확인. 실패하면 인터랙티브 디버깅이 아니라 트레이스 로깅
중심으로 설계.

## 4. 단계별 계획 (수직 슬라이스 우선 — 교차검토 반영 재편)

> 재편 이유(§10): "쉬운 클래스 먼저"는 함정 — 앱 객체·NSInputServer 생성·
> 서버 이름·입력기 발견·키바인딩 경로가 맞아야 "로드"가 의미를 가진다. 따라서
> **조합 로직(Automata) 복원 전에 IM 등록·생명주기·프로토콜 배선을 먼저 실증**한다.

### Phase 0 — 정찰·기반 (대부분 완료)
- [x] 패키지 해제(전용 추출기), 자산 인벤토리, 아키텍처·**정확한 클래스/상위 매핑**
  (super_class 포인터 페어링), SDK 예제 소스 확보, 등록 API(NSInputServer) 실증.
- [ ] Ghidra/IDA에 SMHangul 로드, ObjC 메타데이터 자동 주석, 함수 목록 확정.
- [ ] 심볼앵커(`_jung_val`/`_jong_val`/`_Uni_to_FullKorean_Table`/`_SMcode_Hanja_Table`)
  실주소·xref 확인. **외부 한자 사전 파일 위치·포맷**(`SMHanjaDictionaryPath`,
  `dictionaryWithContentsOfFile:`) 실기에서 확인.

### Phase 1 — ★수직 슬라이스: IM 생명주기 실증 (오토마타 복원 前 필수)
- [ ] **고유 이름의 최소 클론**: 원본과 다른 `ConnectionName`/설치경로로, SDK
  서버 기동 패턴(`NSInputServer initWithDelegate:name:` + 무한 런루프)만 구현.
- [ ] 모든 델리게이트 콜백을 로깅하고 가시적 marked/확정 문자 1개 반환.
- [ ] 설치→IM 환경설정에서 활성화→계기화된 IMView 클라이언트에서 키바인딩
  트리거→포커스/대화(conversation) 전환→종료/재기동까지 통과.
- [ ] **원본 nib 로드 실험**: 5개 nib(NEXTSTEP_SMHangul/frontEnd/Preference/
  Hanja/Symbol)를 아웃렛·액션·커스텀클래스명 갖춘 스텁 owner로 언아카이브,
  특히 **Hanja.nib의 외부 `DingbatInput` 의존** 검증.
- [ ] **동적분석 타당성 10분 테스트**(§3.4): 실패 시 트레이스 로깅 설계로 전환.
- [ ] 마일스톤: **등록·발견·활성화·콜백·UI 언아카이브가 되는 골격**이 실기에 뜬다.

### Phase 2 — 프로토콜 경계 & 조합 스캐폴드
- [ ] `Dispatcher` 복원(IM 델리게이트 프로토콜 전부: 활성화/marked text/취소/
  대화전환/키 전달). 통과기준: 트레이스 오라클과 프로토콜 이벤트 단위 일치.
- [ ] `CvtField`/`LazyPanel`/`Preference` 복원(표시·패널·설정, 사전경로 로딩).
- [ ] `FrontEnd` 골격(이벤트 배선·marked/replace 문자열·KS↔Unicode) 우선 결선.

### Phase 3 — 핵심 조합 로직
- [ ] `Automata` 복원(초/중/종성 결합 상태기계) — Dispatcher/FrontEnd와 **합동**
  으로(분리 불가). 동작 오라클로 자모전이·복모음/복종성·백스페이스 역분해 대조.
- [ ] `NoCheckAutomata`(Automata 차분 — 사용자 가시 모드일 수 있음, 오라클로 확정).
- [ ] **KS↔Unicode/조합표는 정본 알고리즘·데이터 사용**(현대 유니코드 한글
  알고리즘 대체 금지 — `_Uni_to_FullKorean_Table`·ksFrom/unicodeFrom 존재 =
  레거시 코드포인트 의존 가능성). §10.
- [ ] 마일스톤: **2/3벌식 한글 조합이 정품과 프로토콜·문자 수준 동일**.

### Phase 4 — 한자·기호
- [ ] `HanjaConverter` + **외부 한자 사전** 로딩·조회 결선.
- [ ] `SymbolInput`/`DingbatInput`(예제 소스로 상당부분 커버, Hanja 의존 해소).
- [ ] 마일스톤: 한자 변환·기호 입력 동작 등가.

### Phase 5 — 마감
- [ ] 전체 트레이스 오라클 회귀, 잔여 차이 제거, 문서화, (결정 시) 패키징.

## 5. 검증 전략 (예상없이 실측)
- **구조 등가**: 복원 재컴파일본의 __OBJC 클래스/ivar/셀렉터 레이아웃을
  정본과 diff(같은 인터페이스인지 기계적으로 확인).
- **동작 오라클**: 정품에 정해진 키시퀀스 입력 → 조합 과정·확정 문자열·한자
  후보를 기록한 표를 정답지로 삼아 복원본과 대조.
- **바이트 근접(가능한 곳)**: 데이터표(조합표/사전)는 정본에서 추출해 그대로
  사용 → 동일 결과 보장.
- Linux 측 사전 컴파일은 불가(AppKit/ObjC 런타임 의존) → **검증은 실기 중심**.

## 6. 디렉터리 구조
```
SMInputKor/
  orig/            원본 패키지 6종 + payloads/(내부 tar.Z 보존)
  extracted/       live/(정품 설치본=정본), jdev_sdk/(SDK 예제), *.txt(otool 분석)
  re/              Ghidra/IDA 프로젝트·디컴파일 산출·데이터 덤프·분석노트
  src/             복원 Objective-C 소스(클래스별 .h/.m) + 빌드 파일
  doc/             분석 문서·동작 오라클·복원 노트
  tools/           nxpkg_extract.py 등 유틸
  PLAN_SMINPUTKOR.md / README.md / HANDOFF.md(내부)
```

## 7. 리스크 & 미지수
- **동적 디버깅 경로 미확정**: 실기 원격 gdb(gdbserver/gdb-multiarch) 연결
  가능 여부 미확인 → 우선 정적+동작관찰로 진행, 필요 시 실기 로컬 gdb.
- **__DATA 테이블 포맷**: 한글 조합표/한자 사전의 내부 구조 해석 난이도.
  최악의 경우 표는 통째 추출해 리소스로 재사용(로직만 복원).
- **objc_msgSend 난독 아님**: 최적화로 인라인/꼬리호출 등 디컴파일 잡음 가능.
- **nib 재현**: UI는 nib 그대로 재사용 가능(복원 불필요)하나, 코드-아웃렛
  연결명이 일치해야 함(ObjC 셀렉터로 확인).
- **벌식/옛한글 규칙의 미묘함**: 오토마타 경계 케이스는 동작 오라클로만 확정.

## 8. codex 교차검토 (완료 — 결과는 §10)
계획을 codex(MCP)로 교차검토하고 **codex를 신뢰하지 않고 모든 지적을 실측
자산(바이너리 otool/nm/strings·nib data.classes·SDK 소스)으로 재검증**했다.
결과: codex의 실질 지적이 대부분 실측과 일치했고 **내 초기 클래스 매핑 오류를
드러냈다**. 반영 완료(§2·§3·§4 수정). 상세 §10.

## 9. 취급/범위 주의
- 대상은 **사용자가 정당하게 보유·설치해 사용 중인 소프트웨어**의 상호운용·
  보존 목적 복원(리버스 엔지니어링). 복원 소스는 RE로 파악한 동작을 **새로
  구현**한 결과물로 관리한다.
- 내장 데이터(한자 사전 등)·폰트·nib 등 원저작 리소스는 **재배포 시 라이선스
  검토가 선행**되어야 하며, 공개 방침은 별도 결정 전까지 로컬 보관.

## 10. codex 교차검토 결과 (실측 재검증 — 신뢰 아닌 검증)

codex의 각 지적을 바이너리 otool/nm/strings·nib data.classes·SDK 소스로 직접
재검증한 결과. **codex는 참고일 뿐, 아래 판정은 전부 실측 근거.**

| # | codex 지적 | 재검증 | 판정 |
|---|---|---|---|
| 1 | 내 클래스 매핑(Dispatcher/FrontEnd 상위)이 nib와 충돌 | super_class 포인터 페어링 + nib data.classes | **옳음. 내 순서추정이 오류** — 실제 `Dispatcher:NSApplication`, `FrontEnd:NSObject`. §2 정정 |
| 2 | FrontEnd가 조합 두뇌(imProcessEvent:/ksFromUnicode: 등) | method_imp 목록 | **확인.** §2.3 신설 |
| 3 | 명명 데이터표 심볼 존재 | strings | **확인** (`_jung_val/_jong_val/_Uni_to_FullKorean_Table/_SMcode_Hanja_Table`) |
| 4 | 한자 사전이 __DATA 내장이 아닐 수 있음(외부 파일) | strings(`SMHanjaDictionaryPath`,`dictionaryWithContentsOfFile:`,`/Library/Dictionary/SMInputManager.pref`) | **옳음. 내 "내장" 가정 부정확** — 외부 파일 메커니즘 존재. §3/§4 정정 |
| 5 | Hanja.nib가 외부 DingbatInput 의존 | Hanja.nib/data.classes | **확인.** Phase 1 nib 실험에 포함 |
| 6 | 등록은 NSInputServer initWithDelegate:name: | SDK HexInputServer.m:31 | **확인.** §2 반영 |
| 7 | "쉬운 클래스 먼저"는 함정, 수직 슬라이스 우선 | 방법론 | **타당. 채택** — §4 재편(IM 생명주기 실증을 오토마타 前에) |
| 8 | 오라클은 최종문자열 아닌 프로토콜 트레이스(IMView 계기화) | SDK IMView가 NSTextInput 구현 확인 | **타당. 채택** — §3.2 |
| 9 | gdb-multiarch 원격은 스텁 필요, 10분 선판정 | (미확인 — 실기서 판정 예정) | **타당. 채택** — §3.4 |
| 10 | 현대 유니코드 한글 알고리즘 대체 금지(레거시 KS) | ksFrom/unicodeFrom + Uni_to_FullKorean_Table 존재로 개연성↑ | **경계. 채택** — 정본 데이터/알고리즘 사용(§4 Phase3) |

**메타 교훈:** codex를 신뢰하지 않고 재검증했더니, 정작 **내가 검증 없이 순서로
추정했던 클래스 매핑이 틀렸음**이 드러났다(Dispatcher/FrontEnd 역할 반전). 원칙
"예상없이 실측"은 codex뿐 아니라 나 자신의 추정에도 적용된다 — §2 매핑은 이제
바이너리 super_class 포인터로 확정.

**codex 대비 미채택/유보:** 없음(실질 지적이 모두 실측과 정합). 단 codex의 표현
중 추정("likely","believed")은 §3.4·§4에서 실기 확인 과제로 남겨 둠.
