/* isJamoKey(2벌) 가 기존 게이트 !((c-'A')>25 && (c-'a')>25) 와 전수 동치인지 검증 */
#import <Foundation/Foundation.h>
#import "Automata.h"
int main(void){
  id p; id a; int c,mismatch=0;
  p=[[NSAutoreleasePool alloc]init]; a=[[Automata alloc]init]; [a automata_init];
  for(c=0;c<128;c++){
    int oldgate = !(((unsigned short)(c-'A')>25) && ((unsigned short)(c-'a')>25)); /* 기존=자모취급 */
    int neu = [a isJamoKey:(unsigned short)c] ? 1:0;
    if(oldgate!=neu){ printf("MISMATCH c=%d(%c) old=%d new=%d\n",c,(c>=32&&c<127)?c:'.',oldgate,neu); mismatch++; }
  }
  printf(mismatch? "FAIL %d mismatches\n":"OK: 0~127 전수 동치(회귀 없음)\n",mismatch);
  [p release]; return 0;
}
