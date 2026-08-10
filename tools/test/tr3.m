/* tr3.m — 세벌식(NoCheckAutomata) 조합 트레이스 검증.
 * FrontEnd 의 imProcessEvent+makeReplaceString 경로를 UI 없이 재현해,
 * 키 시퀀스 → 확정(U+)/조합중([U+]) 결과를 출력한다. (C89: 선언 먼저) */
#import <Foundation/Foundation.h>
#import "NoCheckAutomata.h"

extern const unsigned short ks[];        /* KS→Unicode (automata_tables.m) */

static id A;
static unsigned short save_unfn;
static unsigned short complete[40];
static int ci;
static unsigned short astr;

static unsigned short cvt(unsigned short c)
{
    if (!c) return 0;
    if ((unsigned short)(c + 0x5B5F) > 0x5D) return ks[c - 0x8144];
    return (unsigned short)(c - 0x7370);
}

static void mkrep(int flag)
{
    unsigned short c, u;
    if (flag == 2) {
        if ([A isFinishAndRest]) {
            c = cvt(save_unfn);
            if (c && ci < 39) { complete[ci++] = c; complete[ci] = 0; }
        }
        c = [A unfn_code];
        if (c) { u = cvt(c); if (u) astr = u; }
    } else if (flag == 3) {
        c = cvt([A comp_code]);
        if (c && ci < 39) { complete[ci++] = c; complete[ci] = 0; }
    }
}

static void feed(int key)
{
    save_unfn = [A unfn_code];
    astr = 0;
    if ([A korean:(unsigned short)key]) {
        mkrep([A returnFlag]);
        mkrep([A restFlag]);
    }
}

static void run(const char *seq)
{
    int i;
    ci = 0; complete[0] = 0; astr = 0;
    [A automata_init];
    for (i = 0; seq[i]; i++) feed((unsigned char)seq[i]);
    printf("  \"%s\" ->", seq);
    for (i = 0; i < ci; i++) printf(" U+%04X", complete[i]);
    if (astr) printf(" [%04X]", astr);
    printf("\n");
}

static void runbs(const char *seq, int nbs)
{
    int i;
    unsigned short u;
    ci = 0; complete[0] = 0; astr = 0;
    [A automata_init];
    for (i = 0; seq[i]; i++) feed((unsigned char)seq[i]);
    for (i = 0; i < nbs; i++) {
        if ([A backCount] > 0) { u = [A reduceCount]; astr = cvt(u); }
        else { [A automata_init]; astr = 0; }
    }
    printf("  \"%s\" +%dBS ->", seq, nbs);
    if (astr) printf(" [%04X]", astr); else printf(" (empty)");
    printf("\n");
}

int main(void)
{
    id pool;
    NoCheckAutomata *a;
    pool = [[NSAutoreleasePool alloc] init];
    a = [[NoCheckAutomata alloc] init];
    [a setLayout:1];        /* 세벌식390 */
    [a automata_init];
    A = a;

    printf("== 세벌식390 ==\n");
    run("mfs");        /* ㅎㅏㄴ  = 한  U+D55C */
    run("kgw");        /* ㄱㅡㄹ  = 글  U+AE00 */
    run("mfskgw");     /* 한글 */
    run("kvf");        /* ㄱ+ㅗ+ㅏ(복모음ㅘ) = 과  U+ACFC */
    run("kfX");        /* ㄱㅏ+ㅄ(직접겹받침) = 값  U+AC12 */
    run("kf3q");       /* ㄱㅏ+ㅂ+ㅅ(결합겹받침) = 값 U+AC12 */
    run("kk");         /* 연속 초성 ㄱㄱ */
    run("f");          /* 단독 모음 ㅏ  U+3151 */
    run("x");          /* [codex#1] 종성키 ㄱ 단독 → ㄱ U+3131 (드롭 아님) */
    run("mx");         /* [codex#1] ㅎ + ㄱ단독 → U+314E U+3131 */
    run("kfXx");       /* [codex#1] 값 + ㄱ단독 → U+AC12 U+3131 (겹받침 실패 fallback) */
    runbs("mf", 1);    /* 하 → BS → ㅎ  [314E] */
    runbs("mfs", 1);   /* 한 → BS → 하  [D558] */
    runbs("mfs", 2);   /* 한 → 2BS → ㅎ [314E] */

    /* 세벌식최종(391): 소문자행은 390과 동일 → 한/글 동일. 구별 키 'E':
     * 최종 E=ㄵ(종성) → "jfE"=앉 U+C549 / 390 E=ㅋ(종성) → 앜 U+C55C. */
    printf("== 세벌식최종391 ==\n");
    [a setLayout:2];
    run("mfs");        /* 한 (동일) */
    run("jfE");        /* ㅇㅏㄵ = 앉 U+C549 (최종 고유 직접 겹받침) */
    printf("== (대조) 390 jfE ==\n");
    [a setLayout:1];
    run("jfE");        /* ㅇㅏㅋ = 앜 U+C55C */

    [pool release];
    return 0;
}
