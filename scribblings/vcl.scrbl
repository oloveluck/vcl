#lang scribble/manual
@(require (for-label racket/base racket/contract vcl/parser/parse vcl/compile vcl/decompile vcl/workspace))

@title{vcl: the ValueSet Compose Language}

@hyperlink["https://build.fhir.org/ig/FHIR/ig-guidance/vcl.html"]{VCL} is the compact,
URL-embeddable syntax for a ValueSet's @tt{compose}: one expression names the codes. This package
parses it with a port of the official grammar, compiles an expression to a ValueSet, decompiles a
compose back to VCL, and makes a @tt{.vcl} file a module. All 60 examples on the spec page parse and
survive printing and reparsing. Part of the @hyperlink["https://github.com/oloveluck/fhir"]{fhir}
family.

@table-of-contents[]

@section{Quick start}

@bold{1. Install.} The packages are not on the Racket package server yet; clone the repositories
side by side and install from source:

@verbatim{
raco pkg install --link --auto fhir/fhir vcl
}

@bold{2. Write an expression}, on the command line or in a file:

@verbatim{
$ raco vcl '(http://loinc.org)(85354-9;55284-4)'
{"compose":{"include":[{"concept":[{"code":"85354-9"},{"code":"55284-4"}],"system":"http://loinc.org"}]},
 "name":"VCLExpression","resourceType":"ValueSet","status":"active",
 "url":"http://fhir.org/VCL?v1=(http://loinc.org)(85354-9;55284-4)"}
}
(one line of JSON, folded here).

@bold{3. Expand it.} The terminology service (fhir-tx) recognises the implicit url anywhere a
ValueSet url is expected (a binding, @tt{$expand}, FHIRPath's @tt{%terminologies.expand()}) and
compiles it on the fly:

@verbatim{
raco fhir-tx expand 'http://fhir.org/VCL?v1=(http://loinc.org)(85354-9;55284-4)' --package hl7.fhir.r4.core.tgz
}

@section{Writing VCL}

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

@subsection{Command line}

@tabular[#:style 'boxed #:sep @hspace[2]
(list (list @tt{raco vcl '<expression>'} "the ValueSet JSON (implicit url)")
      (list @tt{raco vcl expression.vcl} "the same, from a file (a #lang vcl line before the expression is allowed; an error is placed on the file's line)")
      (list @tt{raco vcl --decompile valueset.json} "the VCL of a ValueSet's compose"))]

@litchar{--format text|json|outcome} chooses how an error is reported. Exit codes: 0, 1 on a VCL
error, 2 on usage.

@subsection{As a module}

A @tt{.vcl} file holds one expression. @racket[(require "bp-panels.vcl")] gives @racket[source]
(the text), @racket[expression] (the AST), @racket[compose] (the @tt{ValueSet.compose} jsexpr) and
@racket[valueset] (a whole ValueSet under the implicit url). A parse error is a compile error of the
requiring program, at the line and column in the @tt{.vcl} file where the expression stops; requiring
the module registers the value set, so bindings and @tt{$expand} find it by url.
@tt{racket bp-panels.vcl} prints the ValueSet.

@racketblock[
(require (only-in "bp-panels.vcl" [valueset bp-panels])
         (only-in fhir/terminology/operations $expand))          (code:comment "fhir-tx")
(hash-ref ($expand #:valueSet bp-panels) 'expansion)            (code:comment "the codes")
]

@subsection{From Racket}

@racketblock[
(require vcl/compile vcl/decompile fhir/result/result)
(ok-value (vcl->valueset "(http://loinc.org)(85354-9;55284-4)"))   (code:comment "a ValueSet jsexpr")
(ok-value (vcl->compose "(http://loinc.org)(85354-9;55284-4)"))    (code:comment "just the compose")
(compose->vcl (hash-ref vs 'compose))                              (code:comment "back to text")
]

@section{In an editor, for an agent}

@tt{vcl/support} is what the family's language server (fhir-lsp) loads for VCL: a document's
diagnostics (the one expression compiled to a compose). @tt{vcl/workspace} is what fhir-mcp runs for
an agent: a file's ValueSet, expanded, and which part of the expression holds a code. It also
provides the repository's @tt{guide.md} (a cheat sheet, the operator table, what a compose cannot
say, the common problems, each checked by its tests) as @racket[guide], which fhir-mcp serves as
@tt{learn://vcl}. Without MCP, the repository's Claude skill (@tt{.claude/skills/vcl}) gives an agent
the same workflow with the command line and the Racket API.

@section{Limits}

@itemlist[
@item{What a compose cannot say is an error: an exclusion below the top level, a conjunction with a
plain code, value set or @tt{*} in it, conflicting systems in one conjunction, a bare @tt{*}.}
@item{A nested filter list or an @tt{of} source goes into @tt{filter.value} as VCL text.}
@item{When the terminology service expands a VCL value set, @tt{of} matches nothing (every other
operator expands, @tt{>>} and @tt{!!<} included).}
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

@subsection[#:style 'unnumbered]{@tt{vcl/workspace}}
@defmodule[vcl/workspace]

@defthing[workspace-support any/c]{The @tt{fhir/lang/workspace} support fhir-mcp loads for VCL.}
@defthing[guide string?]{The repository's @tt{guide.md}: the language for agents (fhir-mcp's
@tt{learn://vcl}).}
