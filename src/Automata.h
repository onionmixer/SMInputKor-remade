/*
 * Automata.h — 한글 자모 조합 상태기계 (복원)
 *
 * SMHangul.app 의 Automata 클래스를 __OBJC 메타데이터(ivar 레이아웃/셀렉터)
 * 에서 재구성한 인터페이스. instance_size 0x74, 24 ivar. 메서드 시그니처의
 * 인자/반환 타입은 메서드 타입 인코딩 + 본문 디컴파일로 확정해 나간다(진행중).
 *
 * 조합 원리: ASCII 키코드를 token/cho/jung/jong 룩업표(_token_tbl/_cho_tbl/
 * _jung_tbl/_jong_tbl)로 분류하고, 초성(cho)·중성(jung,복모음 bokmo)·종성
 * (jong,복자음 bokja)을 상태에 누적하며 음절을 조합한다. back[]은 백스페이스
 * 역분해용 백업 링.
 */
#import <Foundation/Foundation.h>

/* ivar `back` = [5{backup="cho"S"jung"S"jong"S"status"S"code"S}] */
typedef struct backup {
    unsigned short cho;
    unsigned short jung;
    unsigned short jong;
    unsigned short status;
    unsigned short code;
} backup;

@interface Automata : NSObject
{
    unsigned short token;       /* 현재 입력 토큰 분류          */
    unsigned short action;      /* 액션 코드(_act_tbl 결과)      */
    unsigned short status;      /* 조합 상태                     */
    int            count;       /* 조합된 자모 수                */
    unsigned short cho;         /* 초성                          */
    unsigned short jung;        /* 중성                          */
    unsigned short jung1;       /* 중성(복모음 1요소)            */
    unsigned short bokmo;       /* 복모음                        */
    unsigned short jong;        /* 종성                          */
    unsigned short jong1;       /* 종성(복자음 1요소)            */
    unsigned short bokja;       /* 복자음(받침)                  */
    int            ret_flag;    /* 반환(확정) 플래그             */
    int            rest_flag;   /* 잔여 플래그                   */
    int            jaso_flag;   /* 자소 플래그                   */
    int            bokjaeum;    /* 복자음 상태                   */
    unsigned short asc_code;    /* 원 ASCII                      */
    unsigned short unfn_code;   /* 미완성(조합중) 코드           */
    unsigned short comp_code;   /* 완성 코드                     */
    unsigned short jaso_temp;   /* 자소 임시                     */
    unsigned short comb_code;   /* 조합 코드                     */
    unsigned short save_jong;   /* 종성 백업                     */
    unsigned short save_jong1;  /* 종성 백업                     */
    char           finishRest;  /* 마감/잔여 상태                */
    backup         back[5];     /* 백스페이스 역분해 백업 링     */
}

- automata_init;                             /* 상태 초기화 */
- (int)korean:(unsigned short)code;          /* 자모 1개 처리(핵심 진입) */

- (unsigned short)search_code:(unsigned short)code;   /* 조합코드→EUC-KR */
/* 초·중·종성 결합 → 조합코드 */
- (unsigned short)make_two:(unsigned short)cho :(unsigned short)jung :(unsigned short)jong;
/* 두 자모 결합 시도: 성공 시 *dst에 결합값, 반환 0; 실패 시 -1 (실측 시그니처).
 * 파라미터명 'out'은 ObjC DO 타입한정자 키워드라 파스 에러 → 'dst' 사용. */
- (int)make_bokja:(unsigned short)a :(unsigned short)b :(unsigned short *)dst;
- (int)make_bokjaeum:(unsigned short)a :(unsigned short)b :(unsigned short *)dst;
- (int)make_bokmo:(unsigned short)a :(unsigned short)b :(unsigned short *)dst;

- (void)saveBackUp;
- (void)savePrevBack;
- (void)clearBackUp;
- (unsigned short)reduceCount;   /* 백스페이스 역분해: 복원된 unfn_code 반환 */
- (int)backCount;
- (BOOL)isJamoKey:(unsigned short)c;    /* [ENHANCE] 자판 라우팅: 이 키가 자모인지 */

- (int)returnFlag;
- (int)restFlag;
- (char)isFinishAndRest;
- (unsigned short)comp_code;
- (unsigned short)unfn_code;
- (unsigned short)asc_code;

@end
