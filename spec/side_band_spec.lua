-- BYTECODE -- side_band.lua:14-23
0001    GGET     2   0      ; "setmetatable"
0002    TDUP     4   3
0003    GGET     5   1      ; "assert"
0004    TGETS    7   1   2  ; "settings"
0005    CALL     5   2   2
0006    TSETS    5   4   2  ; "settings"
0007    GGET     5   1      ; "assert"
0008    TGETS    7   1   4  ; "screen"
0009    CALL     5   2   2
0010    TSETS    5   4   4  ; "screen"
0011    GGET     5   1      ; "assert"
0012    TGETS    7   1   5  ; "horizontal_span"
0013    CALL     5   2   2
0014    TSETS    5   4   5  ; "horizontal_span"
0015    GGET     5   1      ; "assert"
0016    TGETS    7   1   6  ; "widget"
0017    CALL     5   2   2
0018    TSETS    5   4   6  ; "widget"
0019    GGET     5   1      ; "assert"
0020    TGETS    7   1   7  ; "geometry"
0021    CALL     5   2   2
0022    TSETS    5   4   7  ; "geometry"
0023    GGET     5   1      ; "assert"
0024    TGETS    7   1   8  ; "blitbuffer"
0025    CALL     5   2   2
0026    TSETS    5   4   8  ; "blitbuffer"
0027    MOV      5   0
0028    CALLT    2   3

-- BYTECODE -- side_band.lua:25-27
0001    TGETS    1   0   0  ; "settings"
0002    MOV      3   1
0003    TGETS    1   1   1  ; "nilOrTrue"
0004    TGETS    4   0   2  ; "SETTING"
0005    CALLT    1   3

-- BYTECODE -- side_band.lua:38-43
0001    TGETS    4   0   0  ; "dimen"
0002    MOV      7   1
0003    TGETS    5   1   1  ; "hatchRect"
0004    MOV      8   2
0005    MOV      9   3
0006    TGETS   10   4   2  ; "w"
0007    TGETS   11   4   3  ; "h"
0008    GGET    12   4      ; "math"
0009    TGETS   12  12   5  ; "max"
0010    KSHORT  14   1
0011    UGET    15   0      ; band
0012    TGETS   15  15   6  ; "screen"
0013    MOV     17  15
0014    TGETS   15  15   7  ; "scaleBySize"
0015    UGET    18   0      ; band
0016    TGETS   18  18   8  ; "STRIPE"
0017    CALL    15   0   3
0018    CALLM   12   2   1
0019    UGET    13   0      ; band
0020    TGETS   13  13   9  ; "blitbuffer"
0021    TGETS   13  13  10  ; "COLOR_BLACK"
0022    UGET    14   0      ; band
0023    TGETS   14  14  11  ; "ALPHA"
0024    CALL     5   1   9
0025    RET0     0   1

-- BYTECODE -- side_band.lua:31-45
0001    KSHORT   3   0
0002    ISLE     1   3
0003    JMP      3 => 0009
0004    MOV      5   0
0005    TGETS    3   0   0  ; "hatched"
0006    CALL     3   2   2
0007    IST          3
0008    JMP      3 => 0020
0009 => TGETS    3   0   1  ; "horizontal_span"
0010    MOV      5   3
0011    TGETS    3   3   2  ; "new"
0012    TDUP     6   5
0013    GGET     7   3      ; "math"
0014    TGETS    7   7   4  ; "max"
0015    KSHORT   9   0
0016    MOV     10   1
0017    CALL     7   2   3
0018    TSETS    7   6   6  ; "width"
0019    UCLO     0 => 0037
0020 => MOV      3   0
0021    TGETS    4   0   7  ; "widget"
0022    MOV      6   4
0023    TGETS    4   4   2  ; "new"
0024    TDUP     7  12
0025    TGETS    8   0   8  ; "geometry"
0026    MOV     10   8
0027    TGETS    8   8   2  ; "new"
0028    TDUP    11   9
0029    TSETS    1  11  10  ; "w"
0030    TSETS    2  11  11  ; "h"
0031    CALL     8   2   3
0032    TSETS    8   7  13  ; "dimen"
0033    FNEW     8  14      ; side_band.lua:38
0034    TSETS    8   7  15  ; "paintTo"
0035    UCLO     0 => 0036
0036 => CALLT    4   3
0037 => CALLT    3   3

-- BYTECODE -- side_band.lua:0-48
0001    TDUP     0   0
0002    TSETS    0   0   1  ; "__index"
0003    FNEW     1   3      ; side_band.lua:14
0004    TSETS    1   0   2  ; "new"
0005    FNEW     1   5      ; side_band.lua:25
0006    TSETS    1   0   4  ; "hatched"
0007    FNEW     1   7      ; side_band.lua:31
0008    TSETS    1   0   6  ; "create"
0009    UCLO     0 => 0010
0010 => RET1     0   2

