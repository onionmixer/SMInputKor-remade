/* tr2.m — 두벌식(Automata) 회귀 검증. keyboardLayout=0(기본) + setAutomata:1
 * → Automata(2벌). FrontEnd 경로로 2벌 입력이 여전히 올바른지 확인. */
#import <Foundation/Foundation.h>
#import "FrontEnd.h"

static void dump(const char *k, id s)
{
    int i, n = [s length];
    printf("  \"%s\" ->", k);
    for (i = 0; i < n; i++) printf(" U+%04X", [s characterAtIndex:i]);
    if (!n) printf(" (empty)");
    printf("\n");
}

static void run(id fe, const char *keys)
{
    int i;
    [fe setWorkingInit];
    [fe setAutomata:1];                  /* Korean ON, layout 0 → Automata(2벌) */
    for (i = 0; keys[i]; i++)
        [fe imProcessEvent:(unsigned short)(unsigned char)keys[i]];
    dump(keys, [fe inputString]);
}

int main(void)
{
    id pool = [[NSAutoreleasePool alloc] init];
    id fe = [[FrontEnd alloc] init];
    printf("== 두벌식 회귀 (keyboardLayout=0, Automata) ==\n");
    run(fe, "gks");        /* ㅎㅏㄴ = 한 U+D55C */
    run(fe, "gksrmf");     /* 한글 */
    run(fe, "rhk");        /* ㄱㅗㅏ = 과 U+ACFC (복모음) */
    run(fe, "rkqt");       /* ㄱㅏㅂㅅ = 값 U+AC12 (복종성) */
    run(fe, "gg");         /* 연속 ㅎㅎ */
    [pool release];
    return 0;
}
