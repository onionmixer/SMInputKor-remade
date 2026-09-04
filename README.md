# SMInputKor-remade

OPENSTEP 4.2 한글 입력기 **SMHangul**(Softmagic Korean Input)을 소스 없는
Mach-O 바이너리에서 **소스 레벨로 복원**하는(remade) 리버스 엔지니어링 프로젝트.

복원에서 그치지 않고 실기에서 검증하며 다듬는다 — 원본의 조합/설정 버그를
바로잡고, **원본이 만들다 만 Preference 기능들을 완성**했으며, 원본에 없던
**세벌식(390/최종) 자판 지원**을 더했다.

### 왜 복원이 가능한가

Softmagic 한글 입력기는 OPENSTEP의 Input Manager(입력서버) 구조로 동작한다.
정품이 실기에 설치·동작 중이라 이를 **정본이자 동작 오라클**로 삼는다. 대상이
Objective-C라 클래스·ivar·셀렉터·원본 `.m` 파일명이 `__OBJC` 섹션에 평문으로
남아 있어 **인터페이스는 사실상 이미 복원되어 있고**, 복원할 것은 메서드
본문이다.

- 목표·단계·방법론: [`PLAN_SMINPUTKOR.md`](PLAN_SMINPUTKOR.md) (정본)
- 자판 확장 계획·실행 기록: [`doc/KEYBOARD_LAYOUT_PLAN.md`](doc/KEYBOARD_LAYOUT_PLAN.md)

## 요구 환경

**OPENSTEP 4.2J (일본어판)** 이 필요하다. 입력기(Input Manager) 기반이
그쪽에 들어 있고, fat 빌드에 쓰이는 멀티플랫폼 라이브러리도 4.2J
Developer CD에서 온다. 영문판만으로는 빌드도 동작도 보장하지 않는다.

배포 패키지는 **fat 3아키텍처 — i386 / m68k / sparc** 로 만든다. 하나의
`.pkg` 로 셋 다 설치되며, Installer.app 이 이를 정상 처리하고 **설치 후에도
세 아키텍처가 모두 남는 것**을 실기에서 확인했다(설치본 `file` = fat file
with 3 architectures). (hppa는 이 기계에 `cc1obj` 백엔드가 없어 제외했다.)

**입력 동작 확인은 i386 실기**에서 했다. m68k/sparc 는 빌드·패키징·설치까지
검증했고, 그 위에서 실제로 한글을 입력해 본 것은 아니다.

## 지금 상태

| | |
|---|---|
| 복원 | 8클래스·119메서드 — 빌드·설치·동작 |
| 자판 | **두벌식 / 세벌식390 / 세벌식최종** (Preference 라디오로 선택) |
| 고친 원본 버그 | 입력서버 등록 누락(hang), 자모 표시 오프셋, space 소실, 라디오 저장/로드 폴라리티, `ㅋㅋㅋ` 프리즈(오토마타 오배정), 자판사전 파괴(한/영 전환 불능), **부팅 경쟁**(아래) |
| 완성한 미구현 기능 | Preference 옵션 5종 + 패널 닫기 버튼 (아래) |
| 배포 | Installer.app 용 `.pkg` (페이로드 22파일) — `tools/build-fatpkg.sh` |

### 원본이 만들다 만 것들

Preference 패널에는 옵션이 있는데 **원본은 그 값을 저장·로드만 하고 동작에는
쓰지 않았다**(死). 라디오를 돌려도 아무 일이 일어나지 않는다. 각 옵션의
이름과 UI 의도에 맞춰 구현하되, **기본값이 원본의 현행 동작을 그대로
보존**하도록 해서 회귀 위험을 없앴다.

| 옵션 | 원본 | 지금 |
|---|---|---|
| **Init State** (English/Korean) | 폴라리티가 뒤집혀 있었다 | Korean 선택 시 한글 모드로 시작 |
| **Input Unit** (Character/Word) | 미사용 | Character = 글자 확정 즉시 커밋, Word = 누적(원본 동작) |
| **Hanja Conversion** | 미사용 | 한자변환 on/off. 끄면 변환 없이 조합만 확정 |
| **Hanja Area** (None/Mark) | 미사용 | 후보 패널 표시 여부. None이면 인라인만 |
| **Hanja RepeatCount** | 미사용 | 후보 패널 Up/Down 이동 단위 (기본 10) |

**Preference 패널에 닫기 버튼이 없던 것**도 고쳤다. OpenStep의 `NSWindow`는
생성 후 `styleMask` 를 바꿀 수 없어 코드로는 불가능했고, `Preference.nib` 의
`NSWindowTemplate` styleMask 바이트를 `Titled` → `Titled|Closable` 로 **1바이트
패치**했다. 닫아도 패널이 해제되지 않도록 `setReleasedWhenClosed:NO` 를 함께
넣어 재표시가 된다.

자세한 측정·구현 기록: [`doc/PREF_FEATURES_PLAN.md`](doc/PREF_FEATURES_PLAN.md).

### 부팅 때 입력기가 안 뜨던 것

원본 `SMHangul.rc` 는 부팅 시 입력서버를 **조건 없이** 띄운다.  그런데 입력서버는
`NSApplication` 이라 기동하자마자 윈도우서버(DPS)에 붙어야 하고, 못 붙으면 죽는다.
`/etc/rc` 는 입력기를 524행에서 띄우는데 **윈도우서버는 rc 가 아니라 `init` 이
`/etc/ttys` 22행에서** 띄운다 — rc 가 끝난 뒤다.  그래서 입력기가 항상 먼저
묻고, 윈도우서버가 몇 초 안에 답하지 못하면 그 부팅에는 입력기가 없다.

실측: 디스크에 남아 있던 **부팅 23회 중 6회(26%)** 가 그렇게 죽었고, syslog 에
`DPS Error:  Can't connect to server on host local host` 로 매번 기록돼 있었다.
실패는 모두 기동 후 6초 안에 일어났다.

고친 방식은 **재시도**다.  첫 기동은 원본과 똑같이 두고(4분의 3은 이미 잘
되므로 건드리지 않는다), 뒤에 감시를 백그라운드로 붙여 10초 뒤에 프로세스가
없으면 다시 띄운다(최대 12회).  잘 되는 부팅은 아무 로그도 남기지 않는다.
근거·시험·되돌리기는 [`doc/RC_RETRY_PLAN.md`](doc/RC_RETRY_PLAN.md).

### 세벌식 지원
자판표는 [libhangul](https://github.com/libhangul/libhangul)의 390/최종 배열을 정본으로
`tools/gen_layouts.py` 가 생성하고(`data/layout_tables.m`, 빌드 시 생성), 조합은 3벌 전용
상태기계(`NoCheckAutomata`)가 담당한다 — 키가 초/중/종 위치 고정이라 받침 이월이 없고,
복모음·복종성은 결합표, 겹받침 단일키(최종)도 지원. 검증은 `tools/test/` 의 트레이스
하니스로 실기에서 수행한다(3벌 조합·백스페이스, 두벌식 무회귀).

## 디렉터리
| 경로 | 내용 |
|---|---|
| `orig/` | 원본 패키지 6종 + `payloads/`(내부 tar.Z 보존) |
| `extracted/live/` | 정품 설치본(정본): SMHangul/SymbolInput/glyphgenerator |
| `extracted/jdev_sdk/` | NeXT 입력기 SDK 예제 소스(API 스캐폴드) |
| `extracted/*.txt` | otool 분석(ObjC 메타·libs·size) |
| `re/` | Ghidra/IDA 산출·데이터 덤프·분석노트 |
| `src/` | 복원 Objective-C 소스 |
| `doc/` | 분석·동작 오라클 문서 |
| `data/` | 정본에서 추출/생성하는 표 (벤더 데이터 — 커밋 제외, 빌드 시 생성) |
| `tools/` | 빌드·패키징·배포 스크립트, 표 생성기(`gen_layouts.py`/`extract_tables.py`), `nxpkg_extract.py`(비표준 NeXT pkg tar 추출기) |
| `tools/test/` | 실기 검증 하니스(조합 트레이스·백스페이스·회귀) |
| `dist/` | 산출 `.pkg` (커밋 제외) |

## 빌드·설치

두 단계로 나뉜다. **표 생성은 아무 데서나**(python3만 있으면 되고, 보통
개발용 리눅스/맥에서), **빌드와 패키징은 OPENSTEP 실기에서** 한다.
크로스 컴파일러가 아니라 실기의 `cc`로 짓는다.

### 먼저: 정품 SMHangul이 있어야 한다

조합표는 **벤더 데이터**라 이 저장소에 커밋하지 않는다. 대신 빌드 시점에
**사용자가 보유한 정품 바이너리에서 추출**한다. 그러므로 정품 SMHangul이
설치된 OPENSTEP이 없으면 빌드할 수 없다. 소스만 받아서 되는 프로젝트가
아니다.

**1. 표 생성** — 빌드 전에 반드시 먼저 돌린다. python3만 있으면 되고
어느 기계에서 돌려도 좋다.

```sh
# 정품 바이너리에서 조합/인코딩표 추출 → data/automata_tables.m
python3 tools/extract_tables.py [SMHangul_바이너리] [출력.m]
#   기본 입력: extracted/live/SMHangul/SMHangul.app/SMHangul

# 세벌식 390/최종 자판표 생성 → data/layout_tables.m
python3 tools/gen_layouts.py
```

`gen_layouts.py` 는 정품이 필요 없다 — 자판 배열의 출처는
[libhangul](https://github.com/libhangul/libhangul)이고 표는 선언적으로
정의되어 있다. 정품이 필요한 것은 `extract_tables.py` 쪽이다.

**2. 빌드·패키징** — 이 트리를 OPENSTEP 기계로 옮긴 뒤(공유 폴더든
FTP든 상관없다), 그 위에서 실행한다.

```sh
sh tools/build-fat.sh       # fat(i386/m68k/sparc) 빌드
sh tools/build-fatpkg.sh    # Installer.app 용 .pkg 패키징
```

> 스크립트 첫머리에 프로젝트 트리의 절대경로가 박혀 있다. 개발 환경의
> 값이므로, 트리를 둔 위치에 맞게 그 `cd` 경로를 고쳐서 쓴다.

fat 빌드에는 **4.2J Developer CD의 멀티플랫폼 라이브러리**가 설치되어
있어야 한다(위 요구 환경 참조). 설치된 AppKit/Foundation이 i386 전용이면
m68k/sparc 링크가 `objc_msgSend` 미해결로 실패한다 —
[`doc/INSTALL_PLAN.md`](doc/INSTALL_PLAN.md)에 그때의 기록이 있다.
i386만 필요하면 `tools/build-app.sh` + `tools/build-pkg.sh` 로 충분하다.

**설치** — 산출된 `.pkg` 를 Installer.app 으로 연다. 입력기는 부팅 시
`SMHangul.rc` 가 기동하므로 **재부팅해야 활성화**된다.

> **이 패키지만으로는 부족하다.** 원본 `Softmagic_Hangul.pkg`(18MB)는 입력기
> 외에 한글 폰트(`/NextLibrary/Fonts` — Gothic·MyungJo 계열), **EUC-KR 변환표**
> (`Foundation.framework/Resources/CharacterSets` — 일본어판의 EUC-JP 표를
> 치우고 대체), Rulebooks, SymbolInput 을 함께 깔고 `buildafmdir` 로 폰트
> 메트릭을 재생성한다. 우리 패키지는 **입력기 하나(22파일, 680KB)** 만 담는다 —
> 그 리소스들은 재배포 대상이 아니기 때문이다.
>
> 따라서 **정품이 한 번이라도 설치된 시스템**에 덮어쓰는 용도다. 정품을 깐 적
> 없는 4.2J에 이것만 설치하면 폰트와 인코딩 변환표가 없어 제대로 동작하지
> 않는다.

## 도구
Ghidra(MCP), IDA Pro(MCP), gdb-multiarch, 실기 OPENSTEP(정본 실행 환경).

## 주의
사용자가 정당하게 보유·설치한 소프트웨어의 보존/상호운용 목적 복원이다. 내장
데이터(한자 사전 등)·폰트·nib 등 원저작 리소스의 재배포는 라이선스 검토가
선행되어야 하며, 공개 방침은 별도 결정 전까지 로컬 보관한다.
