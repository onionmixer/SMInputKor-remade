/*
 * HanjaConverter.h — 한자 변환 (복원)
 *
 * 한글 음절을 한자 후보로 변환. 내장 코드표(_SMcode_Hanja_Table)와 외부 사용자
 * 사전(systemDictionary, dictionaryWithContentsOfFile:) 양쪽을 조회하고 브라우저/
 * 매트릭스 UI로 후보를 제시한다. NSObject, instance_size 0x40, 15 ivar.
 *
 * 메서드 목록은 __OBJC method_imp 재확인으로 보강 예정(현재는 nib 액션 +
 * 사전 관련 추정). Hanja.nib 액션: changeHangul:/changeHanja:/hanjapanel:.
 */
#import <AppKit/AppKit.h>

@interface HanjaConverter : NSObject
{
    id  browser;                        /* 후보 브라우저 */
    id  matrix;
    id  panel;
    id  radio;
    id  scrollView;
    id  wordpanel;
    id  dispatcher;                     /* Dispatcher 역참조 */
    id  preference;
    id  resp;
    NSMutableDictionary *systemDictionary;  /* 외부 한자 사전 */
    NSString            *pathString;        /* 사전 경로 */
    NSString            *oldPathString;
    NSArray             *wordArray;         /* 현재 후보 목록 */
    unsigned int         cell_pos;
    unsigned int         cell_old;
}
- (void)setDispatcher:d;
- (void)setResp:r;
/* 조회: 단일 한글자→한자 후보 / 단어→한자 후보(내장 SMcode_Hanja_Table + 외부 사전) */
- hanjaWithString:s index:(unsigned)idx;
- hanjaWithStrings:s index:(unsigned)idx;
- findWord:s index:(unsigned)idx;
- (void)clearWordArray;
/* 후보 패널 UI */
- (void)hanjapanel:s index:(unsigned)idx;
- frontHanja:(unsigned short)ks;
- (void)orderOutPanel:sender;
- (void)_initMatrixWithFont:(int)row;   /* 이름과 달리 실인자는 한자표 행 인덱스 */
/* nib 액션 */
- (void)changeHangul:sender;
- (void)changeHanja:sender;
/* NSBrowser 델리게이트 */
- (int)browser:sender createRowsForColumn:(int)col inMatrix:matrix;
@end
