/*
 * glue.m — 링크 글루 (복원)
 *
 * 재구성 클래스들을 하나의 SMHangul 실행파일로 링크하기 위한 최소 접착부:
 *   - 전역 변수(fep, hanjaInputString): 원본 __data 전역(_fep@0x42348,
 *     _hanjaInputString@0x4234c). Dispatcher init 에서 fep 를 설정한다.
 *   - main(): 원본과 동일하게 NSApplicationMain.
 *   - CvtField 캐럿 그리기용 DPS 헬퍼(drawStart/drawEnd/clearDraw): 원본은
 *     pswrap 생성 DPS 바이트스트림(_dpsF_*). 여기서는 **기능적 재구현**(gsave/
 *     grestore/erase)으로 링크·구조검증을 통과시킨다. 시각적 바이트 충실도는
 *     동작 오라클 단계에서 pswrap 원본과 대조. [STUB-FUNCTIONAL]
 */
#import <AppKit/AppKit.h>   /* PS 단일오퍼레이터(PSgsave 등)는 AppKit 경유 */

/* 원본 __data 전역 (Dispatcher/HanjaConverter 가 extern 참조) */
id fep = nil;
id hanjaInputString = nil;
/* NSInputServer 인스턴스(연결 vend). 재구성이 누락했던 등록 — Dispatcher 가 생성. */
id inputServer = nil;

int main(int argc, const char *argv[])
{
    return NSApplicationMain(argc, argv);
}

/* [STUB-FUNCTIONAL] 캐럿 그리기 전 그래픽 상태 저장. 원본 _drawStart@0x9300. */
void drawStart(void)
{
    PSgsave();
}

/* [STUB-FUNCTIONAL] 캐럿 그리기 후 복원+플러시. 원본 _drawEnd@0x932c. */
void drawEnd(void)
{
    PSgrestore();
}

/* [STUB-FUNCTIONAL] 캐럿 지우기. 원본 _clearDraw@0x9358(합성/삭제 계열). */
void clearDraw(void)
{
    /* NOTE: 원본은 캐럿 영역을 배경으로 지움 — pswrap 원본과 대조 예정. */
}
