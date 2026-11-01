#lang brag

; grammar.rkt — the official VCL ANTLR grammar (vcl.g4, vendored alongside) ported rule-for-rule
; to brag. Deviations from the g4, each deliberate and documented:
;   * `tail` is introduced because brag wants a named rule for the optional
;     (conjunction | disjunction | exclusion) group — same language.
;   * codeList accepts a SINGLE code (`{a}`): the g4 requires two+, but a decompiled compose
;     filter with op=in and a one-code value has no other faithful surface form; accepting the
;     singleton keeps compose->vcl->compose a fixpoint. Printing always uses the list form.

vcl         : expr
expr        : subExpr [tail]
tail        : conjunction | disjunction | exclusion
subExpr     : [systemUri] (simpleExpr | OPEN expr CLOSE)
conjunction : (COMMA subExpr)+
disjunction : (SEMI subExpr)+
exclusion   : DASH subExpr
simpleExpr  : STAR | code | filter | includeVs

includeVs   : CARET (URI | systemUri)
systemUri   : OPEN URI CLOSE
filter      : property EQ code
            | property IS-A code
            | property IS-NOT-A code
            | property DESC-OF code
            | property REGEX str
            | property CARET (codeList | URI | filterList)
            | property NOT-IN (codeList | URI | filterList)
            | property GENERALIZES code
            | property CHILD-OF code
            | property DESC-LEAF code
            | property EXISTS code
            | (code | codeList | STAR | URI | filterList) DOT property
filterList  : LCRLY filter (COMMA filter)* RCRLY
property    : code

codeList    : LCRLY code (COMMA code)* RCRLY
code        : SCODE | QUOTED
str         : QUOTED
