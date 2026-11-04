#lang scribble/manual
@(require (for-label racket/base racket/contract vcl/parser/parse vcl/compile vcl/decompile))

@title{vcl: the ValueSet Compose Language for Racket}

@hyperlink["https://build.fhir.org/ig/FHIR/ig-guidance/vcl.html"]{VCL} is the compact,
URL-embeddable syntax for a ValueSet's @tt{compose}. This package parses it with a port of the official
grammar, compiles an expression to @tt{ValueSet.compose} (or a whole ValueSet), decompiles a compose
back to VCL, and makes a @tt{.vcl} file a module with @hash-lang[]. All 60 examples on the spec page
parse and survive printing and reparsing.

Part of the @hyperlink["https://github.com/oloveluck/fhir"]{fhir} family; it depends on the
@tt{fhir} package for its @racket[result] type.

@table-of-contents[]

@section{Install}

@verbatim{
raco pkg install --link --auto fhir/fhir vcl      # from source, with the fhir repo alongside
}

@section{@hash-lang[] @tt{vcl}}
@defmodulelang[vcl]

A file holds one expression. The module provides @racket[source] (the text), @racket[expression]
(the AST), @racket[compose] (the @tt{ValueSet.compose} jsexpr) and @racket[valueset] (a ValueSet
whose url is the implicit VCL url, @tt{http://fhir.org/VCL?v1=…}). A parse error is a compile
error. Running the file prints the ValueSet.

@verbatim|{#lang vcl
(http://loinc.org)(85354-9;55284-4)}|

@section{Parsing}
@defmodule[vcl/parser/parse]

@defproc[(parse-vcl [src string?]) result?]{
@racket[(ok ast)] or @racket[(err invalid-encoding)] with a @tt{fhir/diagnostic} attached
(@tt{attached-diagnostic}), positioned in the expression. Memoized.}

The AST is prefab: @racket[vcl-sub] (a @tt{(system)} applied to an expression), @racket[vcl-conj]
(@tt{,}), @racket[vcl-disj] (@tt{;}), @racket[vcl-excl] (@tt{-}), @racket[vcl-code],
@racket[vcl-star], @racket[vcl-include] (@tt{^uri}), @racket[vcl-filter] (a property, one of the 11
operators, a value), @racket[vcl-of] (R6 @tt{of}), @racket[vcl-code-list] and
@racket[vcl-filter-list] (@tt{vcl/parser/ast}).

@section{Compiling}
@defmodule[vcl/compile]

@defproc[(vcl->compose [x (or/c string? any/c)]) result?]{
Text or an AST to @racket[(ok compose)]. A disjunction becomes include entries, a conjunction one
include's filters, a top-level @tt{-} the exclude, @tt{(system)} distributes over its members,
@tt{^uri} is a @tt{valueSet} reference. What a compose cannot say is an @racket[err], never an
exception: an exclusion below the top level, a conjunction of plain codes, a bare @tt{*}.}

@defproc[(vcl->valueset [src string?] [#:url url (or/c string? #f) #f] [#:name name (or/c string? #f) #f]) result?]{
A whole active ValueSet. @racket[url] defaults to the implicit VCL url of @racket[src];
@racket[name] to @racket["VCLExpression"].}

@defproc[(vcl-print [ast any/c]) string?]{
Canonical text. Compound members are bracketed, since the spec gives @tt{,} and @tt{;} no precedence.}

@section{Decompiling}
@defmodule[vcl/decompile]

@defproc[(compose->vcl [compose jsexpr?]) string?]{
A @tt{ValueSet.compose} as VCL. For compose-expressible expressions, compiling the result gives the
compose back.}

@section{Command line}

@verbatim{
raco vcl '<expression>' | <file.vcl>      the ValueSet JSON (implicit url)
raco vcl --decompile <valueset.json>      the VCL of a ValueSet's compose
}

@tt{--format text|json|outcome} chooses how an error is reported. Exit codes: 0, 1 on a VCL error,
2 on usage.
