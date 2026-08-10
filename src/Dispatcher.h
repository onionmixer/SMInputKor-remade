/*
 * Dispatcher.h — 앱 객체 + NSInputServer 델리게이트 (복원)
 *
 * SMHangul 의 최상위: NSApplication 서브클래스이면서 NSInputServer 의 델리게이트로
 * 입력서버 프로토콜(insertText:sender:conversation: 등)을 구현한다. 키/이벤트를
 * 받아 FrontEnd 로 넘기고, marked text/확정 문자열을 클라이언트에 반영하며 한자
 * 변환·환경설정·아이콘을 관장한다. instance_size 0x80, 16 ivar (__OBJC 실측).
 *
 * 델리게이트 프로토콜 시그니처는 SDK HexInputServer.h 로 대조 확정.
 */
#import <AppKit/AppKit.h>
@class FrontEnd, Preference, HanjaConverter;

@interface Dispatcher : NSApplication
{
    char       isTurnedOn;          /* 한글 입력 on/off        */
    NSImage   *engImage;            /* 영문 아이콘             */
    NSImage   *korImage;            /* 한글 아이콘             */
    int        initState;           /* 초기 모드               */
    int        hanjaArea;           /* 한자 영역 설정          */
    int        inputUnit;           /* 입력 단위               */
    int        hanjaRepeatCount;    /* 한자 반복 횟수          */
    int        hrepeatCount;        /* 한자 반복 현재값        */
    char       hanjaConversation;   /* 한자 변환 상태          */
    char       HANJA_MODE;          /* 한자 모드               */
    char       START_MODE;          /* 시작 모드               */
    char       ENTER_MODE;          /* 엔터 모드               */
    id         preference;          /* Preference              */
    id         hanjaConverter;      /* HanjaConverter          */
    id         textInput;           /* FrontEnd(조합 엔진)     */
    id         quitMenu;            /* 종료 메뉴               */
    char       layoutPending;       /* [ENHANCE] 조합중 자판변경 → 경계에서 적용 대기 */
}

+ (void)initialize;
- init;
- (void)changeIcon;
- (void)configPreferenceValue;

/* --- NSInputServer 델리게이트 프로토콜 (SDK 시그니처 대조) --- */
- (BOOL)canBeDisabled;
- (BOOL)wantsToInterpretAllKeystrokes;
- (void)setActivated:(BOOL)flag sender:(id)sender;
- (void)doCommandBySelector:(SEL)aSelector sender:(id)sender conversation:(long)conv;
- (void)insertText:(id)inString sender:(id)sender conversation:(long)conv;
- (void)markedTextWillBeAbandoned:(id)sender conversation:(long)conv;
- (void)markedTextSelectionChanged:(NSRange)newSel sender:(id)sender conversation:(long)conv;
- (void)cancelInput:(id)sender conversation:(long)conv;
- (void)activeConversationWillChange:(id)sender
                     oldConversation:(long)conv newConversation:(long)newConv;
- (void)senderDidBecomeActive:(id)sender;
- (void)senderDidResignActive:(id)sender;

/* --- marked text (NSInputServiceProvider) --- */
- (void)setMarkedText:(id)aString selectedRange:(NSRange)selRange;
- (BOOL)hasMarkedText;
- (void)unmarkText;
- (void)displayString:(id)s;
- makeCompleteChar:arg;

/* --- 한자 --- */
- (void)hanjaConvert:sender;
- applyHanja:hanja isComplete:(BOOL)complete;
- (unsigned short)unicodeFromKS:(unsigned short)ks;
- (unsigned short)ksFromUnicode:(unsigned short)uni;

/* --- 앱/메뉴 --- */
- (void)showPreference:sender;
- (void)terminate:sender;
- (void)applicationWillBecomeActive:(NSNotification *)note;
- (void)applicationDidFinishLaunching:(NSNotification *)note;
- (void)changeLanguage:sender;

@end
