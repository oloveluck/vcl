#lang scribble/manual
@(require (for-label racket/base racket/contract vcl/parser/parse vcl/compile vcl/decompile))

@title{vcl: the ValueSet Compose Language for Racket}

@hyperlink["https://build.fhir.org/ig/FHIR/ig-guidance/vcl.html"]{VCL} is the compact,
URL-embeddable syntax for a ValueSet's @tt{compose}. This package parses it with a port of the official
grammar, compiles an expression to @tt{ValueSet.compose} or a whole ValueSet, decompiles a compose
back to VCL, and makes a @tt{.vcl} file a module. All 60 examples on the spec page parse and survive
printing and reparsing.

Part of the @hyperlink["https://github.com/oloveluck/fhir"]{fhir} family; depends on the
@tt{fhir} package for its @racket[result] type.

@table-of-contents[]

@section{Install}

@verbatim{
raco pkg install --link --auto fhir/fhir vcl      # from source, with the fhir repo alongside
}

@section{Writing VCL}

An expression names codes and combines them:

@tabular[#:style 'boxed #:sep @hspace[2]
(list (list @bold{form} @bold{meaning})
      (list @elem{@tt{B}, @tt{"B.123"}} "a code (quoted when it has characters a simple code cannot)")
      (list @tt{a;b} "either: the union")
      (list @tt{p=a,q=b} "both: the intersection (of filters)")
      (list @tt{x-y} "x without y (at the top level only)")
      (list @tt{(http://loinc.org)(a;b)} "the codes of a system; a version as (http://loinc.org|2.74)")
      (list @tt{(http://loinc.org)*} "every code of a system")
      (list @tt{^http://hl7.org/fhir/ValueSet/payeetype} "the members of a value set")
      (list @tt{prop=B} "a property filter; also prop<<B (is-a), prop<B (descendent-of), prop~<<B (is-not-a), prop>>B (generalizes), prop<!B (child-of), prop!!<B (descendent-leaf)")
      (list @tt{prop/"A[0-9]*"} "regex")
      (list @elem{@tt{prop^{a,b}}, @tt{prop~^{a,b}}} "in, not in (a code list, a value set url, or a filter list)")
      (list @tt{prop?true} "exists")
      (list @tt{{concept<B}.prop} "of: the property's values over the members (R6)"))]

The spec gives @tt{,} and @tt{;} no precedence: bracket compound members. Spaces are allowed,
newlines are not.

@verbatim|{#lang vcl
((http://loinc.org)(41995-2;4548-4);(http://snomed.info/sct)concept<<365845005)-((http://loinc.org)76573-5)}|

@section{Using it}

@bold{As a module.} A @tt{.vcl} file holds one expression. @racket[(require "bp-panels.vcl")] gives
@racket[source] (the text), @racket[expression] (the AST), @racket[compose] (the
@tt{ValueSet.compose} jsexpr) and @racket[valueset] (a whole ValueSet whose url is the implicit VCL
url, @tt{http://fhir.org/VCL?v1=…}). A parse error is a compile error of the requiring program.
@tt{racket bp-panels.vcl} prints the ValueSet.

@racketblock[
(require (only-in "bp-panels.vcl" [valueset bp-panels])
         (only-in fhir/terminology/operations $expand))       (code:comment "fhir-validation")
(code:comment "the codes, via the terminology service")
(hash-ref ($expand #:valueSet bp-panels) 'expansion)
]

The terminology service also expands an implicit VCL url given anywhere a ValueSet url is expected
(a binding, @tt{%terminologies.expand()} in FHIRPath), compiling it on the fly.

@bold{From Racket.}

@racketblock[
(require vcl/compile vcl/decompile fhir/result/result)
(code:comment "a ValueSet jsexpr")
(ok-value (vcl->valueset "(http://loinc.org)(85354-9;55284-4)"))
(code:comment "just the compose")
(ok-value (vcl->compose "(http://loinc.org)(85354-9;55284-4)"))
(code:comment "back to text")
(compose->vcl (hash-ref vs 'compose))
]

@bold{Command line.}

@verbatim{
raco vcl '(http://loinc.org)(85354-9;55284-4)'   the ValueSet JSON (implicit url)
raco vcl expression.vcl                           the same, from a file
raco vcl --decompile valueset.json                the VCL of a ValueSet's compose
}

@litchar{--format text|json|outcome} chooses how an error is reported. Exit codes: 0, 1 on a VCL error,
2 on usage.

@section{Limits}

@itemlist[
@item{What a compose cannot say is an error: an exclusion below the top level, a conjunction with a
plain code, value set or @tt{*} in it, conflicting systems in one conjunction, a bare @tt{*}.}
@item{A nested filter list or an @tt{of} source goes into @tt{filter.value} as VCL text.}
@item{When the terminology service expands a VCL value set, the operators @tt{>>} (generalizes),
@tt{!!<} (descendent-leaf) and @tt{of} match nothing.}
@item{Decompiling is lossy: an include with both concepts and filters keeps the concepts; displays,
designations and the compose's @tt{inactive} and @tt{lockedDate} are dropped. The implicit url
escapes spaces only.}
@item{The grammar admits a one-code list, @tt{{a}}, which the official grammar does not.}]

@section{Reference}

@subsection[#:style 'unnumbered]{@hash-lang[] @tt{vcl}}
@defmodulelang[vcl]

Provides @racket[source], @racket[expression], @racket[compose] and @racket[valueset], as above.

@subsection[#:style 'unnumbered]{@tt{vcl/parser/parse}}
@defmodule[vcl/parser/parse]

@defproc[(parse-vcl [src string?]) result?]{
@racket[(ok ast)] or @racket[(err invalid-encoding)] with a @tt{fhir/diagnostic} attached
(@tt{attached-diagnostic}), positioned in the expression. Memoized.}

The AST is prefab (@tt{vcl/parser/ast}): @racket[vcl-sub] (a system applied to an expression),
@racket[vcl-conj] (@tt{,}), @racket[vcl-disj] (@tt{;}), @racket[vcl-excl] (@tt{-}),
@racket[vcl-code], @racket[vcl-star], @racket[vcl-include] (@tt{^uri}), @racket[vcl-filter]
(property, operator, value), @racket[vcl-of], @racket[vcl-code-list], @racket[vcl-filter-list].

@subsection[#:style 'unnumbered]{@tt{vcl/compile}}
@defmodule[vcl/compile]

@defproc[(vcl->compose [x (or/c string? any/c)]) result?]{
Text or an AST to @racket[(ok compose)]. A disjunction becomes include entries, a conjunction one
include's filters, a top-level @tt{-} the exclude, a system distributes over its members, @tt{^uri}
is a @tt{valueSet} reference. What a compose cannot say is an @racket[err], never an exception: an
exclusion below the top level, a conjunction of plain codes, a bare @tt{*}.}
@defproc[(vcl->valueset [src string?] [#:url url (or/c string? #f) #f] [#:name name (or/c string? #f) #f]) result?]{
An active ValueSet. @racket[url] defaults to the implicit VCL url of @racket[src]; @racket[name] to
@racket["VCLExpression"].}
@defproc[(vcl-print [ast any/c]) string?]{Canonical text, compound members bracketed.}

@subsection[#:style 'unnumbered]{@tt{vcl/decompile}}
@defmodule[vcl/decompile]

@defproc[(compose->vcl [compose jsexpr?]) string?]{
A @tt{ValueSet.compose} as VCL. For compose-expressible expressions, compiling the result gives the
compose back.}
