/*
 * FrontEnd.h — 한글 조합 엔진/컨트롤러 (복원)
 *
 * SMHangul 의 조합 두뇌. Dispatcher(입력서버 델리게이트)가 받은 키를 여기서
 * Automata 로 조합하고, 조합중(marked)/확정 문자열을 만들며 KS↔Unicode 변환을
 * 수행한다. instance_size 0xa8, 14 ivar (__OBJC 실측).
 */
#import <Foundation/Foundation.h>
@class Automata;

@interface FrontEnd : NSObject
{
    id             myAutomata;          /* 현재 오토마타(Automata/NoCheckAutomata) */
    id             cvtWin;              /* 비인라인 조합창(LazyPanel)             */
    id             cvtField;            /* 조합중 표시 필드(CvtField)             */
    short          completeIndex;       /* 확정 버퍼 인덱스                        */
    short          charSize;            /* 문자 크기(1/2바이트 등)                 */
    char           working;            /* 조합 진행중 여부                        */
    char           inLineMode;          /* 인라인 모드 여부                        */
    char           conversion;          /* 변환(한자 등) 상태                      */
    int            inputUnit;           /* 입력 단위                               */
    int            keyboardLayout;      /* [ENHANCE] 0=두벌식 1=세벌390 2=세벌최종  */
    unsigned short save_unfn;           /* 미완성 코드 백업                        */
    unsigned short repeatHanja;         /* 한자 반복                               */
    unsigned short completeChar[32];    /* 확정 문자 버퍼                          */
    unsigned short afterString[32];     /* 커서 뒤 문자열                          */
    unsigned short astring[3];          /* 임시 문자열                             */
}

- initWithHanja:(char)hanja;
- (void)setAutomata:automata;
- (void)setWorkingInit;
- (void)setInputUnit:(int)unit;
- (void)setKeyboardLayout:(int)l;       /* [ENHANCE] 자판 선택(0/1/2) */
- (int)keyboardLayout;                   /* [ENHANCE] 현재 자판 */
- (BOOL)isJamoKey:(unsigned short)c;    /* [ENHANCE] 자판 라우팅: 이 키가 자모인지 */

- imProcessEvent:event;                 /* 이벤트 처리(핵심 파이프라인) */
- (int)imProcessBS;                     /* 백스페이스: 1=처리, 0=조합 없음 */
- makeReplaceString:arg;                /* marked/replace 문자열 생성   */
- inputString;
- (id)finalizedString;                  /* [ENHANCE] 확정 음절들(Character 단위) */
- (id)composingString;                  /* [ENHANCE] 조합중 음절 */
- (void)drainFinalized;                 /* [ENHANCE] 확정분 배출 */
- (BOOL)finalizedIsJamo;                /* [FIX] 확정분이 단독 자모인지(연속자음 버그) */
- makeInputNonAutomata;
- hanjaProc:arg;

- (int)currentPos;
- (int)afterStringLength;
- (void)cursorMoveLeft;
- (void)cursorMoveRight;
- (void)changeInputMode;
- (char)isWorking;
- (char)isInlineMode;
- (void)clearCvtField;
- (void)displayFEP;
- (void)orderOutFEP;
- (void)orderFrontFEP;
- (void)changedLanguage:(char)flag;

/* KS(완성형) ↔ Unicode 변환 — 정본 테이블 사용(현대 유니코드 알고리즘 대체 금지) */
- (unsigned short)unfinishedUnicode:(unsigned short)code;
- (unsigned short)ksFromUnicode:(unsigned short)uni;
- (unsigned short)unicodeFromKS:(unsigned short)ks;
- unicodeString:s;
- ksString:s;
- (char *)convertedToKSString:s length:(int *)len;   /* EUC-KR 바이트열(malloc), *len=길이 */

@end
