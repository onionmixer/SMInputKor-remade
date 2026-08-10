/* bstest.m — 백스페이스 역분해 검증. argv[1]=키열, argv[2]=백스페이스 횟수. */
#import <Foundation/Foundation.h>
#import "FrontEnd.h"

static void dump(const char *t, id s){int i,n=[s length];printf("%s: ",t);for(i=0;i<n;i++)printf("U+%04X ",[s characterAtIndex:i]);if(!n)printf("(empty)");printf("\n");}

int main(int argc, char **argv)
{
    id pool=[[NSAutoreleasePool alloc] init];
    id fe=[[FrontEnd alloc] init];
    const char *keys=(argc>1)?argv[1]:"gks";
    int nbs=(argc>2)?atoi(argv[2]):3;
    int i;
    [fe setAutomata:0];
    for(i=0;keys[i];i++) [fe imProcessEvent:(unsigned short)(unsigned char)keys[i]];
    printf("after keys '%s':\n",keys); dump("  input",[fe inputString]);
    for(i=0;i<nbs;i++){
        int r=[fe imProcessBS];
        printf("BS#%d ret=%d backCount=%d\n",i+1,r,0);
        dump("  input",[fe inputString]);
    }
    [pool release]; return 0;
}
