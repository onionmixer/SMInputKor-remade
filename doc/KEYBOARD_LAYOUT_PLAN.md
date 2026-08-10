# 자판 배열 3종 지원 작업계획 (두벌식 / 세벌식390 / 세벌식최종)

원본 SMHangul 은 **두벌식만** 지원(자모표 2세트가 모두 두벌식 — Automata=검사형,
NoCheckAutomata=무검사형; 3벌식 테이블 없음). 목표: **두벌식 + 세벌식390 + 세벌식최종(391)**
세 자판을 지원하고 Preference 에서 선택. 신규 기능 → 별도 계획 + codex 교차검토(불신·재검증).

## 0. 현 구조 (실측)
- `FrontEnd.setAutomata:(mode)` → mode=1 Automata(2벌 검사), mode=0 NoCheckAutomata(2벌 무검사).
  현재 Korean-ON 이 Automata 를 쓰도록 수정됨(§RE_ANALYSIS 14).
- Automata.korean:  token_tbl/cho_tbl/jung_tbl/jong_tbl(2벌), 백업링(백스페이스) 사용.
- NoCheckAutomata.korean: oneOf*(현재 2벌 복사본), 백업링 미사용.
- 조합/인코딩 헬퍼(make_two/search_code/make_bokmo/bokja, twoOfCho)는 자판 무관(공용).

## 1. 자판 구분과 automaton 매핑(설계)
- **두벌식**: 한 키가 초성/종성 겸용 → 분류·검증 필요 → **Automata**(현행) 사용.
- **세벌식(390/최종)**: 키가 초/중/종 위치 고정 → 분류 불필요("oneOf") → **NoCheckAutomata**
  계열 사용(이름이 원래 3벌식 의도로 보임). 390·최종은 **자모 매핑만 다름**(상태기계 동일).
- 결론: 상태기계 2종(Automata=2벌, NoCheckAutomata=3벌) + 3벌 테이블 2세트(390/최종).
  자판 선택값 layout ∈ {0=2벌, 1=390, 2=최종}.

## 2. Phase A — 3벌식 자모 테이블 작성 (data)
- 신규 배열: `cho390/jung390/jong390/token390/act390` 및 `choFin/jungFin/jongFin/tokenFin/actFin`.
  (값 인코딩=Johab 인덱스로 기존 oneOf/twoOfCho와 동일 규약. 키→자모 매핑만 규격별로 작성.)
- 출처: 공개된 세벌식390·최종 표준 배열. **주의**: 최종은 숫자열·특수키에 받침/겹낫표 등
  배치 → token(초/중/종 분류)·cho/jung/jong 모두 규격대로. 손으로 작성 후 트레이스 검증.
- 이 테이블들은 **정본 추출물이 아니라 우리가 신규 작성**(원본에 없음) → data/ 가 아니라
  소스에 두거나 별도 생성. IP: 표준 자판 매핑은 사실 데이터.
- ※ 현 oneOf*(2벌 복사본)는 3벌 테이블로 대체되거나, layout=2벌일 땐 Automata 를 쓰므로
  oneOf* 자체는 3벌 전용으로 재정의.

## 3. Phase B — automaton 테이블 파라미터화
- NoCheckAutomata 가 layout(390/최종)에 따라 다른 테이블을 참조하도록:
  - 방안(가벼움): 전역 포인터 `curCho/curJung/curJong/curToken/curAct` 를 setAutomata 시
    390 또는 최종 배열로 지정하고 NoCheckAutomata.korean: 이 이를 통해 인덱싱.
  - 또는 NoCheckAutomata 에 layout ivar + 분기.
- **[검증 필요] NoCheckAutomata.korean: 이 진짜 3벌식에서 올바른지** 재검토(현재는 2벌
  테이블로만 관찰). 3벌은 초/중/종 위치 고정이라 case 전이가 2벌과 다를 수 있음.
- **[해결 필요] 3벌식 백스페이스**: NoCheckAutomata 는 백업링 미사용 → imProcessBS(백업링
  기반)로는 자모 단위 삭제 불가. 대안: (a) NoCheckAutomata 에 saveBackUp/clearBackUp 추가
  (Automata 처럼), (b) 3벌 백스페이스는 조합 통째 삭제. (a) 권장(일관 UX).

## 4. Phase C — setAutomata 커플링 해제 + 선택값 배선
- 자판 선택은 on/off 와 무관해야 함. 새 상태 `keyboardLayout`(Dispatcher ivar) 도입.
- Korean-ON 경로(toggleConversionMode:/applicationDidFinishLaunching:/changeLanguage:)에서
  `[fep setAutomata: <layout에 따른 인자>]` 호출:
  - layout=2벌 → Automata, 390/최종 → NoCheckAutomata(+해당 테이블 지정).
  - setAutomata: 시그니처를 layout 받도록 확장(또는 별도 setLayout:).
- configPreferenceValue: 새 키 **`SMKeyboardType`**(값: "2beol"/"3beol390"/"3beolFinal"
  또는 정수) 읽어 keyboardLayout 설정 + 현재 조합 automaton 갱신.
- writeToUserDefaults: 선택 UI → SMKeyboardType 저장. OK 후 재적용(configPreferenceValue).

## 5. Phase D — Preference nib 편집 (자판 선택 UI)
- **백업 필수**: 작업 전 Preference.nib(objects.nib+data.classes) 를 backup/ 로 복사.
- 컨트롤: NSPopUpButton 또는 3-라디오 NSMatrix "자판: 두벌식 / 세벌식390 / 세벌식최종".
- 아울렛 `keyboardTypePU` + 액션(변경 시 즉시 미리보기 or OK 시 반영) 추가.
- **편집 방법 결정 필요**:
  - (권장·안전) **InterfaceBuilder(실기 GUI)** 로 컨트롤 추가·아울렛/액션 연결 → 가장
    정석. 사용자 GUI 작업 필요(제가 절차 안내).
  - (대안) typedstream 직접 편집 — 새 NSPopUpButton 오브젝트·연결 레코드 삽입은 매우
    복잡·고위험(바이트 패치 수준 넘음). 비권장.
  - data.classes 에 Preference 의 새 아울렛/액션 등록 필요.
- Preference.h 에 `keyboardTypePU` 아울렛 + 액션 선언, Preference.m 에 load/save 반영.

## 6. Phase E — 검증
- 헤드리스 트레이스: 각 layout 대표 시퀀스(두벌 "gksrmfdms"=한글은; 390·최종은 규격
  키열로 같은 음절) → 동일 음절 산출 확인. 복모음/복종성/받침/백스페이스/연속자음.
- 실기 GUI: Preference 에서 자판 전환 → 즉시 반영, 각 자판으로 입력 확인.
- 회귀: 두벌식(현행) 동작 불변 확인.

## 7. 리스크·원칙
- 두벌식(현재 정상)에 회귀 금지 — layout=2벌 경로는 기존 Automata 그대로.
- 3벌 테이블 오작성 위험 → 규격 문서 대조 + 트레이스로 음절 단위 검증.
- nib 편집 위험 → 백업 + InterfaceBuilder 우선. 실패 시 백업 복원.
- 신규 기능은 [ENHANCE] 태그, 충실복원부와 구분.

## 8. codex 교차검토 (예정)
- 계획·3벌 테이블·automaton 파라미터화·백스페이스 처리 검토. **codex 불신, 정본/트레이스 재검증.**

## 9. 결정 사항 (★확정)
1. **nib 편집**: **headless typedstream 편집을 먼저 시도**, 로드 실패/깨짐이면 사용자가
   InterfaceBuilder(실기)로 추가(제가 절차 안내). §13 참조.
2. **세벌식 규격**: **390 표준 + 최종 391 표준**.
3. **UI 형태**: OK 버튼 위쪽 **3-라디오 그룹**(NSMatrix, 가로 허용), Preference 전체 **영문**.
4. **SMKeyboardType 기본값**: 두벌식(2벌). enum/정수 + 2벌 fallback.
5. **3벌식 백스페이스**: 자모 단위(논리 단위 정의 후). [미세결정은 Phase 3에서]

## 10. [블로커·실측] Dispatcher 키 라우팅 — 최종 지원의 핵심 난점
- 현재 `Dispatcher insertText:`(src/Dispatcher.m:109): `if ((c-'A')>25 && (c-'a')>25)`
  → **A-Za-z만 imProcessEvent 로**, 나머지(숫자·기호)는 makeCompleteChar 후 통과.
- **세벌식최종은 숫자열·기호 키에 받침/자모 배치** → 그 키들이 automaton 에 안 감 →
  최종 조합 불가. (세벌식390은 대부분 알파벳이라 영향 적으나 일부 기호 사용분 확인 필요.)
- **수정 방향**: 라우팅을 **자판 인지(layout-aware)** 로. 현재 layout 의 token 표에서
  해당 키가 자모(token≠passthrough)면 imProcessEvent, 아니면 통과.
  - 방안(가벼움): Dispatcher 가 현재 layout token 표(또는 fep 에 질의)로 판정.
  - 방안(구조적): 모든 키를 automaton 에 보내고, korean: 의 case1/7(asc_code 통과)로
    비자모 처리 → Dispatcher 는 ret_flag/asc_code 로 통과 여부 결정. (흐름 변경 큼.)
- 두벌식 회귀 방지: layout=2벌일 땐 기존 A-Za-z 게이트와 동일 결과가 되도록.

## 11. 예상 작업량·순서 요약
1. Phase A 3벌 테이블(390/최종) 작성·검증 — 가장 큰 데이터 작업.
2. Phase B NoCheckAutomata 3벌 정합성 재검토 + 백스페이스(백업링) 처리.
3. Phase C setAutomata 커플링 해제 + keyboardLayout 배선 + 라우팅(§10) 수정.
4. Phase D Preference nib 편집(백업 후, IB 권장) + 아울렛/액션/pref.
5. Phase E 트레이스·실기 검증, 회귀 점검. → codex 재검토.

## 12. codex 교차검토 결과 (정본/트레이스로 재검증 — codex 불신)
- **[수용] NoCheckAutomata=3벌 엔진은 미검증 가정.** oneOf*가 2벌 테이블이고 도달 액션이
  2벌 액션표와 일치. case0(초기상태 중성 드롭)·case3(연속자음 무시)가 3벌에서도 문제.
  → **3벌 상태기계는 테이블 교체만으론 부족**. 명세/트레이스 선행, 필요시 소형 3벌
  상태기계 신설 검토.
- **[수용] 위치고정 키만으론 전이 정확 보장 안 됨.** case9 재음절화가 oneOfCho[save_jong]
  에 의존 → 직접 겹받침 키는 (ㄺ→ㄹ+ㄱ) 분해 이월 불가. **겹받침 분해 메타데이터** 또는
  겹받침을 두 받침키로 입력하도록 설계·검증 필요. ㅇ/ㅎ 이월도 커버.
- **[수용] 초성 채움(Choseong filler)·종성전용/추가 자모 미계획.** twoOfCho는 일반 초성만.
  jaeum_two 존재하나 미사용. **규격에서 목표동작 확정**(명시 ㅇ/호환자모/filler/거부).
  cho·jong 배열에 억지로 섞지 말 것.
- **[수용] 백스페이스는 자모 단위로 하되 saveBackUp 추가만으론 안 됨.** 논리 입력 단위
  정의 필요(직접 겹받침 1키=삭제 시 2자모; 두키 겹받침=한 구성 먼저 pop; 스냅샷은
  이월용 pending-final 상태까지 보존). back[5] 오버플로 가드 부재도 재점검.
- **[수용] 3벌도 인코딩 커버리지 확대 없음** — 동일 search_code/KS 통과. 단 특수코드
  fallback 5개 존재 → "기존 인코더 인벤토리와 동일"로 표현(재검증 대상).
- **[수용·블로커] 최종은 현 Dispatcher 게이트로 불가**(src/Dispatcher.m:109 — 비문자
  선통과). **자판 인지 accepted-key 술어로 라우팅**: 활성 layout이 선언한 문자(shift 포함)만
  조합, 그 외 printable 통과, space/Return/BS/명령/IM 제어는 컨트롤 유지, NoCheckAutomata
  룩업 전 <128/유효 token 가드(실추출 테이블 128항목).
- **[수용] 레이아웃 전환은 조합 경계에서만.** configPreferenceValue엔 sender 없어
  makeCompleteChar: 불가. → 선택값 즉시 저장, [fep isWorking]이면 pending, 다음 커밋/취소
  후 적용. launch/toggle-on/changeLanguage:/pref reload 를 **단일 "입력상태 적용" 경로로 통합**.
- **[수용] keyboardLayout 은 enum/정수 + 2벌 fallback**(문자열보다 명확). 결측/도메인 검증.
- **[수용] 헤드리스 typedstream nib 편집은 비현실적으로 위험.** 팝업/매트릭스 추가는
  오브젝트·메뉴·뷰포함·지오메트리·아울렛/액션 커넥터 다수 필요. **InterfaceBuilder(실기)**가
  정석. data.classes 에 keyboardType 아울렛 추가(즉시반영이면 ACTION도; OK-저장이면 불요).
- **[수용] 선언적 레이아웃 정의 우선**: 각 자판을 `문자→역할·자모인덱스·단독출력·재음절화/
  분해 메타`로 선언 → 표·테스트 생성. **UI 전에 Dispatcher end-to-end 트레이스**(모든 비문자
  키·단순/겹받침+모음·단독자모/filler·각 단계 백스페이스·조합중 레이아웃 변경) 선행.

## 13. nib UI 확정 (사용자 요구)
- **기존 UI 유지**, OK 버튼 **위쪽**에 **자판배열 선택 라디오 그룹**(가로 배치 허용) 추가.
- **Preference 전체 영문** — 라디오 라벨 영문: 예 "2-set" / "3-set 390" / "3-set final"
  (또는 "Dubeolsik"/"Sebeolsik 390"/"Sebeolsik Final"). 박스 타이틀 예 "Keyboard".
- **편집 방법 (★사용자 확정: headless 우선, 실패 시 IB)**:
  1) **headless typedstream 편집을 먼저 시도** — Preference.nib 백업(backup/) 후:
     - objects.nib(NeXT typedstream)에 NSMatrix(NSButtonCell 라디오 3셀, 태그 0/1/2,
       타이틀 "2-set"/"3-set 390"/"3-set final") + NSBox("Keyboard") 오브젝트를 OK 위쪽
       프레임에 추가, File's Owner(Preference)의 새 아울렛 `keyboardType` 커넥터 추가,
       (즉시반영 시)액션 커넥터 추가.
     - data.classes 에 Preference OUTLETS 에 `keyboardType` 추가((필요시)ACTIONS 도).
     - **접근**: typedstream 파서/작성기로 라운드트립(정확한 클래스 버전·타입코드 재현).
       바이트 삽입은 오프셋·길이·객체 참조번호 갱신이 필요 → 전용 도구 작성.
     - **검증**: 실기에서 nib 로드 성공 + 라디오 표시·아울렛 연결 동작 확인.
  2) 로드 실패/깨짐이면 → **백업 복원 후 사용자가 InterfaceBuilder(실기)로 추가**(제가
     정확한 절차 안내: 3셀 매트릭스·태그 0/1/2·프레임·아울렛 keyboardType 연결).
  - 코드측(Preference.h 아울렛 선언, load/save, 적용)은 어느 경우든 제가 담당.

## 14. 개정 진행 순서 (codex 반영)
1. **레이아웃 선언**(2벌/390/최종): 문자→역할/자모/단독/분해 메타. 표·테스트 생성.
2. **Dispatcher 라우팅**을 layout-aware accepted-key 로(최종 블로커 해결) + NoCheck 가드.
3. **3벌 상태기계 명세·트레이스**: NoCheckAutomata 적응 가능성 판정, 안 되면 소형 3벌 엔진.
   겹받침 분해·이월·초성채움·백스페이스 단위 확정.
4. **입력상태 적용 단일 경로** + keyboardLayout(enum) + 경계 전환(pending).
5. **nib UI**(IB, 백업 후) + 아울렛/load/save/pref(SMKeyboardType).
6. **검증**: 3자판 end-to-end 트레이스 + 실기, 두벌식 회귀 점검. → codex 재검토.

## 15. Phase 1 실행 기록 (2026-08-10) — 완료
- **레이아웃 선언(libhangul 참조)**: `tools/gen_layouts.py` — 세벌식390(hangul-keyboard-39)·
  최종(hangul-keyboard-3f)의 키→U+11xx 조합형 자모를 정의. U+11xx→Johab 인덱스 변환기
  (cho (U-1100)+2 / jung 21표 / jong 갭(18) 반영).
- **변환기 교차검증**: 두벌식 추출표(cho_tbl/jung_tbl)와 대조 → **OK**(일치). 390 스폿체크:
  초 k→ㄱ(2)/h→ㄴ(4)/;→ㅂ(9)/j→ㅇ(13)/m→ㅎ(20), 중 f→ㅏ(3)/t→ㅓ(7)/v→ㅗ(13)/d→ㅣ(29),
  종 x→ㄱ(2)/s→ㄴ(5)/q→ㅅ(21)/a→ㅇ(23), 최종 겹받침 단일키 @→ㄺ(10)/D→ㄼ(12)/$→ㄿ(15). 전부 정확.
- **C 방출**: `data/layout_tables.m`(gitignore) — 390/최종의 role/cho/jung/jong 128표
  (role 0통과/1초/2중/3종). Phase 2/3 automaton 이 참조할 자판 데이터.
- **Dispatcher 자판 인지 라우팅**: 하드코딩 `(c-'A')>25 && (c-'a')>25` → `![fep isJamoKey:c]`.
  Automata.isJamoKey(token_tbl 1~4)=두벌식 자모. **전수(0~127) 동치 검증 → 두벌식 회귀 없음.**
  세벌식최종의 숫자/기호 자모 키 라우팅 준비 완료(§10 블로커 해소 기반). NoCheckAutomata
  override(3벌 role표)는 Phase 2.
- fat(3아치) 빌드 클린. (사용자 가시 동작 변화 없음 → 재설치/재패키징은 3벌 활성화 단계에서.)

## 16. Phase 2 실행 기록 (2026-08-10) — automaton 재작성·검증 완료
- **libhangul 조합엔진 참조**(hangulinputcontext.c, JASO 처리): 세벌식은 (1) 받침 이월 없음,
  (2) 초성이 완성음절/초성 뒤에 오면 확정+재시작, (3) 복모음/복종성은 결합표, (4) 단독 자모는
  filler/raw. 이 설계를 그대로 채택.
- **NoCheckAutomata 재작성**(`src/NoCheckAutomata.{h,m}`): 2벌 무검사 변형 → **3벌 전용 상태기계**.
  `int layout` ivar + `setLayout:`(1=390/2=최종). role(초1/중2/종3) 위치고정 → 분류 불필요.
  상속 헬퍼 재사용: make_two/search_code(→EUC-KR), make_bokmo(복모음)/make_bokja(복종성),
  백업 링(saveBackUp/reduceCount/clearBackUp — 3벌 백스페이스 지원). automata_init 에 clearBackUp
  추가(원본은 누락). `isJamoKey:` override(자판 role표 기준).
- **상태**: 0빈/1초/2초+중/3완성(+종). 초성: status!=0→finishRest(직전확정)+재시작.
  중성: st1→초+중 결합, st2→복모음(make_bokmo), 그외→직전확정+모음단독(rest_moeum 동형).
  종성: st2→초+중+종, st3→복종성(make_bokja), 그외→직전확정+종성드롭[INFER].
- **정본 정합 교정 2건**(재작성 중 발견): (a) 초성 단독코드 `cho_two`(=`twoOfCho`, 동일 확인)
  사용, (b) status==0 단독모음에서 ret_flag=3·rest_flag=**-1**(원래 초안은 둘다 3 → comp_code 이중
  커밋 버그였음. makeReplaceString flag3 는 comp_code 를 completeChar 로 커밋하므로 ret/rest 둘다
  3이면 2번 들어감). Automata.korean: 의 rest_moeum(잔여 있으면 ret2+rest3) 동형으로 정렬.
- **트레이스 검증**(`tools/tmp/tr3.m`, FrontEnd imProcessEvent+makeReplaceString 재현, 실기 실행):
  390 `mfs`→한(D55C) / `kgw`→글(AE00) / `mfskgw`→한글 / `kvf`→과(복모음ㅘ) /
  `kfX`·`kf3q`→값(직접·결합 겹받침 둘다) / `kk`→ㄱ+ㄱ(연속초성, 예전 프리즈 버그류) /
  `f`→ㅏ(단독) / 백스페이스 하→ㅎ·한→하·한→하→ㅎ. 최종 `jfE`→앉(C549, 최종 고유 ㄵ직접받침),
  390 대조 `jfE`→아(앜은 KS X 1001 미수록 → 초+중 확정·종성 드롭; 2벌 Automata 도 동일 한계).
  **전부 기대치 일치.**
- **KS 완성형 한계**(설계상): search_code 는 KS X 1001(2350음절)만 → 앜/옛한글 등 미수록 음절은
  표현 불가. 초+중+종 무효 시 초+중 확정·종성 드롭. 2벌 Automata 와 동일 거동이라 회귀 아님.

## 17. Phase C/D 실행 기록 (2026-08-10) — 배선·UI(headless)
- **FrontEnd**(`setAutomata:`): on/off 파라미터 유지하되 ON 시 `keyboardLayout` 로 분기 —
  0→Automata(2벌), 1/2→NoCheckAutomata+setLayout:. `int keyboardLayout` ivar +
  `setKeyboardLayout:`/`keyboardLayout` 접근자 추가. (호출부 다수의 on/off 의미 불변 → 회귀 없음.)
- **Dispatcher**: `+initialize` 에 `SMKeyboardType`=@"0" registerDefaults. `configPreferenceValue`
  에서 SMKeyboardType 읽어 `[fep setKeyboardLayout:]`, **Korean 활성 & 조합중 아님(`isTurnedOn`
  && `![fep isWorking]`)이면 setAutomata:1 로 즉시 반영**, 조합중이면 다음 토글에 반영(경계안전).
- **Preference 저장/로드**: `writeToUserDefaults:` → `[keyboardType selectedColumn]` 문자열 저장.
  `loadInputManagerInfo`(configureWindow) → `selectCellAtRow:0 column:[v intValue]` 로드.
  int(열 인덱스) 기반 — configPreferenceValue 의 intValue·registerDefaults "0" 와 정합.
- **nib UI (headless — nib 바이너리 무편집)**: objects.nib 은 typed-stream(손편집 위험) →
  **런타임 프로그램적 구성** 채택. `Preference.init` 에서 `buildKeyboardTypeUI` 호출:
  `keyboardType` 아웃렛 nil 일 때만(추후 IB 배치 시 자동 생략·공존) 패널을 상단으로 H=30 키우고
  (`setAutoresizesSubviews:NO` 로 하단 앵커 서브뷰 고정) 새 상단 스트립에 "Keyboard:" 라벨 +
  [2-set | 3-set 390 | 3-set final] **1행×3열 가로 라디오**(영문, OK 포함 모든 컨트롤 위) 배치.
  값=selectedColumn(0/1/2). ※ IB 대안: `keyboardType` 아웃렛만 매트릭스에 연결하면 코드 구성 생략.
- 빌드: 모든 build-*.sh 에 `data/layout_tables.m` 추가. 전체 fat(i386/m68k/sparc) 클린 컴파일.
- **남음(Phase E)**: 실기 설치·Preference 패널 시각 확인(라디오 배치/선택 저장) + 3벌 실입력
  E2E(390/최종) + 2벌 회귀 + codex 재검토.

## 18. codex 교차검토 + 수정 (2026-08-10) — 실측 재검증 후 반영
codex 5건 지적. **불신 원칙대로 각각 실측 재검증**:
1. **[실버그·수정] 잉여/실패 종성 드롭 → 데이터 손실.** 종성키가 놓일 자리 없을 때(초/중 없음,
   겹받침 실패, KS 미수록) 자음을 버리고 working=1 만 세워, 이후 백스페이스가 **문서 텍스트를
   삭제**. codex는 `jaeum_two[jong_index]`를 제안했으나 **실측하니 jaeum_two는 CHO 인덱스**라
   (jaeum_two[5]=ㄷ≠ㄴ) 그대로 쓰면 엉뚱한 자음. → gen_layouts.py에 `JONG_COMPAT`(U+11xx→U+31xx)
   + `lyJongTwo_390/Fin`(ASCII→0xA4xx) 생성, 종성 fallback을 모음 fallback과 동형(단독 자음 확정)
   으로 교정. 트레이스: `x`→ㄱ, `mx`→ㅎ+ㄱ, `kfXx`→값+ㄱ, `jfE`(390)→아+ㅋ(예전 ㅋ드롭 해소).
2. **[UX갭·수정] 조합중 자판변경이 토글 전까지 미적용.** configPreferenceValue가 !isWorking일
   때만 재생성 → 조합중 변경은 setWorkingInit이 옛 클래스 재init. → Dispatcher에 `layoutPending`
   ivar, 조합중이면 대기→insertText: 경계(!isWorking)에서 setAutomata:1 적용(isJamoKey 라우팅 앞).
3. **[누수·수정] setAutomata: 교체 시 이전 오토마타 미해제.** → 상단에서 `[myAutomata release]`.
4. **[누수·수정] 프로그램 라디오 매트릭스 생성 소유권 미해제.** → addSubview 후 `[m release]`.
5. **[견고성·수정] layout 값 미검증**(SMKeyboardType=3→390 오선택, NSMatrix 범위초과). →
   setKeyboardLayout: 0..2 클램프, setLayout: 1/2 클램프, Preference 로드 열 0..2 클램프.
codex 확인: 0/1/2 selectedColumn→string→intValue 폴라리티 정상, C89 위반 없음. **전 findings
수정 후 전체 fat 클린 빌드 + 3벌/2벌 트레이스 전부 통과 + 실기 재배포.**

## 19. [중대] 자판사전 파괴 버그 — 한/영 전환 불능 (2026-08-10 발견·수정)
**증상**: 자판 기능 테스트 중 Preference 에서 Set 을 누르자 **한/영 전환키가 죽음**.
**원인(잠복 버그, 자판 기능과 무관)**: `~/Library/KeyBindings/SMHangul.dict` 는 정본이
**keystroke→action** 방향인데(`extracted/live/SMHangul/KeyBindings/SMHangul.dict` 13항목:
`"$ "="toggleConversionMode:"` … `"\010"="deleteBackward:"` `"\UF700".."\UF703"=move*`),
재구성 코드가 두 겹으로 어긋나 있었다:
  (a) `loadInputManagerInfo` 가 dict 에서 `""`/`" "` **2항목만** `_imMap` 에 복사,
  (b) `writeToUserDefaults:` 가 `_imMap` 에 **action→keystroke(반전)** 로 3개만 넣고 파일로 씀.
→ 저장 즉시 dict 가 `{"toggleConversionMode:"="$ "; …}` 3항목으로 축소·반전. 시스템은
keystroke 로 조회하므로 **한/영 전환·공백·엔터·백스페이스·화살표 바인딩이 전부 소실**.
(실기 실측으로 확인: 손상본 3항목 vs 정본 13항목.)
**수정**:
- 로드: `[_imMap addEntriesFromDictionary:kbDict]` — dict 전체를 정본 방향 그대로 보존.
- 저장: 새 `rebindAction:toKey:` — 해당 액션의 옛 keystroke 항목 제거 후 **keystroke 를 키로**
  재등록. 나머지 바인딩은 보존.
- **자동 복구 `repairKeyBindings`**(사용자 수동 조치 불필요, 멱등): (1) 키가 `…:` 셀렉터 모양인
  반전 항목을 뒤집어 복원, (2) 필수 편집 바인딩(공백/엔터/백스페이스/화살표) 누락 시 정본값 보충.
  화살표는 비ASCII(U+F700..F703)라 `stringWithCharacters:` 로 unichar 구성(UTF-8 바이트를
  `stringWithCString:` 에 넣으면 3글자가 되어 어긋남 — 자체 검토로 발견·교정).
- 손상된 사용자 dict 는 `tools/tmp/fixdict.sh` 로 즉시 복구(원본은 `.broken` 백업).
**codex 2차 교차검토 반영**: (1) 홈 dict 가 존재하나 **파싱 실패**면 폴백을 건너뛰어 같은 손실이
재발 → `if(!kbDict)` 로 폴백 조건 교정 + `repairKeyBindings` 를 dict 유무와 무관하게 항상 실행.
(2) 팝업이 편집키(예 `" "`=enteredSpace:)를 덮어쓰면 공백이 죽음 → `isEditingAction:` 보호 가드
추가(팝업끼리 충돌은 사용자의 명시적 선택이므로 나중 선택 우선 유지).
**Preference 캡션 폰트**: `systemFontOfSize:11` 강제로 창 내 다른 텍스트와 서체가 달라 보이던 것을
라디오 셀(nib 원본) 폰트를 상속하도록 교정.
