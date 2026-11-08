340
((3) 0 () 1 ((q lib "vcl/compile.rkt")) () (h ! (equal) ((q def ((lib "vcl/decompile.rkt") compose->vcl)) q (1754 . 3)) ((c def c (c (? . 0) q vcl-print)) q (1696 . 3)) ((c def c (c (? . 0) q vcl->compose)) q (1451 . 3)) ((c def c (c (? . 0) q vcl->valueset)) q (1525 . 5)) ((q def ((lib "vcl/parser/parse.rkt") parse-vcl)) q (1391 . 3))))

form                                     meaning
B, "B.123"                               a code (quoted when it has characters a simple code cannot)
a;b                                      either: the union
p=a,q=b                                  both: the intersection (of filters)
x-y                                      x without y (at the top level only)
(http://loinc.org)(a;b)                  the codes of a system; a version as (http://loinc.org|2.74)
(http://loinc.org)*                      every code of a system
^http://hl7.org/fhir/ValueSet/payeetype  the members of a value set
prop=B                                   a property filter; also prop<<B (is-a), prop<B (descendent-of), prop~<<B
                                         (is-not-a), prop>>B (generalizes), prop<!B (child-of), prop!!<B
                                         (descendent-leaf)
prop/"A[0-9]*"                           regex
prop^{a,b}, prop~^{a,b}                  in, not in (a code list, a value set url, or a filter list)
prop?true                                exists
{concept<B}.prop                         of: the property's values over the members (R6)

raco vcl ’<expression>’            the ValueSet JSON (implicit url)
raco vcl expression.vcl            the same, from a file
raco vcl –decompile valueset.json  the VCL of a ValueSet's compose
procedure
(parse-vcl src) -> result?
  src : string?
procedure
(vcl->compose x) -> result?
  x : (or/c string? any/c)
procedure
(vcl->valueset src [#:url url #:name name]) -> result?
  src : string?
  url : (or/c string? #f) = #f
  name : (or/c string? #f) = #f
procedure
(vcl-print ast) -> string?
  ast : any/c
procedure
(compose->vcl compose) -> string?
  compose : jsexpr?
