/*
 * Automata.m — 한글 자모 조합 상태기계 (복원, 진행중)
 *
 * SMHangul 의 Automata 클래스 재구성. 각 메서드는 IDA 디컴파일을 근거로 clean
 * 재작성한다. 상태: [OK]=디컴파일 대조 완료, [INFER]=추정(대조 예정),
 * [TODO]=본문 미복원(주소 명기).
 *
 * 조합 원리(korean:): 입력 ASCII를 token_tbl로 토큰 분류 → act_tbl[5*status+token]
 * 로 액션(0~13)을 얻어 초/중/종성 상태를 전이. 결합은 make_two:::(cho·jung·jong→
 * 조합코드), search_code:(조합코드→EUC-KR), make_bokmo:::/make_bokja:::(복모음/
 * 복종성). back[] 링은 백스페이스 역분해용(saveBackUp/savePrevBack/clearBackUp).
 *
 * 데이터표는 소스에 내장하지 않고 정본에서 추출한 extern 리소스로 링크한다
 * (data/, PLAN §3.2 절차로 원소폭/인덱스/센티넬 검증 후 생성).
 */
#import "Automata.h"

/* --- 정본에서 추출할 조합/인코딩 테이블 (data/ 리소스) --- */
extern const unsigned short token_tbl[256];  /* ASCII→토큰 분류 */
extern const unsigned short cho_tbl[256];    /* ASCII→초성 인덱스 */
extern const unsigned short jung_tbl[256];   /* ASCII→중성 인덱스 */
extern const unsigned short jong_tbl[256];   /* ASCII→종성 인덱스 */
extern const unsigned short act_tbl[];       /* [status*5 + token]→액션 */
extern const unsigned short cho_two[];       /* 초성 단독 조합중 코드 */
extern const unsigned short moeum_two[];     /* 모음 단독 완성 코드 */
/* KS X 1001 완성형↔조합코드 매핑: 원본은 행별 배열(map_idx[32] 포인터 +
 * map_cnt[32] 카운트, 행 = 코드 비트10-14). 재구성은 행을 순서대로 이은 flat
 * 배열 map_codes[] 로 평탄화(행 시작 = 이전 행 카운트 누적). 표준에서 생성. */
extern const unsigned short map_codes[];     /* 모든 행 코드 연접(≈2350) */
extern const unsigned short map_cnt[32];     /* 행별 원소 수(행2~20 nonzero) */

/* make_two::: 비트팩킹 필드값 (자모 인덱스→비트필드) */
extern const unsigned short cho_val[];       /* 초성 비트필드(+0x8000) */
extern const unsigned short jung_val[];      /* 중성 비트필드 */
extern const unsigned short jong_val[];      /* 종성 비트필드 */
/* 복모음/복종성/복자음 결합표 (쌍 → 결합값) */
extern const unsigned short bok_mo1[13],    bok_mo2[13],    bok_mo[13];
extern const unsigned short bok_ja1[11],    bok_ja2[11],    bok_ja[11];
extern const unsigned short bok_jaeum1[11], bok_jaeum2[11], bok_jaeum[11];

@implementation Automata

/* [OK] 상태 초기화. cho=1,jung=2,jong=1 = "빈 자모" 센티넬. */
- automata_init
{
    rest_flag  = -1;
    ret_flag   = -1;
    finishRest = 0;
    cho  = 1;
    jung = 2;
    jong = 1;
    jaso_temp = 0;
    comp_code = 0;
    unfn_code = 0;
    asc_code  = 0;
    [self clearBackUp];
    status = 0;
    return self;
}

/*
 * [OK] 자모 1개 처리 — 핵심 상태기계.
 * korean: 디컴파일을 액션별로 충실히 재작성. 반환 1(처리됨). 행위 검증 대기.
 */
- (int)korean:(unsigned short)a3
{
    unsigned short prevCho, prevJung, prevJong;

    /* [FIX] 방어: 룩업표는 128 항목, act_tbl 은 토큰 0~4(5열)뿐. 범위 밖 입력
     * (a3>=128, 또는 제어문자처럼 token>=5)은 ASCII 통과로 처리해 OOB 접근을 막는다.
     * (실제로는 Dispatcher 가 영문자만 여기로 보내므로 정상 경로엔 도달하지 않음.) */
    if (a3 >= 128 || token_tbl[a3] >= 5) {
        finishRest = 0;
        asc_code = a3; ret_flag = 1; rest_flag = -1;
        cho = 1; jung = 2; jong = 1; status = 0;
        [self clearBackUp];
        return 1;
    }
    token  = token_tbl[a3];
    action = act_tbl[5 * status + token];
    finishRest = 0;

    switch (action) {
    case 0:                                   /* 모음 단독 완성 */
        cho = 1; jung = 2; jong = 1; status = 0;
        comp_code = moeum_two[jung_tbl[a3]];
        ret_flag = 3; rest_flag = -1;
        [self clearBackUp];
        return 1;

    case 1:                                   /* 비한글(ASCII 그대로) */
        asc_code = a3; ret_flag = 1; rest_flag = -1;
        cho = 1; jung = 2; jong = 1; status = 0;
        [self clearBackUp];
        return 1;

    case 2:                                   /* 초성 시작 */
        [self clearBackUp];
        cho = cho_tbl[a3]; jung = 2; jong = 1;
        unfn_code = cho_two[cho];
        ret_flag = 2; rest_flag = -1; status = 1;
        goto save_and_return;

    case 3:                                   /* 잔여 후 초성/모음 */
        [self clearBackUp];
        finishRest = 1; jung = 2; jong = 1; rest_flag = -1;
        if (token) {
            cho = cho_tbl[a3];
            unfn_code = cho_two[cho];
            ret_flag = 2; status = 1;
            goto save_and_return;
        }
        cho = 1; asc_code = a3; ret_flag = 1; status = 0;
        return 1;

    case 4:                                   /* 중성 결합(초성+중성) */
        jung = jung_tbl[a3];
        comb_code = [self make_two:cho :jung :1];
        unfn_code = [self search_code:comb_code];
        if (!unfn_code) goto rest_moeum;      /* 결합 실패 → 모음 단독 잔여 */
        ret_flag = 2; rest_flag = -1; jong = 1; status = 2;
        goto save_and_return;

    case 5:                                   /* 잔여 후 초성 */
        [self clearBackUp];
        ret_flag = 2; rest_flag = -1; finishRest = 1;
        cho = cho_tbl[a3]; unfn_code = cho_two[cho];
        jung = 2; jong = 1; status = 1;
        goto save_and_return;

    case 6:                                   /* 복모음 결합 */
        jung1 = jung_tbl[a3];
        if ([self make_bokmo:jung :jung1 :&bokmo] == -1) {
            finishRest = 1; unfn_code = 0;
            comp_code = moeum_two[jung_tbl[a3]];
            ret_flag = 2; rest_flag = 3;
            cho = 1; jung = 2; jong = 1; status = 0;
            [self clearBackUp];
            return 1;
        }
        comb_code = [self make_two:cho :bokmo :1];
        unfn_code = [self search_code:comb_code];
        if (!unfn_code) goto rest_moeum;
        jung = bokmo; ret_flag = 2; rest_flag = -1; status = 2;
        goto save_and_return;

    case 7:                                   /* 잔여 후 비한글 */
        ret_flag = 1; rest_flag = -1; finishRest = 1;
        asc_code = a3; unfn_code = 0;
        cho = 1; jung = 2; jong = 1; status = 0;
        [self clearBackUp];
        return 1;

    case 8:                                   /* 종성 결합 */
        save_jong = a3;
        jong = jong_tbl[a3];
        comb_code = [self make_two:cho :jung :jong];
        unfn_code = [self search_code:comb_code];
        if (unfn_code) {
            ret_flag = 2; rest_flag = -1; status = 3;
        } else {                              /* 종성 실패 → 새 초성 */
            [self clearBackUp];
            cho = cho_tbl[a3]; unfn_code = cho_two[cho];
            ret_flag = 2; rest_flag = -1; finishRest = 1;
            jung = 2; jong = 1; status = 1;
        }
        goto save_and_return;

    case 9:                                   /* 종성이 다음 음절 초성으로 이동 */
        prevCho = cho; prevJung = jung;
        cho = cho_tbl[save_jong];
        jung = jung_tbl[a3];
        comb_code = [self make_two:cho :jung :1];
        unfn_code = [self search_code:comb_code];
        if (!unfn_code) {
            comp_code = moeum_two[jung_tbl[a3]];
            finishRest = 1;
            cho = 1; jung = 2; jong = 1;
            ret_flag = 2; rest_flag = 3; status = 0;
            [self clearBackUp];
            return 1;
        }
        [self clearBackUp];
        comb_code = [self make_two:prevCho :prevJung :1];
        comp_code = [self search_code:comb_code];
        ret_flag = 3; rest_flag = 2; jong = 1; status = 2;
        [self savePrevBack];
        goto save_and_return;

    case 0xA:                                 /* 복종성 결합 */
        save_jong1 = a3;
        jong1 = jong_tbl[a3];
        if ([self make_bokja:jong :jong1 :&bokja] == -1) {
            [self clearBackUp];
            cho = cho_tbl[a3]; unfn_code = cho_two[cho];
            ret_flag = 2; rest_flag = -1; finishRest = 1;
            jung = 2; jong = 1; status = 1;
            goto save_and_return;
        }
        comb_code = [self make_two:cho :jung :bokja];
        unfn_code = [self search_code:comb_code];
        if (!unfn_code) {
            [self clearBackUp];
            ret_flag = 2; rest_flag = -1; finishRest = 1;
            cho = cho_tbl[a3]; unfn_code = cho_two[cho];
            jung = 2; jong = 1; status = 1;
            goto save_and_return;
        }
        ret_flag = 2; rest_flag = -1; status = 4;
        goto save_and_return;

    case 0xB:                                 /* 종성 확정 */
        [self clearBackUp];
        comb_code = [self make_two:cho :jung :jong];
        comp_code = [self search_code:comb_code];
        ret_flag = 2; rest_flag = -1;
        goto finish_new_cho;

    case 0xC:                                 /* 복종성이 다음 초성으로 이동 */
        prevCho = cho; prevJung = jung; prevJong = jong;
        cho = cho_tbl[save_jong1];
        jung = jung_tbl[a3];
        comb_code = [self make_two:cho :jung :1];
        unfn_code = [self search_code:comb_code];
        if (!unfn_code) {
            finishRest = 1;
            comp_code = moeum_two[jung_tbl[a3]];
            cho = 1; jung = 2; jong = 1;
            ret_flag = 2; rest_flag = 3; status = 0;
            [self clearBackUp];
            return 1;
        }
        [self clearBackUp];
        comb_code = [self make_two:prevCho :prevJung :prevJong];
        comp_code = [self search_code:comb_code];
        ret_flag = 3; rest_flag = 2; jong = 1; status = 2;
        [self savePrevBack];
        goto save_and_return;

    case 0xD:                                 /* 복종성 확정 후 새 초성 */
        [self clearBackUp];
        comb_code = [self make_two:cho :jung :bokja];
        comp_code = [self search_code:comb_code];
        rest_flag = -1; ret_flag = 2;
    finish_new_cho:
        finishRest = 1;
        cho = cho_tbl[a3]; unfn_code = cho_two[cho];
        jung = 2; jong = 1; status = 1;
        goto save_and_return;

    default:
        return 1;
    }

rest_moeum:                                   /* 결합 실패 공통 처리(LABEL_9) */
    finishRest = 1;
    comp_code = moeum_two[jung_tbl[a3]];
    ret_flag = 2; rest_flag = 3;
    cho = 1; jung = 2; jong = 1; status = 0;
    [self clearBackUp];
    return 1;

save_and_return:                              /* LABEL_35 */
    [self saveBackUp];
    return 1;
}

/*
 * [OK] 조합 완성 코드 → EUC-KR(KS X 1001 완성형) 바이트쌍.
 * 코드 비트10-14를 행으로 map_idx/map_cnt 조회, 94자/행 규칙으로 인코딩.
 * NOTE: map_idx 행별 인덱싱 구현은 테이블 추출 시 최종 확정.
 */
- (unsigned short)search_code:(unsigned short)code
{
    int row = (code & 0x7C00) >> 10;
    int i, pos, flat;
    unsigned short base;

    if (map_cnt[row]) {
        base = 0;                              /* 이 행의 flat 시작 오프셋 */
        for (i = 0; i < row; i++)
            base += map_cnt[i];
        for (pos = 0; pos < map_cnt[row]; pos++)
            if (map_codes[base + pos] == code) break;
        if (pos < map_cnt[row]) {
            flat = base + pos;                 /* KS X 1001 완성형 순번 */
            return (((unsigned short)(flat / 94) + 0xB0) << 8)
                 |  ((unsigned short)(flat % 94) + 0xA1);
        }
    }
    switch (code) {                           /* 표 밖 특수 음절 */
        case 0xB181: return 0xC9A3;
        case 0xB381: return 0xC9A4;
        case 0xBE61: return 0xC9A5;
        case 0x9DE1: return 0xC9A1;
        case 0xB0A1: return 0xC9A2;
    }
    return 0;
}

/* [OK] 백스페이스 역분해 백업 링 초기화 (count=-1, status 필드는 보존) */
- (void)clearBackUp
{
    int i;
    count = -1;
    for (i = 0; i < 5; i++) {
        back[i].cho  = 0;
        back[i].jung = 0;
        back[i].jong = 0;
        back[i].code = 0;
    }
}

/* [INFER] 단순 ivar 게터 — 본문 디컴파일로 대조 예정 */
- (unsigned short)comp_code  { return comp_code; }
- (unsigned short)unfn_code  { return unfn_code; }
- (unsigned short)asc_code   { return asc_code;  }
- (int)returnFlag            { return ret_flag;  }
- (int)restFlag              { return rest_flag; }
- (char)isFinishAndRest      { return finishRest; }
- (int)backCount             { return count; }

/* [ENHANCE] 이 키가 이 자판에서 자모(조합 대상)인지 — Dispatcher 라우팅용.
 * 두벌식(Automata): token_tbl 의 1~4(자음/모음). 0=통과, 5=제어. (세벌식은
 * NoCheckAutomata 가 자판 role 표로 override.) 라우팅을 하드코딩 A-Za-z 대신
 * 자판 인지로 — 세벌식최종의 숫자/기호 자모 키를 조합에 태우려면 필수. */
- (BOOL)isJamoKey:(unsigned short)c
{
    if (c >= 128) return NO;
    return token_tbl[c] >= 1 && token_tbl[c] <= 4;
}

/*
 * [OK] 자모 3요소 → 조합 16비트 코드. 초성 필드에 0x8000(조합 한글 표시) 세트,
 * 중성·종성 비트필드를 OR. (make_two:cho:jung:jong)
 */
- (unsigned short)make_two:(unsigned short)choIdx
                          :(unsigned short)jungIdx
                          :(unsigned short)jongIdx
{
    unsigned short v = cho_val[choIdx];
    v |= 0x8000;                       /* HIBYTE |= 0x80 */
    return jong_val[jongIdx] | jung_val[jungIdx] | v;
}

/* [OK] 복모음 결합: (a,b) 쌍을 bok_mo 표에서 찾아 *out에 결합값, 0; 실패 -1. */
- (int)make_bokmo:(unsigned short)a :(unsigned short)b :(unsigned short *)dst
{
    int i;
    for (i = 0; i < 13; i++)
        if (bok_mo1[i] == a && bok_mo2[i] == b) { *dst =bok_mo[i]; return 0; }
    return -1;
}

/* [OK] 복종성 결합(받침 두 자음). */
- (int)make_bokja:(unsigned short)a :(unsigned short)b :(unsigned short *)dst
{
    int i;
    for (i = 0; i < 11; i++)
        if (bok_ja1[i] == a && bok_ja2[i] == b) { *dst =bok_ja[i]; return 0; }
    return -1;
}

/* [OK] 복자음 결합. */
- (int)make_bokjaeum:(unsigned short)a :(unsigned short)b :(unsigned short *)dst
{
    int i;
    for (i = 0; i < 11; i++)
        if (bok_jaeum1[i] == a && bok_jaeum2[i] == b) { *dst =bok_jaeum[i]; return 0; }
    return -1;
}

/* [OK] 백업 링 push — 현재 조합 상태 저장(백스페이스 역분해용). */
- (void)saveBackUp
{
    ++count;
    back[count].cho    = cho;
    back[count].jung   = jung;
    back[count].jong   = jong;
    back[count].status = status;
    back[count].code   = unfn_code;
}

/* [OK] 종성→다음 초성 이동 시, 새 초성 상태를 링에 push. */
- (void)savePrevBack
{
    ++count;
    back[count].cho    = cho;
    back[count].jung   = 2;
    back[count].jong   = 1;
    back[count].status = 1;
    back[count].code   = cho_two[cho];
}

/* [OK] 백스페이스 역분해 — 링 pop, 직전 조합 상태 복원. unfn_code 반환. */
- (unsigned short)reduceCount
{
    if (count <= 0) {           /* [FIX] 방어: 언더플로(back[-1]) 방지. 호출부(imProcessBS
                                 * backCount>0)가 보장하지만 API 안전을 위해 가드. */
        count = -1;
        return unfn_code;
    }
    --count;
    cho    = back[count].cho;
    jung   = back[count].jung;
    jong   = back[count].jong;
    status = back[count].status;
    unfn_code = back[count].code;
    return unfn_code;
}

@end
