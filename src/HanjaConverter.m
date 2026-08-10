/*
 * HanjaConverter.m — 한자 변환 (복원, 진행중)
 *
 * 한글 음절을 한자 후보로 변환하고 후보를 브라우저/매트릭스 UI로 제시한다.
 * 조회원: 내장 코드표 SMcode_Hanja_Table(정본 추출 리소스, data/) + 외부 사용자
 * 사전(systemDictionary, dictionaryWithContentsOfFile:). 각 메서드는 IDA 디컴파일
 * 대조([OK]) / 추정([INFER]) / 미복원([TODO]).
 *
 * SMcode_Hanja_Table 구조(실측): 114 unsigned short/행, 약 484행. 행[0]=한글 KS
 * 코드(키), 행[1..113]=그 독음의 한자 KS 코드 후보(0 종료). 내용(사전 데이터)은
 * 소스에 내장하지 않고 정본에서 추출(extract_tables.py, data/, gitignore).
 */
#import "HanjaConverter.h"
@class Preference;   /* [Preference alloc] 수신자용 전방 선언 */

#define HANJA_ROW   114     /* ushort/행 */
#define HANJA_ROWS  484     /* 최대 행 수 */
extern const unsigned short SMcode_Hanja_Table[]; /* [HANJA_ROW*row + col] */

@implementation HanjaConverter

/* [INFER] 트리비얼 세터(크기 0x10 = 단순 대입). */
- (void)setDispatcher:d { dispatcher = d; }
- (void)setResp:r       { resp = r; }

/*
 * [OK] 단일 한글자 → 한자 후보(index%후보수). 한글자를 KS 코드로 바꿔
 * SMcode_Hanja_Table 에서 키가 일치하는 행을 찾고, 그 행의 후보들(0 종료)
 * 중 idx 번째(순환)를 표시 코드로 변환해 1글자 NSString 반환.
 */
- hanjaWithString:s index:(unsigned)idx
{
    unsigned short ks, disp;
    unsigned uni, count = 0;
    int row, i;

    uni = [s characterAtIndex:0];
    ks  = [dispatcher ksFromUnicode:uni];

    row = 0;
    while (SMcode_Hanja_Table[HANJA_ROW * row] != ks) {
        if (++row > HANJA_ROWS - 1)
            return nil;
    }
    for (i = 0; i <= 119; i++) {              /* 후보 수 세기(0 종료) */
        if (!SMcode_Hanja_Table[HANJA_ROW * row + 1 + i])
            break;
        ++count;
    }
    if (!count)
        return nil;
    cell_pos = idx % count;
    disp = [dispatcher unicodeFromKS:SMcode_Hanja_Table[HANJA_ROW * row + 1 + idx % count]];
    return [NSString stringWithCharacters:&disp length:1];
}

/* 외부 사전 트라이의 종료 키(원본 off_5E36C). NOTE: 실제 키 문자열 확인. */
#define HANJA_WORD_ENDKEY @"\\0"

/*
 * [OK] 단어 → 한자 후보(외부 사전). preference 의 사전 경로가 바뀌면
 * systemDictionary 를 재로드하고, findWord:index: 로 후보(wordArray)를 구성해
 * idx 번째(순환) 반환.
 * NOTE: 5575D(preference 사전경로 게터)·55765(경로로 재로드) 셀렉터 확인.
 */
- hanjaWithStrings:s index:(unsigned)idx
{
    unsigned count;
    if (!preference)
        preference = [[Preference alloc] init];
    pathString = [preference dictionaryName];           /* NOTE: 5575D */
    if (!pathString)
        return nil;
    if (![oldPathString isEqual:pathString]) {
        oldPathString = [pathString copy];
        [systemDictionary setDictionaryPath:pathString];/* NOTE: 55765 (경로로 재로드) */
    }
    if (!wordArray) {
        [self findWord:s index:idx];
        if (!wordArray)
            return nil;
    }
    count = [wordArray count];
    return [wordArray objectAtIndex:idx % count];
}

/*
 * [OK] 외부 사전(중첩 딕셔너리 = 트라이) 순회로 단어의 한자 후보 배열을 찾는다.
 * 작업 노드 d 를 루트(systemDictionary)로 시작해 입력 단어의 각 글자로 하위
 * 노드를 따라 내려가고(setDictionary:), 끝에서 종료키의 후보 배열을 wordArray 에.
 * 도중 매칭 실패 시 wordArray = nil.
 * NOTE: 5563E(setDictionary:)·55642(substringWithRange:)·55476(objectForKey:) 확인.
 */
- (void)findWord:s index:(unsigned)idx
{
    NSMutableDictionary *d = [[NSMutableDictionary alloc] init];
    int len = [s length];
    int i;

    [d setDictionary:systemDictionary];                 /* 루트에서 시작 */
    if (len <= 0) {
        wordArray = [d objectForKey:HANJA_WORD_ENDKEY];
        return;
    }
    for (i = 0; i < len; i++) {
        id ch  = [s substringWithRange:NSMakeRange(i, 1)]; /* NOTE: 55642 */
        id sub = [d objectForKey:ch];
        if (!sub) {
            wordArray = nil;
            return;
        }
        [d setDictionary:sub];                          /* 하위 노드로 좁힘 */
    }
    wordArray = [d objectForKey:HANJA_WORD_ENDKEY];
}

/*
 * [OK] 후보 패널 표시/갱신. idx>0: wordpanel 앞으로, 브라우저 매트릭스에 24pt
 * 폰트 설정 후 리로드하고 현재 후보(idx%count)를 선택. idx==0: 첫 글자를 KS
 * 코드로 바꿔 단일자 경로 진입.
 * NOTE: 브라우저/매트릭스 AppKit 셀렉터(55776/559AA/557B2/557B6/559AE/559B2/
 * 559B6/5589A/559A6), 폰트명 off_5E354 는 확인 대상.
 */
- (void)hanjapanel:s index:(unsigned)idx
{
    if (idx) {
        id matrix, font;
        unsigned count;
        [wordpanel makeKeyAndOrderFront:self];        /* NOTE: 55776 */
        matrix = [browser matrixInColumn:0];          /* NOTE: 559AA */
        font   = [NSFont fontWithName:@"..." size:24.0]; /* NOTE: off_5E354/557B2 */
        [matrix setFont:font];                        /* NOTE: 557B6 */
        [browser setMatrix:matrix inColumn:0];        /* NOTE: 559AE (브라우저 갱신) */
        [browser reloadColumn:0];                     /* NOTE: 559B2 */
        count = [wordArray count];
        [browser selectRow:idx % count inColumn:0];   /* NOTE: 559B6 */
    } else {
        unsigned short uni = [s characterAtIndex:0];
        unsigned short ks  = [dispatcher ksFromUnicode:uni];  /* NOTE: 5589A */
        [self frontHanja:ks];                         /* NOTE: 559A6 (단일자 경로) */
    }
}

/* [OK] 브라우저에서 선택한 한자를 확정 적용. */
- (void)changeHanja:sender
{
    id str = [[sender selectedCell] stringValue];
    if ([str length])
        [dispatcher applyHanja:str isComplete:1];
}

/* [INFER] 한글로 되돌리기(크기 0x7 = 거의 빈 본문). 대조 예정. */
- (void)changeHangul:sender { }

/* [INFER] 후보 배열 초기화(크기 0x11 = 단순 대입). 대조 예정. */
- (void)clearWordArray { wordArray = nil; }

/*
 * [OK] 생성자: super init → Hanja.nib 로드(owner=self) → systemDictionary/path/cell
 * 초기화. nib 실패 시 로그+nil. NOTE: nib명(off_5E33C=Hanja 추정)·에러문(off_5E348).
 */
- init
{
    [super init];
    if ([NSBundle loadNibNamed:@"Hanja" owner:self]) {   /* NOTE: off_5E33C */
        systemDictionary = [[NSMutableDictionary alloc] init];
        oldPathString    = [[NSString alloc] init];
        pathString       = [[NSString alloc] init];
        cell_old = 0;
        cell_pos = 0;
        return self;
    }
    NSLog(@"HanjaConverter: cannot load nib");            /* NOTE: off_5E348 */
    return nil;
}

/* [OK] 후보 패널·단어 패널 숨김. */
- (void)orderOutPanel:sender
{
    if (panel)     [panel orderOut:self];
    if (wordpanel) [wordpanel orderOut:self];
}

/*
 * [OK] 단일 KS 코드의 한자표 행을 찾아 후보 매트릭스를 채우고 패널을 앞으로.
 * NOTE: 55A5A(행 인덱스로 매트릭스 채우는 헬퍼) 셀렉터 확인.
 */
- frontHanja:(unsigned short)ks
{
    int i;
    for (i = 0; i <= HANJA_ROWS - 1; i++)
        if (SMcode_Hanja_Table[HANJA_ROW * i] == ks)
            [self _initMatrixWithFont:i];    /* 55A5A = _initMatrixWithFont:(행 인덱스) */
    [panel orderFront:self];
    return self;
}

/*
 * [OK/STRUCT] 단일 한글자 행(row)의 한자 후보를 10열 매트릭스에 채운다(이름은
 * "Font"지만 실인자는 행 인덱스). 각 KS 코드를 dispatcher unicodeFromKS: 로 표시
 * 문자로 변환해 셀에 설정, 나머지 셀은 비우고, 현재 후보(cell_pos+1) 하이라이트.
 * NOTE(AppKit 셀 셀렉터): 55CC6/55CCE(setStringValue:)/55CD2(setLeaf:)/55CD6/55CDA/
 * 55CDE(highlightCell:atRow:column:)/55CE2/55CE6·폰트명 off_5E354·빈칸 off_5E360.
 */
- (void)_initMatrixWithFont:(int)row
{
    id font, cell, str;
    int count = 1, j, k;
    unsigned short u;

    font = [NSFont fontWithName:@"..." size:24.0];        /* NOTE: off_5E354 */
    [matrix setFont:font];
    for (j = 0; j <= 119; j++) {                          /* 후보 수(+1) */
        if (!SMcode_Hanja_Table[HANJA_ROW * row + 1 + j])
            break;
        count++;
    }
    for (j = 0; j < count; j++) {                         /* 행0=한글키 포함 채움 */
        u    = [dispatcher unicodeFromKS:SMcode_Hanja_Table[HANJA_ROW * row + j]];
        cell = [matrix cellAtRow:j / 10 column:j % 10];
        str  = [NSString stringWithCharacters:&u length:1];
        [cell setStringValue:str];
        [cell setLeaf:YES];                              /* NOTE: 55CD2 */
        [cell setEnabled:YES];                           /* NOTE: 55CDA */
    }
    for (k = count; k <= 119; k++) {                     /* 나머지 셀 비움 */
        cell = [matrix cellAtRow:k / 10 column:k % 10];
        [cell setStringValue:@""];                       /* NOTE: off_5E360 */
        [cell setLeaf:NO];
    }
    [matrix highlightCell:YES atRow:(cell_pos + 1) / 10 column:(cell_pos + 1) % 10]; /* 55CDE */
    [matrix highlightCell:NO  atRow:cell_old / 10 column:cell_old % 10];
    cell_old = cell_pos + 1;
    /* [panel display]; */                               /* NOTE: 55CE2/55CE6 */
}

/*
 * [STRUCT] NSBrowser 델리게이트: wordArray(단어 한자 후보)를 matrix 에 한 셀씩 채운다.
 * NOTE(AppKit): 554AA(가드)/554AE(addRow)/55452(cellAtRow:column:)/셀 setStringValue:·
 * setLeaf:·setLoaded: 확인.
 */
- (int)browser:sender createRowsForColumn:(int)col inMatrix:(id)aMatrix
{
    int i, n, r = 0;
    id cell;
    n = [wordArray count];
    for (i = 0; i < n; i++) {
        [aMatrix addRow];                                /* NOTE: 554AE */
        cell = [aMatrix cellAtRow:r column:0];           /* NOTE: 55452 */
        [cell setStringValue:[wordArray objectAtIndex:i]];
        [cell setLeaf:YES];
        r++;
    }
    return n;
}

@end
