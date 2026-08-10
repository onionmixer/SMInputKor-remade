# SMInputKor-remade

OPENSTEP 4.2 한글 입력기 **SMHangul**(Softmagic Korean Input)을 소스 없는
i386 Mach-O 바이너리에서 **소스 레벨로 복원**하고(remade), 원본 버그를 고치고
기능을 확장하는 리버스 엔지니어링 프로젝트.

복원에서 그치지 않고 실기에서 검증하며 다듬는다 — 원본에 있던 조합/설정 버그를
바로잡고, 원본에 없던 **세벌식(390/최종) 자판 지원**을 더했다.

- 목표·단계·방법론: [`PLAN_SMINPUTKOR.md`](PLAN_SMINPUTKOR.md) (정본)
- 자판 확장 계획·실행 기록: [`doc/KEYBOARD_LAYOUT_PLAN.md`](doc/KEYBOARD_LAYOUT_PLAN.md)
- 재개 노트(내부): `HANDOFF.md` (gitignore)

## 지금 상태

실기 OPENSTEP(Intel)에서 **한글 입력 동작**. fat(i386/m68k/sparc) 빌드·설치 패키지까지.

| | |
|---|---|
| 복원 | 8클래스·119메서드 — 빌드·설치·동작 |
| 자판 | **두벌식 / 세벌식390 / 세벌식최종** (Preference 라디오로 선택) |
| 고친 원본 버그 | 입력서버 등록 누락(hang), 자모 표시 오프셋, space 소실, 설정 미반영, 라디오 저장/로드 폴라리티, `ㅋㅋㅋ` 프리즈(오토마타 오배정), 자판사전 파괴(한/영 전환 불능) |
| 배포 | `.pkg` (fat 3아치, 페이로드 22파일) — `tools/build-fatpkg.sh` |

### 세벌식 지원
자판표는 [libhangul](https://github.com/libhangul/libhangul)의 390/최종 배열을 정본으로
`tools/gen_layouts.py` 가 생성하고(`data/layout_tables.m`, 빌드 시 생성), 조합은 3벌 전용
상태기계(`NoCheckAutomata`)가 담당한다 — 키가 초/중/종 위치 고정이라 받침 이월이 없고,
복모음·복종성은 결합표, 겹받침 단일키(최종)도 지원. 검증은 `tools/test/` 의 트레이스
하니스로 실기에서 수행한다(3벌 조합·백스페이스, 두벌식 무회귀).

## 무엇인가
Softmagic 한글 입력기는 OPENSTEP의 Input Manager(입력서버) 구조로 동작한다.
정품이 실기 OPENSTEP에 설치·동작 중이라 이를 정본/동작 오라클로 삼아, 재빌드
가능한 Objective-C 소스로 복원한다. 대상 바이너리는 Objective-C라 클래스·ivar·
셀렉터·원본 .m 파일명이 __OBJC에 평문 보존되어 인터페이스는 사실상 복원되어
있고, 복원할 것은 8개 클래스·119개 메서드 본문이다.

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

> `data/` 는 커밋하지 않는다. 빌드 전에 생성한다:
> `python3 tools/extract_tables.py` (정본 바이너리에서 조합표 추출),
> `python3 tools/gen_layouts.py` (세벌식 자판표 생성).

## 도구
Ghidra(MCP), IDA Pro(MCP), gdb-multiarch, 실기 OPENSTEP(정본 실행 환경).

## 주의
사용자가 정당하게 보유·설치한 소프트웨어의 보존/상호운용 목적 복원이다. 내장
데이터(한자 사전 등)·폰트·nib 등 원저작 리소스의 재배포는 라이선스 검토가
선행되어야 하며, 공개 방침은 별도 결정 전까지 로컬 보관한다.
