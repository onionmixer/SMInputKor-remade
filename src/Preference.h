/*
 * Preference.h — 환경설정 (복원)
 *
 * 입력 단위/초기 모드/한자 영역/한자 반복/인라인·색상, 그리고 한자 사전 경로
 * (외부 파일)를 관리. 설치된 입력기 목록(InputManagers/ * /Info)을 읽어들인다.
 * NSObject, instance_size 0x48, 17 ivar (대부분 아웃렛 id). 아웃렛 이름은 nib
 * data.classes 와 일치.
 */
#import <AppKit/AppKit.h>

@interface Preference : NSObject
{
    id  initState;              /* 초기 모드 체크박스 */
    id  keyboardType;           /* [ENHANCE] 자판 라디오 매트릭스(0/1/2) */
    id  hanjaArea;
    id  panel;
    id  inputUnit;
    id  hanjaRepeatCount;
    id  textColor;
    id  hanjaConversion;
    id  engKorSelectPopUp;
    id  hanjaSelectPopUp;
    id  inlineWinSelectPopUp;
    id  attributePopUp;
    id  colorWell;
    id  dictionaryPathTF;       /* 한자 사전 경로 텍스트필드 */
    id  dictionaryListPU;       /* 사전 목록 팝업 */
    NSMutableArray      *_imArray;    /* 설치된 입력기 목록 */
    NSMutableDictionary *_imMap;
    NSString            *imDictPath;  /* 입력기 사전 경로 */
}
- init;
- (void)showUI;
- (void)buildKeyboardTypeUI;            /* [ENHANCE] 자판 라디오 코드 구성 */
- (void)changeKeyboardType:sender;      /* [ENHANCE] 자판 라디오 액션 */
- (void)loadInputManagerInfo;
- (void)setPopUpWithKeyBindingDictionaray:dict andKey:key;  /* 원본 오타 셀렉터 보존 */
- (void)rebindAction:(NSString *)action toKey:(const char *)key;  /* [FIX] 자판사전 재바인딩 */
- (void)repairKeyBindings;                       /* [FIX] 손상 dict 자동 교정 */
- (BOOL)isEditingAction:(NSString *)a;           /* [FIX] 보호 대상 편집 액션 */
- (int)indexWithKey:key;
- (void)changeAttributeType:sender;
- (void)revertDefaults:sender;
- (void)writeToUserDefaults:(NSMutableDictionary *)defaults;
- (void)writeGlobalDefaults:sender;
- (void)writeDefaults:sender;
- (void)updateDictionaryPopUpButton:sender;
- (void)setPath:sender;
- dictionaryName;
- (void)dealloc;
@end
