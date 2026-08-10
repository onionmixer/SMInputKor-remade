/*
 * CvtField.h — 조합중 텍스트 표시 필드 + 캐럿 (복원)
 *
 * NSTextField 서브클래스. 조합중(marked) 문자열을 보여주고 깜빡이는 캐럿을
 * DPS(_PSmoveto/_PSrlineto/_PSstroke)로 직접 그린다. instance_size 0x6c, 2 ivar.
 */
#import <AppKit/AppKit.h>

@interface CvtField : NSTextField
{
    float caret;         /* 캐럿 x 위치 */
    int   cursorState;   /* 캐럿 표시 상태(깜빡임) */
}
- initWithFrame:(NSRect)frame;
- (BOOL)acceptsFirstResponder;
- (void)drawCaret:sender;
- (void)setCaret:(float)x;
- (void)showCaret;
- (void)hideCaret;
@end
