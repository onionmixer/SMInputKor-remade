/*
 * LazyPanel.m — 비인라인 조합/후보 패널 (복원)
 *
 * NSPanel 서브클래스. 입력서버 특성상 클라이언트 앱이 키 포커스를 유지해야 하므로
 * 이 패널은 키/메인 윈도우가 되지 않고 포커스를 빼앗지 않는다. IDA 디컴파일 대조
 * ([OK]) / 추정([INFER]).
 */
#import "LazyPanel.h"

@implementation LazyPanel

/* [OK] 키 윈도우가 되지 않는다(포커스 비획득). */
- (BOOL)canBecomeKeyWindow { return NO; }

/* [INFER] 메인 윈도우도 되지 않는다(canBecomeKeyWindow 와 동일 패턴). */
- (BOOL)canBecomeMainWindow { return NO; }

/* [INFER] first responder 비획득. */
- (BOOL)acceptsFirstResponder { return NO; }

/* [INFER] 키 윈도우 만들기 무력화(클라이언트 포커스 유지). */
- (void)makeKeyWindow { }

/*
 * [OK] 이벤트를 상위에 넘긴 뒤 NSApp(Dispatcher)에 콜백.
 * NOTE: NSApp 호출 셀렉터(dword_5857C)는 포커스 반환/앱 비활성 유지 계열로 추정 —
 * 최종 확인 후 확정.
 */
- (void)sendEvent:(NSEvent *)event
{
    [super sendEvent:event];
    [NSApp /* NOTE: 셀렉터 확인 */ deactivate];
}

@end
