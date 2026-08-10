/*
 * CvtField.m — 조합중 텍스트 표시 필드 + 깜빡이는 캐럿 (복원)
 *
 * NSTextField 서브클래스. 비인라인 모드에서 조합중(marked) 문자열을 보여주고,
 * DPS(PSmoveto/PSrlineto/PSstroke)로 세로 캐럿을 직접 그린다. IDA 디컴파일 대조
 * ([OK]) / 추정([INFER]).
 */
#import "CvtField.h"

@implementation CvtField

/*
 * [OK] 비편집·비선택·테두리 필드로 초기화, 20pt 한글 폰트 설정, caret=0.
 * (setEditable:/setSelectable:/setBordered: 인자 0,0,1 로 관찰 — 선택자명은 추정.)
 * NOTE: 폰트명은 원본 off_5E03C 문자열(한글 폰트) — 최종 확인 후 확정.
 */
- initWithFrame:(NSRect)frame
{
    id font;
    [super initWithFrame:frame];
    [self setEditable:NO];
    [self setSelectable:NO];
    [self setBordered:YES];
    caret = 0.0;
    font = [NSFont fontWithName:@"Gothic-Medium" /*NOTE: off_5E03C 확인*/ size:20.0];
    if (!font)
        font = [NSFont systemFontOfSize:20.0];
    [self setFont:font];
    return self;
}

/* [INFER] 캐럿 표시 필드 — 포커스 비획득(대조 예정). */
- (BOOL)acceptsFirstResponder
{
    return NO;
}

/*
 * [OK] 세로 캐럿을 DPS로 그린다. x = 20*caret + 5, y=5, 높이 20.
 * mode 0 = 그리기, 1 = 지우기(clearDraw). lockFocus/unlockFocus 로 감싼다.
 */
- (void)drawCaret:(int)mode
{
    float x = 20.0 * caret + 5.0;
    [self lockFocus];
    if (mode) {
        if (mode == 1)
            clearDraw();
    } else {
        drawStart();
        PSsetgray(NSBlack);
        PSmoveto(x, 5.0);
        PSrlineto(0.0, 20.0);
        PSstroke();
        drawEnd();
    }
    [self unlockFocus];
}

/* [OK] 캐럿 위치 설정 후 표시. */
- (void)setCaret:(float)x
{
    caret = x;
    [self showCaret];
}

/* [OK] */
- (void)showCaret { [self drawCaret:0]; }

/* [INFER] showCaret 의 대칭 — 지우기(drawCaret:1). */
- (void)hideCaret { [self drawCaret:1]; }

/* [OK] 상위 dealloc(추가 해제 없음). */
- (void)dealloc { [super dealloc]; }

@end
