# SMHangul.rc 재시도 계획 (안 B) — 2026-09-04

부팅 4회 중 1회꼴로 입력기가 뜨지 않는다.  원인은 확정됐다(HANDOFF
2026-09-04 (2)): `SMHangul` 은 `NSApplicationMain`(`src/glue.m:23`)이라
기동 즉시 윈도우서버(DPS)에 붙어야 하는데, `SMHangul.rc` 는 `/etc/rc:524`
에서 조건 없이 띄우고 **윈도우서버는 rc 가 아니라 `init` 이 `/etc/ttys:22`
에서 띄운다**.  못 붙으면 `DPS Error: Can't connect to server` 를 syslog 에
남기고 죽는다.

이 문서는 **고치기 전에** 설계를 적어 둔 것이다.  코드는 이 계획이
교차검토를 통과한 뒤에 쓴다.

## 1. 실측한 전제 (전부 이 기계에서 확인)

| # | 사실 | 확인 방법 |
|---|---|---|
| P1 | 실패는 **관측 부팅 23회 중 6회(26%)** | `grep SMHangul /usr/adm/messages{,.old}` / 부팅 수는 `grep -c "Checking for DOS"` |
| P2 | 실패까지 걸리는 시간 **≤ 6 초** (세 번 모두 정확히 같은 상한) | `autonfsmount`(rc:320, InputManagers rc:524 보다 앞)의 syslog 시각과 DPS 에러 시각 차 |
| P3 | `$!` 동작 | `/tmp/shprobe.sh` §1 |
| P4 | `kill -0 <살아있는 pid>` = 성공, `<죽은 pid>` = 실패 | 같은 스크립트 §2·§3 |
| P5 | **`date +%s` 없음** (인자를 무시하고 usage 를 뱉는다) | 같은 스크립트 §4 |
| P6 | 백그라운드 서브셸이 끝나도 그 자식은 산다 | 같은 스크립트 §6 |
| P7 | 도구 경로: `/usr/bin/sleep`, `/bin/kill`, `/bin/expr`, `/usr/ucb/logger` (`/bin/sleep` 없음) | `ls -l` |
| P8 | `logger -p user.err` 은 `/usr/adm/messages` **와** `/dev/console` 양쪽에 닿는다.  `-p daemon.notice` 는 **닿지 않았다** | 실제로 한 줄씩 넣어 확인 |
| P9 | `SMHangul.rc` = `-rw-r--r-- root`, 234 B | `ls -l` |
| P10 | 패키지는 설치 디렉터리를 통째로 복사한다 → rc 수정이 자동으로 실린다 | `tools/build-fatpkg.sh:14` |

**P5 때문에 경과시간 산술을 쓸 수 없다.**  설계는 `sleep` 로만 시간을 센다.

## 2. 설계

rc 는 지금처럼 즉시 한 번 띄운다(성공 74% 는 그대로 지나간다).  달라지는
것은 **백그라운드 감시 서브셸**을 하나 붙이는 것뿐이다.

```
(한 번 띄운다) -> (SETTLE 초 기다린다) -> 살아 있나?
                                          예 -> 서브셸 종료 (앱은 고아로 계속 산다, P6)
                                          아니오 -> 로그 남기고 GAP 초 뒤 다시, 최대 TRIES 회
```

- 부팅을 **늦추지 않는다**: 감시 전체가 `&` 안에 있다.
- **원인을 몰라도 낫는다**: 왜 74% 는 붙는지 아직 모르지만(HANDOFF 참조),
  재시도는 그 답을 요구하지 않는다.
- 앱의 출력은 지금처럼 `/dev/console` 로 보낸다(현행 동작 보존).
  감시 루프 자신의 잡음(`kill` 의 "No such process", 잡 제어 메시지)만
  `/dev/null` 로 버린다.

### 상수

| 이름 | 값 | 근거 |
|---|---|---|
| `SETTLE` | **10** | 실패는 ≤6 초(P2).  4 초 여유.  이 값보다 늦게 죽는 실패는 감시 밖이다 — **알면서 두는 한계** |
| `GAP` | **4** | rc 가 끝나고 `init` 이 윈도우서버를 띄우기까지가 몇 초.  너무 짧으면 같은 실패를 반복한다 |
| `TRIES` | **12** | 최악 12×(10+4) = 168 초.  실패할 때만 걸리는 비용이고, 성공하면 10 초 만에 끝난다 |

### 초안 (ASCII 전용 — 이 기계의 `.strings` 인코딩 함정과 같은 이유)

```sh
#
# SMHangul startup script, run at boot time.
#
# The input server is an NSApplication, so it must reach the window
# server or it exits.  rc starts it (rc:524) before init starts the
# window server (ttys:22), so the connection is a race that this
# machine loses about one boot in four.  Launch it, and if it dies
# within SETTLE seconds, launch it again.
#
SMHANGUL=/NextLibrary/InputManagers/SMHangul/SMHangul.app/SMHangul
SETTLE=10
GAP=4
TRIES=12

echo -n " (SoftMagic Korean Input)" >/dev/console

(
    n=1
    while [ $n -le $TRIES ]; do
        $SMHANGUL >/dev/console 2>&1 &
        pid=$!
        /usr/bin/sleep $SETTLE
        if /bin/kill -0 $pid; then
            if [ $n -gt 1 ]; then
                /usr/ucb/logger -p user.err -t SMHangul.rc \
                    "input server came up on attempt $n"
            fi
            exit 0
        fi
        /usr/ucb/logger -p user.err -t SMHangul.rc \
            "input server died within ${SETTLE}s (attempt $n of $TRIES)"
        n=`/bin/expr $n + 1`
        /usr/bin/sleep $GAP
    done
    /usr/ucb/logger -p user.err -t SMHangul.rc \
        "input server did not stay up after $TRIES attempts"
) </dev/null >/dev/null 2>&1 &
```

## 3. 검증 계획

### 3.1 재부팅 없이 — 루프 논리 (스텁으로)

`SMHANGUL` 을 가짜 프로그램으로 바꿔 `/tmp` 에서 돌린다.  실기 시스템
파일은 건드리지 않는다.

| 스텁 | 기대 |
|---|---|
| 즉시 죽는다 | `TRIES` 회 시도하고 "did not stay up" 을 남긴다 |
| 3회째부터 산다 | 3회째에 멈추고 "came up on attempt 3" 을 남긴다 |
| 처음부터 산다 | 1회로 끝나고 **아무 로그도 남기지 않는다** (평소 부팅은 조용해야 한다) |
| 죽는 데 `SETTLE`+2 초 걸린다 | **감시가 못 잡는다** — 이 한계를 시험으로 못박아 둔다 |

시도 횟수는 스텁이 자기 실행 횟수를 파일에 적어 **세어서** 확인한다
(눈으로 세지 않는다).

### 3.2 재부팅으로 — 실제 판정

실패율이 26% 이므로 **1회 성공은 증거가 아니다.**

- 관측 부팅 n 회 전부 성공이면, "실패율이 여전히 26% 이상일 확률" 은
  `(1-6/23)^n`.  **n=8 이면 8.9%, n=10 이면 4.9%** (python 으로 계산).
- 그래서 **최소 8회, 되도록 10회** 재부팅을 목표로 한다.  사용자의 시간을
  쓰는 일이므로 다른 작업의 재부팅에 얹어서 센다.
- 각 부팅마다 두 줄만 보면 된다:
  - `grep SMHangul /usr/adm/messages` — DPS 에러가 있는데 **입력기는 떠
    있으면** 재시도가 먹은 것이다 (가장 강한 증거).
  - `ps -ax | grep SMHangul` — 프로세스 존재.

## 4. 되돌리기

`SMHangul.rc` 하나만 바뀐다.  원본을 `SMHangul.rc.orig-20260904` 로
남기고, 되돌리기는 `cp` 하나.  실패해도 최악은 **지금과 같은 상태**다
(감시 서브셸이 아무것도 못 해도 첫 기동은 현행과 동일하다).

## 5. 열린 위험

1. `SETTLE` 보다 늦게 죽는 실패는 못 잡는다.  P2 가 그런 실패를 본 적이
   없다는 것이 근거이고, 그 근거는 **6건**뿐이다.
2. 운영자가 부팅 직후 10초 안에 입력기를 일부러 죽이면 되살아난다.
   해롭지 않지만 놀랄 수 있다.
3. `logger` 가 `user.err` 로 가므로 재시도 로그는 **콘솔에도 뜬다**.
   조용한 부팅을 원하면 `-p` 를 바꿔야 하는데, `daemon.notice` 는 이
   기계에서 `/usr/adm/messages` 에 닿지 않았다(P8).
4. 이 rc 는 **시스템 파일**이다.  손대려면 허가와 백업이 먼저다.

---

## 6. codex 교차검토 판정 (2026-09-04, 코딩 전)

**회신을 요약해 옮기지 않는다.  전건을 실기/python 으로 검증한 결과만 적는다.**

| codex 주장 | 내 검증 방법 | 결과 |
|---|---|---|
| 문법은 대체로 유효 (`$!`, `( )&` 안의 `exit 0`, `${SETTLE}s`, 백쿼트 `expr`) | 실기 probe (`$!`·고아 생존·`[10s]` 출력 확인) | ✅ 사실 |
| **`kill -0` 이 좀비를 살아있다고 볼 수 있다** (codex 도 "확신 없다"고 밝힘) | **설계와 같은 모양**으로 실기 시험: 자식이 2초 뒤 스스로 죽고 부모는 `sleep 10` 중 → `kill -0` | ❌ **이 셸에서는 안 일어난다.** 부모가 `sleep` 을 기다리는 동안 자식을 거둔다.  비-자식(형제) 경우도 같음 |
| 로그 문구가 과장 — `kill -0` 은 liveness 지 readiness 가 아니다 | 문구 판단 | ✅ 채택 — "came up" → "still running after 10s" |
| **첫 기동은 오늘과 똑같이 두고, 감시만 백그라운드로 빼라** (성공하는 74% 를 건드리지 말 것) | 재구성이 실제로 되는지 실기 시험: 감시 서브셸이 **자기 자식이 아닌** pid 에 `kill -0` → 성공 | ✅ **채택.** 되는 길을 그대로 두는 쪽이 옳다 |
| 재시도 간격은 4초가 아니라 14초.  마지막 기동은 154 s, 판정 164 s, 최종 로그 168 s | python 으로 재계산 | ✅ 사실 (내 "12×(10+4)=168" 은 총 경과이지 마지막 기동 시각이 아니다) |
| 마지막 `GAP` 은 무의미하니 빼라 | 위 계산 (168 → 164) | ✅ 채택 — GAP 은 **다음 시도가 있을 때만** 잔다 |
| 복구가 `user.err` 라 정상 복구가 오류처럼 보인다 | `/etc/syslog.conf` 대조 + 실측: `*.err` 만 `/usr/adm/messages` 에 닿았고 `daemon.notice` 는 **양쪽 다 못 닿았다** | ⚖️ 부분채택 — 우선순위는 유지(대안이 실측으로 없다), 문구만 복구임이 드러나게 |
| PID 재사용으로 오탐 가능 | 반박: 창이 10초, 이 기계는 부팅 직후 PID 소모가 느리다 | ⚖️ 한계로 기록, 설계 변경 없음 |
| 셸만으로 윈도우서버 준비 판정 불가 | 내가 먼저 확인한 사실과 일치(netname 조회 CLI 없음) | ⏭ 행동 변화 없음 |

## 7. 확정안

```sh
#
# SMHangul startup script, run at boot time.
#
# The input server is an NSApplication, so it must reach the window
# server when it starts or it exits.  This script runs from /etc/rc
# line 524, but init does not start the window server until it reaches
# /etc/ttys line 22 -- which is after rc.  The connection is therefore
# a race, and this machine loses it on about one boot in four, leaving
# no Korean input server at all.
#
# So: start it exactly the way this script always did, then watch from
# the background.  If it is gone SETTLE seconds later, start it again,
# up to TRIES times.  The watcher never delays the boot, and on a boot
# that works it costs one sleeping shell for ten seconds and says
# nothing at all.
#
SMHANGUL=/NextLibrary/InputManagers/SMHangul/SMHangul.app/SMHangul
SETTLE=10
GAP=4
TRIES=12
LOG="/usr/ucb/logger -p user.err -t SMHangul.rc"

echo -n " (SoftMagic Korean Input)" >/dev/console

$SMHANGUL &
smpid=$!

(
    n=1
    while [ $n -le $TRIES ]
    do
        /usr/bin/sleep $SETTLE
        if /bin/kill -0 $smpid 2>/dev/null; then
            if [ $n -gt 1 ]; then
                $LOG "input server still running ${SETTLE}s after attempt $n"
            fi
            exit 0
        fi
        $LOG "input server was gone ${SETTLE}s after attempt $n of $TRIES"
        n=`/bin/expr $n + 1`
        if [ $n -le $TRIES ]; then
            /usr/bin/sleep $GAP
            $SMHANGUL >/dev/console 2>&1 &
            smpid=$!
        fi
    done
    $LOG "no Korean input server on this boot after $TRIES attempts"
) </dev/null >/dev/null 2>&1 &
```

**첫 기동 줄(`$SMHANGUL &`)은 현행과 글자 그대로 같다.**  성공하는 부팅에서
달라지는 것은 뒤에 붙는 감시 서브셸 하나뿐이고, 그것은 10초 자다가
아무 말 없이 사라진다.

## 8. 재부팅 없이 한 검증 — 통과 (2026-09-04)

`src/SMHangul.rc` 에서 **상수 7줄만** 치환한 사본으로 실기 `/tmp` 에서
돌렸다.  치환은 python 이 하고, **루프 본체가 한 글자도 안 바뀌었음을
프로그램이 확인**한 뒤에 시험했다(생성물끼리 비교하지 않기 위해).
시험용 상수는 `SETTLE=2 GAP=1 TRIES=4`.

| 시나리오(스텁) | 기동 횟수 | 로그 | 판정 |
|---|---|---|---|
| 처음부터 산다 (평소 부팅) | **1** | **없음** | ✅ 성공하는 부팅은 조용하다 |
| 계속 죽는다 | **4** (=TRIES) | 실패 4 + 포기 1 | ✅ 정확히 TRIES 에서 멈춘다 |
| 3회째부터 산다 | **3** | 실패 2 + "still running … attempt 3" | ✅ 붙으면 즉시 멈춘다 |
| `SETTLE`+2 초 뒤에 죽는다 | 1 | 없음 | ✅ **사각지대가 사각지대임을 확인** (§5-1) |

횟수는 스텁이 파일에 적은 줄을 **세어서** 확인했고, 기대값 대조는 python 이
했다.  네 시나리오 모두 기대와 일치.

## 9. 설치 기록 (2026-09-04)

```
백업 : /NextLibrary/InputManagers/SMHangul/SMHangul.rc.orig-20260904  (234 B, cp -p)
설치 : /NextLibrary/InputManagers/SMHangul/SMHangul.rc                (1770 B, 644 root)
검사 : sh -n  통과
       BSD sum 06708/2 — 저장소 원본을 python 으로 재계산한 값과 일치
```

되돌리기:

```sh
cp /NextLibrary/InputManagers/SMHangul/SMHangul.rc.orig-20260904 \
   /NextLibrary/InputManagers/SMHangul/SMHangul.rc
```

## 10. 남은 것 — 재부팅 판정

실패율 26% 라 **1회 성공은 증거가 아니다**(§3.2).  부팅마다 두 줄만 본다:

```sh
ps -ax | grep SMHangul          # 프로세스가 있나
grep SMHangul /usr/adm/messages # DPS 에러 / 재시도 로그
```

가장 강한 증거는 **`DPS Error` 가 있는데 프로세스는 살아 있는 부팅**이다 —
그것이 재시도가 실제로 구해 낸 장면이다.
