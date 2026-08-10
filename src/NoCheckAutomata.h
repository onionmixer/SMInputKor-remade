/*
 * NoCheckAutomata.h — 세벌식(3-set) 조합 오토마타 (재작성 [ENHANCE])
 *
 * 원래는 Automata 의 무검사 2벌 변형이었으나, 세벌식(390/최종) 지원을 위해
 * 3벌 전용 상태기계로 재작성한다. 세벌식은 키가 초/중/종성으로 위치 고정이라
 * 분류·받침이월이 불필요(libhangul JASO 처리와 동일)하고, layout(390/최종)별
 * 키→자모 표(layout_tables.m)를 참조한다. 조합/인코딩 헬퍼(make_two/search_code/
 * make_bokmo/make_bokja)와 백업 링(saveBackUp/reduceCount/clearBackUp)은 Automata 상속.
 */
#import "Automata.h"

@interface NoCheckAutomata : Automata
{
    int layout;             /* [ENHANCE] 1=세벌식390, 2=세벌식최종 */
}
- (void)setLayout:(int)l;   /* 자판 선택 → 참조 표 결정 */
- automata_init;
- (int)korean:(unsigned short)code;
@end
