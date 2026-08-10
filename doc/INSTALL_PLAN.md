# 설치/교체 작업계획 — 재구성 SMHangul 입력기

원본 Softmagic_Hangul 입력기를 제거하고, 재구성한 SMHangul을 원본 pkg와 **구성
동일한 .pkg**로 묶어 설치·테스트하기 위한 계획. 실기 OPENSTEP(/ndrv NFS 공유).

## 0. 전제·원칙 (신중) — ★사용자 확정: 폰트 등 벤더 리소스는 유지
- **범위 = SMHangul 입력기만 교체.** 사용자 지시로 **폰트·`FullKorean.glyphgenerator`·
  `SymbolInput`·PS2Resources·Foundation CharacterSets 는 uninstall 하지 않고 그대로
  둔다.** → 우리 SMHangul의 FullKorean 출력 렌더에 필요한 폰트/리소스가 유지되므로
  의존성 문제 해소. **작업 대상은 `/NextLibrary/InputManagers/SMHangul/` 트리 하나뿐.**
- **새 pkg = SMHangul 입력기 하나만** 담는다(SMHangul.app + Info + KeyBindings +
  SMHangul.rc). 폰트 등은 포함하지 않음(그대로 있으니).
- **"원본과 구성 동일" 재정의:** 새 pkg의 **SMHangul 부분 파일 집합(경로·모드·구조)**이
  원본 pkg의 SMHangul 부분과 동일해야 한다(즉 같은 경로에 같은 모드로 설치되는 드롭인
  교체). 내용 차이는 오직 `SMHangul.app/SMHangul` 실행파일(우리 빌드본)뿐.
- **가역성 최우선.** 손대기 전 SMHangul 트리 백업. 실패 시 백업(또는 orig/ 원본 pkg의
  SMHangul 부분)으로 원상복구.
- **공유 머신**([[openstep-machine]]) — SMHangul.rc가 부팅 시 자동 실행 → crash 시
  콘솔 스팸 가능. .rc는 가역적으로.
- **실행 중 프로세스**(pid 168·1085) 교체·삭제 전 반드시 kill.
- **미확정(테스트로 확인):** NSInputServer 등록 경로(nib vs AppKit 자동),
  loadInputManagerInfo [STRUCT](환경설정 패널 일부 미완 가능 — 핵심 입력엔 무관).

## 1. 백업 (필수 — 먼저)
- 실기 로컬 백업: **`/NextLibrary/InputManagers/SMHangul/` 트리 전체**(교체 대상)
  + `/NextLibrary/Receipts/Softmagic_Hangul.pkg`(있으면). → native tar 로
  `/ndrv/SMInputKor/backup/`(gitignore)에 보관. (폰트 등은 건드리지 않으니 백업 불요,
  단 안전을 위해 SymbolInput/glyphgenerator 도 선택 백업 가능.)
- 원본 설치 pkg는 이미 `orig/Softmagic_Hangul.pkg.tar.gz` 보유(최종 원복 수단 —
  이 안에 원본 SMHangul.app 실행파일도 있음).

## 2. 원본 pkg 구성 분석 (= "동일성" 기준 정의)
- `orig/.../Softmagic_Hangul.info`(실측): Title=Softmagic_Hangul, Version=1.0,
  DefaultLocation=/, Relocatable=NO, Application=YES. `.sizes`: NumFiles 112.
- 설치 파일 매니페스트 확정: payload tar의 전체 경로+모드 목록(`tools/nxpkg_extract.py`
  또는 실기 설치 트리 `find`). 이게 새 pkg가 맞춰야 할 구성(파일 집합·경로·모드).
- 등록 요소: `SMHangul.rc`(부팅 실행), `Info`의 ConnectionName
  "SoftMagicKoreanFrontendProcessor", 아이콘(imageNamed: eng/kor).

## 3. 제거 — SMHangul 입력기만 (헤드리스 — nxrun)
폰트·SymbolInput·glyphgenerator·PS2Resources·CharacterSets 는 **건드리지 않는다.**
1. **프로세스 종료**: `kill` SMHangul(pid 168·1085).
2. **부팅 자동실행 차단**: `/NextLibrary/InputManagers/SMHangul/SMHangul.rc` 를 백업 후
   무력화(이름 변경) — 재부팅 시 구 바이너리 재기동 방지.
3. **SMHangul 트리 제거**: `/NextLibrary/InputManagers/SMHangul/` 만 제거(백업 후).
   나머지 입력기/폰트/리소스는 유지.
4. **수신처**: 원본이 단일 pkg 수신처(Softmagic_Hangul.pkg)를 갖는다면, 우리 pkg가
   같은 이름으로 재설치되므로 그대로 두거나 교체(§6). 새 pkg 설치가 수신처를 갱신.

## 4. 새 pkg 빌드 (SMHangul 입력기만) — 헤드리스
1. **스테이징 루트 조립**(/tmp/smk_pkgroot, 설치 루트 = /): 원본 SMHangul 트리 구조
   `./NextLibrary/InputManagers/SMHangul/`(Info, SMHangul.rc, KeyBindings/SMHangul.dict,
   SMHangul.app/{SMHangul, Resources/...})를 정본에서 배치하되, `SMHangul.app/SMHangul`
   실행파일만 **재구성 빌드본**으로 교체. nib/이미지/dict 는 정본 그대로. 데이터표는
   바이너리 내장(별도 파일 불필요). 경로·모드 원본 동일.
2. **.info 작성**: 원본 SMHangul 메타 기준(Title=Softmagic_Hangul, Version,
   DefaultLocation=/, Relocatable=NO, Application=YES). 새 이름을 쓸지(예:
   SMInputKor) 원본명 유지할지는 §6 설치 방식과 함께 결정(수신처 충돌 회피).
3. **패키지 생성**: `/NextAdmin/Installer.app/package <pkgroot> <info> -d <dest>`
   (stdin `/dev/null`). `package`가 .bom/.sizes/.tar.Z 자동 생성. **gz 없이 .tar까지만**.
   산출 `SMInputKor/pkg/`(gitignore — 정본 nib/이미지 포함하므로 비커밋).
   - OPENSTEP 함정: `dirname` 없음→sed, NeXT `mkdir -p` 없음→단계별.

## 5. 구성 동일성 체크 (새 pkg vs 원본의 SMHangul 부분)
- **파일 매니페스트 diff**: 새 pkg payload의 (경로,모드) 목록과, 원본 pkg payload 중
  `./NextLibrary/InputManagers/SMHangul/` 하위 항목을 추출해 비교 →
  **SMHangul 부분 파일 집합·경로·모드 동일**해야 함. 유일한 내용 차이 = `SMHangul.app/
  SMHangul` 실행파일(우리 빌드본 384420 vs 원본 411124).
- 새 pkg 구조 검증: `.info`/`.bom`/`.sizes`/`.tar.Z` 형식이 원본 pkg 형식과 동일.
  `.sizes` NumFiles = SMHangul 트리 파일 수(원본 112 전체가 아니라 SMHangul 부분).
- 부팅 `.rc`·`Info` ConnectionName·아이콘(eng/kor) 존재 확인.
- 통과 못하면 §4 스테이징 보정 후 재빌드.

## 6. 설치
- **GUI 경로**(사용자): Installer.app 으로 새 .pkg 설치(번들을 /로 복사). — 이 단계는
  실기 콘솔 GUI가 필요. **시점에 상세 절차 요청.**
- **헤드리스 대안**(nxrun): payload를 native `tar`로 /에 직접 전개(Installer 없이).
  모드/소유 확인. — GUI 불가 시 사용.
- 설치 후 SMHangul.rc 복원(활성화). 재부팅 또는 수동 실행으로 입력서버 기동.

## 7. 테스트 (사용자)
- 입력기 환경설정에서 활성화 → 텍스트 앱에서 2/3벌식 조합·한자 변환·기호 입력 확인.
- **GUI 조작 필요분은 시점에 단계별로 안내 요청.** 동작 오라클(조합 과정·완성 문자열
  FullKorean 표시)로 정본과 대조.

## 8. 롤백 (실패 시)
- 우리 SMHangul 프로세스 kill → §1 백업 복원(또는 orig/Softmagic_Hangul.pkg 재설치)
  → SMHangul.rc 복원 → 재부팅. 원상 복구 확인.

## 실행 기록 (2026-08-10) — 설치까지 완료, 재부팅 대기
- **백업**: `/NextLibrary/InputManagers/SMHangul` → `backup/SMHangul-orig.tar`(495616B,
  원본 exe 411124 포함) 검증.
- **pkg 빌드**(`tools/build-pkg.sh` + `pkg/Softmagic_Hangul.info`): 라이브 SMHangul
  트리 스테이징 + 실행파일만 재구성 빌드본(402568B)으로 교체 → `/NextAdmin/Installer.app/
  package`. **함정**: package 기본 `installer_tar`가 100자 초과 경로(NEXTSTEP_SMHangul.nib
  등 6개) "file name too long"으로 누락(.bom엔 36, tar엔 30 — 불일치). **해결**:
  `installer_bigtar`(long-name = 원본 offset-224 포맷)로 payload 재생성 → 6개 복구,
  bigtar tf 22파일 전부.
- **구성 동일성**: payload 파일집합 원본과 동일(22파일, 경로 일치, exe 내용만 차이).
  pre/post_install은 폰트·CharacterSets용이라 SMHangul-전용 pkg에선 정당하게 생략.
- **설치**: SMHangul 프로세스 kill → 구 트리 rm → 새 payload `/`에 bigtar 전개.
  검증: 설치 exe=우리 빌드(402568), rc/dict/nib(긴경로 포함)/tiff 전부 존재.
- **다음**: 부팅 시 SMHangul.rc가 입력서버 기동 → **재부팅으로 활성화**(사용자).

## 9. 헤드리스 vs GUI 구분
- 헤드리스(제가 nxrun으로): 백업, 프로세스 kill, .rc 무력화/복원, 파일 제거, 스테이징,
  `package` 실행, 구성 diff, (원하면) payload 직접 전개 설치.
- GUI(사용자): Installer.app 설치(선택), 입력기 활성화·입력 테스트.

## 실행 기록 (2026-08-10) — fat 시도 + 클린 i386 패키지
- **fat 빌드 시도(i386+m68k+sparc)**: 이 머신에 교차컴파일러(cc1obj)는 i386/m68k/sparc
  존재(hppa는 cc1obj 부재로 불가). 그러나 **AppKit/Foundation 프레임워크가 i386 전용
  (thin)** (`file` 확인: "for architecture i386") → m68k/sparc 링크 시 objc_msgSend/
  NSFont 등 미해결로 실패. **fat 은 우리 코드가 아니라 시스템의 thin 프레임워크로 막힘.**
  소스는 이식 준비 완료(오브젝트는 m68k/sparc 컴파일됨), `tools/build-fat.sh` 마련 —
  fat 프레임워크가 있는 시스템/플랫폼별 빌드에서 그대로 fat 산출 가능.
- **클린 i386 패키지 확정**: 디버그 SMHPROBE 프로브 15개 제거, 진단 래퍼(SMHangul→
  SMHangul.real) 제거하고 실 i386 바이너리(412444B)를 SMHangul 로 설치, 패치 nib
  (Preference closable) 포함. `package`+`installer_bigtar`(긴 경로 nib 4개 복구)로
  재생성 → **페이로드 22파일, 원본 SMHangul 구성과 동일, 잔여(.orig/.real) 없음**.
  산출: 실기 `/tmp/smk_pkgout/Softmagic_Hangul.pkg`(.bom/.info/.sizes/.tar.Z).
- 실기 설치본도 클린 바이너리로 교체됨(재테스트 필요 — 프로브 제거가 동작에 영향 없음).

## 실행 기록 (2026-08-10) — ★fat 빌드·fat 패키지 성공
- 4.2J Developer CD의 **멀티플랫폼 라이브러리 재설치** 후: 설치 프레임워크(AppKit/
  Foundation) + crt0.o/dylib1.o 가 **fat(i386/m68k/sparc)**, cc1obj 백엔드도 3아치
  (hppa 만 부재).
- **fat 빌드**(`tools/build-fat.sh`, `-arch i386 -arch m68k -arch sparc`): 설치
  프레임워크로 직접 링크 → **fat 실행파일(3아치, 1,264,140B)** 산출.
- **fat 패키지**(`tools/tmp/fatpkg.sh`): fat 바이너리를 SMHangul 로 설치 → 라이브
  트리 스테이징 → `package` + `installer_bigtar` → **페이로드 22파일(원본 구성 동일),
  내장 exe 도 fat 3아치** 검증. 산출 실기 `/tmp/smk_pkgout/Softmagic_Hangul.pkg`
  (.tar.Z 657925B). 실기 설치본도 fat 바이너리로 교체(이 머신은 i386 슬라이스 사용).
- 결론: **i386/m68k/sparc OPENSTEP 에서 동작하는 단일 fat 패키지 완성.** (hppa 는
  cc1obj 부재로 제외 — 필요시 hppa cc1obj 확보 후 -arch hppa 추가.)
