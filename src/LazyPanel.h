/*
 * LazyPanel.h — 비인라인 조합/후보 패널 (복원)
 *
 * NSPanel 서브클래스. 키/메인 윈도우가 되지 않고 포커스를 빼앗지 않도록
 * 재정의(입력서버 특성상 클라이언트 앱이 키를 유지해야 함). ivar 추가 없음.
 */
#import <AppKit/AppKit.h>

@interface LazyPanel : NSPanel
{
}
- (BOOL)canBecomeKeyWindow;
- (BOOL)canBecomeMainWindow;
- (BOOL)acceptsFirstResponder;
- (void)makeKeyWindow;
- (void)sendEvent:(NSEvent *)event;
@end
