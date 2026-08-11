# SMHangul Preference 기능 완성 작업계획

원본 SMHangul 의 Preference 옵션 상당수가 **저장은 되나 실제 동작에 반영되지 않는**
미완성 상태다(원본 버그/미구현). 사용자 승인(“원본에 미구현이면 우리가 구현”)에 따라
각 옵션이 실제로 역할을 하도록 구현한다. 본 문서는 실측 근거·구현 계획·검증·리스크를
정리하고, 이후 codex 교차검토(불신·재검증)를 거친다.

정본 IDA 세션: 649e22b5 (extracted/live/SMHangul/SMHangul.app/SMHangul, 411124B).

## 0. 실측 요약 (측정 자료)
### 저장측 — `-[Preference writeToUserDefaults:]` (0x7d78)
- keybinding 팝업: `engKorSelectPopUp/inlineWinSelectPopUp/hanjaSelectPopUp` →
  `indexOfSelectedItem`(0x5683a) → `keyDict[idx]` → `_imMap` → ~/Library/KeyBindings/
  SMHangul.dict 기록. **정상.**
- `initState/hanjaArea/inputUnit`: **`state`(0x5684e)** 로 읽어 두 문자열 중 택1 저장.
  - initState: state? "Korean"(off_5E2DC) : "English"(off_5E234), key "SMInitState"(off_5E228).
  - hanjaArea: state? "Underline"(off_5E288) : "None"(off_5E24C), key "SMHanjaArea"(off_5E240).
  - inputUnit: state? "Word"(off_5E2E8) : "Character"(off_5E264), key "SMInputUnit"(off_5E258).
  - ※ **버그 의심**: 이 컨트롤들은 라디오 매트릭스(English/Korean, None/Mark,
    Character/Word)인데 `-state`(=선택 셀의 on 상태=항상 1)로 읽으면 **어느 항목을
    골랐는지 구분 못함** → 항상 첫 분기값으로 저장될 가능성. (검증 필요: initState
    아울렛 실제 클래스가 NSMatrix 인지 2-state 버튼인지.)
- `hanjaRepeatCount`: `intValue`(0x5672e), <=0 이면 "3", key "SMHanjaRepeatCount"(off_5E270).
- `hanjaConversion`: 셀렉터 0x56852(=state? intValue? [INFER]), >=0 이면 key
  "SMHanjaConversion".
- `attributePopUp`: indexOfSelectedItem → "Underline"(off_5E288)/"Background"(off_5E30C),
  key "NSMarkedTextAttribute"(off_5E168); `colorWell` color → NSArchiver → "NSMarkedTextColor".
- 한자 사전: dictionaryListPU/dictionaryPathTF stringValue → ~/Library/Dictionary/
  SMInputManager.pref.

### 읽기측 — `-[Dispatcher configPreferenceValue]` (0x6418)  (시작 시 1회)
- SMInitState=="English" → initState=1; SMHanjaArea=="None" → hanjaArea=1;
  SMInputUnit=="Character" → inputUnit=1, `[fep setInputUnit:]`; SMHanjaRepeatCount/
  SMHanjaConversion → intValue.  ※ 우리 재구성은 이전에 **플레이스홀더 키**를 읽어
  아무 것도 반영 안 됐음 → 이미 실제 키로 수정(빌드 412456B 반영).

### 동작 사용처 (grep + 원본 확인)
- `initState`: applicationDidFinishLaunching: 에서 `initState==1 → 한글 ON`. **사용됨.**
- `inputUnit`: FrontEnd `setInputUnit:` 로 ivar 저장만, **어디서도 안 읽음(死, 원본도 동일).**
- `hanjaArea`/`hanjaConversion`/`hanjaRepeatCount`: ivar 저장만, **미사용(死).**
  (한자 탐색은 런타임 `hrepeatCount` 별도 사용, ±10 하드코딩.)
- `NSMarkedTextAttribute/Color`: NSGlobalDomain 저장 → **AppKit 이 marked text 표시에 사용.**

## 1. 확인된 문제 (우선순위)
1. **[FIXED] 키 불일치** — configPreferenceValue 플레이스홀더 키 → 실제 키(SM*)로 수정.
2. **[FIXED] 즉시 반영** — OK 후 `[NSApp configPreferenceValue]` 재호출 추가.
3. **라디오 선택 저장 오류** — initState/hanjaArea/inputUnit 이 `-state` 로 저장되어
   선택이 반영 안 될 가능성. → 실제 컨트롤 클래스 확인 후 올바른 접근자로.
4. **폴라리티 역전** — 예) Korean 선택 → "Korean" 저장 → configPref: "Korean"!="English"
   → initState=0 → 한글 OFF(영문 시작). end-to-end 뒤집힘. → 일관되게 교정.
5. **死 옵션 미구현** — Input Unit(Character/Word), Hanja Area(None/Mark),
   Hanja Conversion, Hanja RepeatCount 를 실제 동작에 연결.

## 2. 옵션별 구현 계획
### 2.1 Init State (English/Korean) — 초기 한/영
- 컨트롤 클래스 확인(NSMatrix vs 2-state). 저장을 selectedRow/selectedColumn 또는
  [[cell]tag] 로 교정(라디오면). 목표 매핑: **Korean 선택 → 시작 시 한글 ON**.
- 3지점 일관 교정: writeToUserDefaults(선택→"Korean"/"English"),
  configPreferenceValue(문자열→initState), applicationDidFinishLaunching(initState→모드).
  폴라리티 한 방향으로 정렬.
- 검증: 라디오 Korean 저장 후 재기동 시 한글 모드로 시작.

### 2.2 Input Unit (Character/Word) — 조합 확정 단위
- 제안 의미: **Word**(현행) = 완성 음절을 marked 버퍼에 누적, 공백/경계에서 일괄 확정.
  **Character** = 음절 완성 즉시 클라이언트에 확정 삽입, marked 는 조합중 음절만.
- 구현: FrontEnd 조합 파이프라인(imProcessEvent:/makeReplaceString:/makeCompleteChar:)
  에서 inputUnit==Character 이면 완성 음절을 즉시 [sender insertText:] 하고
  completeChar 누적 생략. inputUnit 은 이미 configPref 에서 [fep setInputUnit:] 로 주입됨.
- 리스크: 조합/커밋 흐름 변경 → 현재 정상 입력 회귀 위험. 별도 경로로 최소 변경.
- 검증: Character 모드에서 "한글" 입력 시 "한" 완성 즉시 확정, "글" 조합중.

### 2.3 Hanja RepeatCount — 한자 후보 페이지 크기
- 현재 moveUp/moveDown 이 ±10 하드코딩. → `hanjaRepeatCount`(>0) 로 대체
  (Dispatcher doCommandBySelector: moveUp/Down). 0/미설정 시 기본 10 유지.
- 검증: RepeatCount=5 저장 후 한자 패널에서 moveDown 이 5칸 이동.

### 2.4 Hanja Area (None/Mark) — [INFER] 의미 미확정 → **§10에서 구현**
- 후보 의미: 한자 변환 후보 표시를 marked(밑줄/영역표시) vs 패널. 실측 근거 부족.
- 계획: 원본에서 hanjaArea ivar 사용처 재확인(현재 없음). 의미 확정 전엔 보류하고
  사용자에 의미 질의 또는 최소구현(설정만 유지). **구현 착수 전 확인 필요.**

### 2.5 Hanja Conversion — [INFER] 의미 미확정 → **§10에서 구현**
- 저장 셀렉터 0x56852 미확정. hanjaConversion ivar 사용처 없음. 2.4 와 동일 — 보류/질의.

### 2.6 Marked Text Attribute/Color — AppKit 처리
- NSGlobalDomain 기록이면 AppKit 이 반영. 동작 검증만(밑줄/배경색 표시).

## 3. 검증 방법
- 헤드리스 하니스(tools/tmp/*.m)로 FrontEnd/Automata 단위 동작 확인(2.2/2.3).
- 실기 GUI 테스트(사용자): 각 옵션 변경→OK→즉시/재기동 반영 확인.
- 라디오 접근자·폴라리티는 원본 디스어셈블 재확인으로 근거 고정.

## 4. 리스크·원칙
- 정상 동작 중인 입력(hang/자모/space 수정 완료)에 회귀 금지 — 변경은 최소·격리.
- 원본 버그 교정은 [ENHANCE]/[FIX] 태그로 명시, 충실복원 부분과 구분.
- 의미 불명(2.4/2.5)은 추측 구현 금지 — 확인 후 진행.

## 5. codex 교차검토 (완료 — 결과는 §6)
- 계획의 타당성·누락·리스크 검토. **codex 결론은 불신하고 정본(IDA)·실측으로 재검증.**

## 6. codex 교차검토 결과 (정본으로 재검증 — codex 불신)
정본 loadInputManagerInfo(0x744c)/writeToUserDefaults(0x7d78) 재확인으로 검증:

- **[검증됨] 라디오 매트릭스 확정.** 읽기측(loadInputManagerInfo)은 initState/hanjaArea/
  inputUnit 을 `dword_57142`(인자 2개: row,col)= **selectCellAtRow:column:** 로 설정.
  즉 이들은 **NSMatrix 라디오**. 저장측(writeToUserDefaults)의 **`-state`(0x5684e)는
  선택을 못 잡는 원본 버그**. → 저장을 `[[m selectedCell] tag]` 또는 `[m selectedRow]`로.
- **[검증됨·fork 오류] fork 재구성의 loadInputManagerInfo 가 `[initState setState:]`(1인자)로
  복원 — 원본은 selectCellAtRow:column:(2인자).** → 재구성 수정 필요(정본 접근자로).
- **[검증됨] Init State 폴라리티 역전**(English→Korean ON). launch 분기는 그대로 두고
  저장/읽기 매핑을 교정(canonical: initState==1=한글 ON, "Korean"↔ON).
  ★ codex 지적대로 **4번째 지점 loadInputManagerInfo 라디오 선택도 폴라리티 교정 대상.**
- **[검증됨] NSMarkedTextAttribute 라운드트립 역전.** save: idx0→"Background",idx1→"Underline";
  load: "Underline"→idx0,else→idx1 → idx0 저장 후 로드하면 idx1. 원본 버그. 교정 필요.
- **[수용] Input Unit 구현 위치**: FrontEnd 에는 입력서버 sender 가 없어 insertText: 불가
  (codex 정확). → **Dispatcher insertText: 에서 확정분 drain 후 삽입, 잔여만 marked.**
  FrontEnd 에는 "확정분만 뽑는 API" 추가. **확정(finishRest/완성)된 텍스트만 커밋**
  (종성 이월 때문에 3자모 완성처럼 보여도 즉시 커밋 금지 — codex 정확).
  단 **의미 자체가 불확실**(입력단위 vs 한자변환 범위) — 트레이스 테스트로 특성화 후 확정.
- **[수용] RepeatCount→±10 추정 철회.** 저장 기본값 3 vs ±10 = 한자패널 10열 기하학일
  가능성 → 근거 부족. **보류.**
- **[수용] Hanja Area("None"/"Underline") 이름≠동작, Hanja Conversion 의미 불명 → 보류.**
- **[수용] writeGlobalDefaults 는 app 도메인 값에 가려질 수 있음**(standardUserDefaults
  우선순위). configPreferenceValue 가 읽는 실효 도메인 확인.
- **[수용] completeChar[32] 무경계 누적** → >31 음절 오버플로 가드 추가.
- **테스트**: Dispatcher 가짜 sender 로 setMarkedText:/insertText: 호출 시퀀스 검증 +
  라디오 저장/재열림/재기동, 두 도메인, 종성이월, 백스페이스, 공백/문장부호, 모드전환.

## 7. 단계별 진행(확정)
- **Phase 1(최우선·저위험)**: 라디오 매트릭스 접근자 교정(저장 selectedRow/tag +
  loadInputManagerInfo selectCellAtRow:column: 정본 복원) + Init State/attr 폴라리티 교정.
  → 기존 옵션(초기 한/영, marked text 속성/색)이 **실제로 올바르게** 동작.
- **Phase 2**: Input Unit(Character/Word) — Dispatcher 에서 확정분 drain 방식, 트레이스
  테스트로 의미 특성화 후 최소·격리 구현. 회귀 방지 최우선.
- ~~**Phase 3(보류)**: Hanja Area/Conversion/RepeatCount — 근거·의미 확보 전 미구현.~~
  → 방침 변경 후 **§10에서 구현 완료**(원본 미구현 → 의도 매칭, 기본값은 현행 보존).

## 8. Phase 1 실행 기록 (2026-08-10)
- **[FIX] 라디오 매트릭스 저장/로드**: writeToUserDefaults 는 `[[m selectedCell] title]`
  저장, loadInputManagerInfo 는 `selectCell:withTitle:`(title 일치 셀 selectCellAtRow:)로
  선택 — 원본 `-state`/fork `setState:` 버그 교정.
- **[FIX] Init State 폴라리티**: configPreferenceValue 를 =="Korean"→initState=1 로
  교정("Korean" 선택 시 한글 모드로 시작). launch 분기 불변.
- **[보류] attributePopUp 라운드트립 역전**: 팝업 메뉴 타이틀이 "Undeline"(오타)로
  저장값 "Underline"과 달라 title-기반 불가, nib 항목 순서 모호 → AppKit 값 훼손
  위험으로 이번엔 미변경. IB/실측으로 항목 순서 확정 후 인덱스 매핑만 교정 예정.
- 빌드 412464B, 설치 완료.

## 9. Phase 2 실행 기록 (2026-08-10) — Input Unit(Character/Word)
- **구현**: Dispatcher insertText: 에서 inputUnit==1(Character)이면 imProcessEvent: 후
  [fep finalizedString](확정 completeChar) 있으면 setMarkedText:@"" → [sender insertText:]
  → [fep drainFinalized]; 조합중(astring)만 marked. Word(0)는 기존 누적.
- **FrontEnd API 추가**: finalizedString/composingString/drainFinalized(조합·오토마타 보존).
- **안전성**: 확정된 completeChar 만 커밋(종성 이월 위험 없음), astring 미확정은 커밋 금지.
- **트레이스 검증(tools/tmp/chartest.m)**: "한글은" → 한(U+D55C)@ㄱ시작, 글(U+AE00)@ㅇ시작,
  은(U+C740)@space 커밋. 조기커밋 없음.
- 빌드 412580B, 설치 완료.

## 10. Phase 3 실행 기록 (2026-08-10) — Hanja 옵션 (원본 미구현 → 의도 매칭 구현)
사용자 방침: "원본에 없으면 구현 의도에 맞는 방향으로 결정 진행". 세 옵션은 원본이
저장·로드만 하고 동작 미사용(死). 각 옵션의 이름/UI 의도에 맞춰 **회귀 없는(기본값=현행
유지) 최소·격리** 동작을 부여:
- **Hanja Conversion (SMHanjaConversion)** = 한자변환 on/off. Dispatcher hanjaConversation
  기본 1(init), configPref 로 override. doCommandBySelector: hanjaConvert: 에서
  hanjaConversation==0 이면 변환 안 하고 조합만 확정. 기본 ON → 현행 유지.
- **Hanja Area (SMHanjaArea, None/Mark)** = 후보 패널 표시 여부. hanjaConvert: 의
  hanjapanel: 호출을 `!hanjaArea` 로 가드. hanjaArea==1(None)=패널 생략(인라인만),
  0(Mark/기본)=패널 표시. 기본(미설정→0)=표시=현행. applyHanja 는 조합 전체를 치환하므로
  "단자 강제" 방향은 단어 훼손 위험이라 폐기하고 패널표시 토글로 결정.
- **Hanja RepeatCount (SMHanjaRepeatCount, 기본 3)** = 후보 패널 Up/Down 이동 단위.
  moveUp/moveDown 의 ±10 을 ±(hanjaRepeatCount>0 ? 값 : 10) 로. 기본(미설정→0)=10=현행.
- 전부 [ENHANCE], 기본값이 현행을 보존해 회귀 위험 최소. 빌드 412580B, 설치.

## 11. Preference 타이틀바 닫기 버튼 (2026-08-10)
- 원본 Preference 패널 styleMask=NSTitledWindowMask(1)만 → 타이틀바 닫기 상자 없음.
  OpenStep NSWindow 엔 setStyleMask: 가 없어(생성 시 고정) 코드로 못 바꿈.
- **nib 패치**: Preference.nib/objects.nib 의 NSWindowTemplate styleMask 바이트
  (@0x1681) 0x01→0x03 (Titled|Closable). 1바이트만 변경(7040B 동일), backing=2·
  frame(469/345/274/401) 디코드로 위치 확정. 설치본 cmp 로 검증(NIB_IDENTICAL).
- **exe**: Preference init 에 `[panel setReleasedWhenClosed:NO]` — 닫기 상자
  (performClose:→close)로 패널이 해제되지 않아 showPreference: 재표시 가능.
- 결과: 타이틀바 닫기 상자로 창 닫힘 + 기존 OK(저장+"saved"+닫기)/Cancel(orderOut).
  빌드 412580B, nib+exe 설치.
