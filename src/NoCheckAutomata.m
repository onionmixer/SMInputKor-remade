/*
 * NoCheckAutomata.m — 세벌식(3-set) 조합 오토마타 (재작성 [ENHANCE])
 *
 * 세벌식은 키가 초/중/종성 위치 고정(libhangul JASO 처리와 동형):
 *   - 받침 이월 없음. 초성이 (완성 음절/초성 뒤에) 오면 현재 확정 후 새 음절 시작.
 *   - 복모음(중성+중성)·복종성(종성+종성)은 결합표(make_bokmo/make_bokja).
 *   - 최종은 겹받침을 단일 키로도 입력(테이블의 jong 인덱스가 곧 겹받침).
 *   - 단독 자모(초성 없는 중성 등)는 단독 표시코드로 확정.
 * layout(390/최종)별 키→자모 표는 layout_tables.m(gen_layouts.py 생성).
 * 조합/인코딩·백업링은 Automata 상속.
 * 상태 status: 0 빈 / 1 초성 / 2 초성+중성 / 3 완성(+종성).
 */
#import "NoCheckAutomata.h"

/* 자판별 자모 매핑(role:0통과 1초 2중 3종 / cho·jung·jong: Johab 인덱스) */
extern const unsigned short lyRole_390[128], lyCho_390[128], lyJung_390[128], lyJong_390[128];
extern const unsigned short lyRole_Fin[128], lyCho_Fin[128], lyJung_Fin[128], lyJong_Fin[128];
/* 종성 단독 자음 표시코드(ASCII 인덱스, 0=비종성). jaeum_two 는 CHO 인덱스라 Johab jong
 * 인덱스로 못 쓰므로 자판별 ASCII→표준자음코드 표를 별도 사용. */
extern const unsigned short lyJongTwo_390[128], lyJongTwo_Fin[128];
/* 단독 표시코드(Automata 공용) */
extern const unsigned short twoOfCho[32];    /* 초성 단독 */
extern const unsigned short moeum_two[32];   /* 중성 단독 */

@implementation NoCheckAutomata

/* 자판 선택(1=390, 2=최종). 그 외 값은 390 으로 클램프. */
- (void)setLayout:(int)l { layout = (l == 2) ? 2 : 1; }

/* 상태 초기화(백업 링 포함 — 3벌 백스페이스 지원). */
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
    if (!layout) layout = 1;
    return self;
}

/* 이 키가 현재 세벌식 자판에서 자모인지(라우팅용). role!=0. */
- (BOOL)isJamoKey:(unsigned short)c
{
    const unsigned short *ROLE = (layout == 2) ? lyRole_Fin : lyRole_390;
    return (c < 128) && (ROLE[c] != 0);
}

/*
 * 세벌식 조합 상태기계. 반환 1(처리). save_unfn(FrontEnd 가 korean: 직전 포착)+
 * finishRest 로 직전 조합을 확정(makeReplaceString flag2), 새 unfn_code 를 조합중 표시.
 */
- (int)korean:(unsigned short)a3
{
    const unsigned short *ROLE = (layout == 2) ? lyRole_Fin : lyRole_390;
    const unsigned short *CHO  = (layout == 2) ? lyCho_Fin  : lyCho_390;
    const unsigned short *JUNG = (layout == 2) ? lyJung_Fin : lyJung_390;
    const unsigned short *JONG = (layout == 2) ? lyJong_Fin : lyJong_390;
    const unsigned short *JTWO = (layout == 2) ? lyJongTwo_Fin : lyJongTwo_390;
    unsigned short ci, ji, gi, comb, u, bok;
    int role;

    finishRest = 0;

    /* 비자모/범위밖: ASCII 통과(라우팅이 걸러야 하나 방어). */
    if (a3 >= 128 || ROLE[a3] == 0) {
        asc_code = a3; ret_flag = 1; rest_flag = -1;
        cho = 1; jung = 2; jong = 1; status = 0; [self clearBackUp];
        return 1;
    }
    role = ROLE[a3];

    /* ── 초성 ── */
    if (role == 1) {
        ci = CHO[a3];
        if (status != 0)                 /* 조합 중 → 직전 확정 후 새 음절 */
            finishRest = 1;
        [self clearBackUp];
        cho = ci; jung = 2; jong = 1;
        unfn_code = twoOfCho[ci];
        ret_flag = 2; rest_flag = -1; status = 1;
        [self saveBackUp];
        return 1;
    }

    /* ── 중성 ── */
    if (role == 2) {
        ji = JUNG[a3];
        if (status == 1) {               /* 초성 + 중성 */
            jung = ji;
            comb = [self make_two:cho :jung :1];
            u = [self search_code:comb];
            if (u) {
                unfn_code = u; ret_flag = 2; rest_flag = -1; status = 2;
                [self saveBackUp];
                return 1;
            }
        } else if (status == 2) {         /* 복모음(중성+중성) */
            if ([self make_bokmo:jung :ji :&bok] != -1) {
                comb = [self make_two:cho :bok :1];
                u = [self search_code:comb];
                if (u) {
                    jung = bok; unfn_code = u; ret_flag = 2; rest_flag = -1; status = 2;
                    [self saveBackUp];
                    return 1;
                }
            }
        }
        /* 그 외(status 0/3, 조합 불가, 복모음 아님): 현재 확정(있으면) + 중성 단독 완성.
         * Automata rest_moeum 과 동형: 잔여 있으면 ret2(save_unfn 확정)+rest3(모음),
         * 없으면 ret3 단독(rest_flag=-1 — 이중 커밋 방지). */
        comp_code = moeum_two[ji];
        if (status != 0) {
            finishRest = 1; unfn_code = 0;
            ret_flag = 2; rest_flag = 3;
        } else {
            ret_flag = 3; rest_flag = -1;
        }
        cho = 1; jung = 2; jong = 1; status = 0;
        [self clearBackUp];
        return 1;
    }

    /* ── 종성 ── */
    gi = JONG[a3];
    if (status == 2) {                    /* 초성+중성 + 종성 */
        jong = gi;
        comb = [self make_two:cho :jung :jong];
        u = [self search_code:comb];
        if (u) {
            unfn_code = u; ret_flag = 2; rest_flag = -1; status = 3;
            [self saveBackUp];
            return 1;
        }
    } else if (status == 3) {             /* 겹받침(두 종성키) */
        if ([self make_bokja:jong :gi :&bok] != -1) {
            comb = [self make_two:cho :jung :bok];
            u = [self search_code:comb];
            if (u) {
                jong = bok; unfn_code = u; ret_flag = 2; rest_flag = -1; status = 3;
                [self saveBackUp];
                return 1;
            }
        }
    }
    /* 그 외(종성 놓을 자리 없음/조합 불가): 현재 확정(있으면) + 종성 단독 자음 완성.
     * [FIX codex#1] 예전엔 잉여 종성을 드롭 → (a) 자음 소실, (b) 조합 없는데 working=1
     * 되어 다음 백스페이스가 문서 텍스트를 지우는 데이터 손실. 이제 모음 fallback 과
     * 동형으로 단독 자음(JTWO)을 확정한다. (JTWO[a3] 는 종성키면 항상 비0.) */
    comp_code = JTWO[a3];
    if (status != 0) {
        finishRest = 1; unfn_code = 0;
        ret_flag = 2; rest_flag = 3;
    } else {
        ret_flag = 3; rest_flag = -1;
    }
    cho = 1; jung = 2; jong = 1; status = 0;
    [self clearBackUp];
    return 1;
}

@end
