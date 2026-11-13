#lang scribble/manual
@; Text in @tt is shown exactly as written: no curly quotes, and "--" stays two hyphens.
@(require (only-in scribble/core [element literal-element]))
@(define (tt . text) (literal-element (quote tt) text))
@(require (only-in scribble/core element)
          (for-label racket/base racket/contract vcl/parser/parse vcl/compile vcl/decompile vcl/workspace))
@; vcl, sh : an expression or a command in a sentence, exactly as typed (tt would turn -- into a dash
@; and "x" into curly quotes)
@(define (vcl . text) (element 'tt text))
@(define (sh . text) (element 'tt text))

@title{vcl: the ValueSet Compose Language}

Health data is full of codes. A lab result says which test it was with a code; a diagnosis, a
medication, a marital status are codes too. Rules about that data keep needing to say "one of these
codes": the tests used to follow diabetes, the codes that mean a parent. Such a named set of codes
is a @italic{value set}. You name the set once, and a profile, a search or a piece of clinical
logic can then refer to it instead of repeating the codes.

The codes themselves come from @italic{code systems}: published catalogues of codes with their
meanings, such as LOINC for laboratory tests or SNOMED CT for clinical terms. Each code system is
named by a web address (@tt{http://loinc.org}).

FHIR writes a value set as a ValueSet resource, which is a page of JSON.
@hyperlink["https://build.fhir.org/ig/FHIR/ig-guidance/vcl.html"]{VCL}, the ValueSet Compose
Language, writes the same thing on one line:

@verbatim|{(http://loinc.org)(4548-4;2345-7)}|

That reads "from LOINC, the codes 4548-4 and 2345-7": the HbA1c test and the glucose test. A value
set can also describe its codes by a rule instead of listing them, "every code under
@italic{parent}", and VCL writes that as shortly.

This package turns a VCL expression into the ValueSet resource, turns a ValueSet back into VCL, and
lets the rest of the family use an expression wherever a value set is expected. A mistake in an
expression is reported where the expression stops.

Part of the @hyperlink["https://oloveluck.github.io/fhir/"]{fhir} family of FHIR languages and tools.

@table-of-contents[]

@section{What you can do with it}

@itemlist[
@item{@bold{Write a value set in one line} and get the FHIR resource: @secref["first"].}
@item{@bold{Describe codes by a rule} instead of listing them, so the set stays right when the code
system grows (@secref["rules"]).}
@item{@bold{List the codes a value set holds}, with their names: this is called expanding it
(@secref["expanding"]).}
@item{@bold{Read a ValueSet someone published} as one line of VCL (@secref["decompile"]).}
@item{@bold{Keep a value set in a file} that a program can use (@secref["module"]).}]

@section[#:tag "first"]{A first example}

@bold{1. Install} the tools as the @hyperlink["https://oloveluck.github.io/fhir/"]{family's front
page} describes. The command is then @sh{raco vcl} (or @sh{vcl}, if you built the standalone
tools).

@bold{2. Write an expression.} FHIR has a small code system for a person's administrative gender,
with four codes. This expression names two of them:

@verbatim|{
$ raco vcl '(http://hl7.org/fhir/administrative-gender)(male;female)'
{"compose":{"include":[{"concept":[{"code":"male"},{"code":"female"}],"system":"http://hl7.org/fhir/administrative-gender"}]},"name":"VCLExpression","resourceType":"ValueSet","status":"active","url":"http://fhir.org/VCL?v1=(http://hl7.org/fhir/administrative-gender)(male;female)"}
}|

The first pair of round brackets holds the code system, the second the codes, separated by
semicolons. Put the expression in single quotes so the shell leaves the brackets alone.

The answer is a ValueSet resource, one line of JSON. Reading it:

@itemlist[
@item{@tt{compose} is the part of a ValueSet that says which codes are in it. It @tt{include}s one
group: from this @tt{system}, these two @tt{concept}s. FHIR calls a code together with its meaning
a concept.}
@item{@tt{url} is the address the value set goes by. A VCL value set needs no address of its own:
its address is @tt{http://fhir.org/VCL?v1=} followed by the expression. Anything that takes a value
set's address can be given this one.}
@item{@tt{name} and @tt{status} are filled in so the resource is complete.}]

@bold{3. List the codes it holds.} The family's terminology tool, @tt{fhir-tx}, takes that address:

@verbatim|{
$ raco fhir-tx expand 'http://fhir.org/VCL?v1=(http://hl7.org/fhir/administrative-gender)(male;female)'
{"expansion":{"contains":[{"code":"male","display":"Male","system":"http://hl7.org/fhir/administrative-gender","version":"5.0.0"},{"code":"female","display":"Female","system":"http://hl7.org/fhir/administrative-gender","version":"5.0.0"}],"total":2},"resourceType":"ValueSet","url":"http://fhir.org/VCL?v1=(http://hl7.org/fhir/administrative-gender)(male;female)"}
}|

This is the value set @italic{expanded}: the list of the codes it holds, each with its name
(@tt{display}), looked up in the code system. Here that is no surprise, since you listed them.

@bold{4. Describe instead of listing.} A star means "every code of the system":

@verbatim|{(http://hl7.org/fhir/administrative-gender)*}|

Expanded the same way, this holds four codes: male, female, other and unknown. You did not have to
know them. Put @vcl{ - (http://hl7.org/fhir/administrative-gender)unknown} after it, "without
unknown", and it holds three.

@bold{5. Make a mistake.} Leave out the last bracket:

@verbatim|{
$ raco vcl '(http://hl7.org/fhir/administrative-gender)(male;female'
<expression>:1:50: vcl parse error: the expression ends after `female`
 1 | (http://hl7.org/fhir/administrative-gender)(male;female
   |                                                  ^^^^^^
}|

The message gives the line and column, and the marker shows the last thing that was understood.

@bold{6. Go the other way.} Given a ValueSet as a JSON file, here the value set of marital statuses
that FHIR itself publishes, @litchar{--decompile} prints it as VCL:

@verbatim|{
$ raco vcl --decompile ValueSet-marital-status.json
(http://terminology.hl7.org/CodeSystem/v3-MaritalStatus)*;(http://terminology.hl7.org/CodeSystem/v3-NullFlavor)UNK
}|

Which reads: every code of the marital-status code system, and the code @tt{UNK} (unknown) from
another one.

@section[#:tag "writing"]{Writing an expression}

An expression is one line. The specification at
@hyperlink["https://build.fhir.org/ig/FHIR/ig-guidance/vcl.html"]{build.fhir.org} is the reference
for the language; this section is what you need most of the time.

@subsection{Listing codes}

@itemlist[
@item{@vcl{(http://loinc.org)(4548-4;2345-7)}: a code system in round brackets, then its codes in
round brackets, separated by @litchar{;}. A space after the semicolon is allowed.}
@item{@vcl{(http://loinc.org)4548-4}: one code needs no second pair of brackets.}
@item{@vcl{(http://loinc.org|2.74)(4548-4;2345-7)}: a bar and a version after the address pin the
codes to one version of the code system.}
@item{@vcl{(http://loinc.org)4548-4;(http://snomed.info/sct)73211009}: codes from two code systems,
joined by @litchar{;}.}
@item{A code with characters a plain code cannot have (a space, a dot) goes in double quotes:
@vcl{"B.123"}.}]

Always give the code system. The same code can mean different things in different systems, and the
round brackets around the address are how VCL knows where the address ends: without them
@vcl{http://loinc.org|4548-4} is read as one long address.

@subsection[#:tag "rules"]{Describing codes by a rule}

Many code systems are trees: a general code with more specific ones under it. HL7's code system of
roles and personal relationships has @tt{PRN} (parent), and under it father, mother, adoptive parent, step
parent and more. To name "any kind of parent" you do not list them. You write a @italic{filter}, a
rule the codes must meet:

@verbatim|{(http://terminology.hl7.org/CodeSystem/v3-RoleCode)concept<<PRN}|

@vcl{concept<<PRN} means "PRN and every code below it". Expanded (@secref["expanding"] shows the
command), this holds 18 codes, from @tt{PRN} parent through @tt{FTH} father and @tt{MTH} mother to
@tt{STPPRN} step parent. If the code system later gains a new kind of parent, the value set holds
it without being edited. That is the reason to describe rather than list.

Other rules are written the same way, a property of the code, an operator and a value:

@itemlist[
@item{@vcl{concept<PRN}: the codes below PRN, without PRN itself (17 of them).}
@item{@vcl{concept<!PRN}: its direct children only (6: adoptive parent, father, mother, natural
parent, foster parent, step parent).}
@item{@vcl{COMPONENT="Hemoglobin A1c"}: a property of the code has this value. Which properties
exist depends on the code system; this one is LOINC's.}]

@secref["operators"] lists every operator.

@subsection{Everything, another value set, leaving out}

@itemlist[
@item{@vcl{(http://hl7.org/fhir/administrative-gender)*}: every code of a code system.}
@item{@vcl{^http://hl7.org/fhir/ValueSet/administrative-gender}: the codes of another value set,
named by its address after a @litchar{^}.}
@item{@vcl{(http://loinc.org)(4548-4;17856-6) - (http://loinc.org)17856-6}: what is on the left,
without what is on the right. Leave spaces around the @litchar{-} or bracket both sides: a hyphen
straight after a code is read as part of the code.}]

@subsection{Or, and}

@litchar{;} means "or": the codes of either side. @litchar{,} means "and": the codes that meet both
rules.

@verbatim|{(http://terminology.hl7.org/CodeSystem/v3-RoleCode)(concept<<PRN,concept~<<FTH)}|

That is "a kind of parent, and not a kind of father" (13 codes). A code system in round brackets
applies to everything in the brackets that follow it.

VCL gives @litchar{;} and @litchar{,} no order of precedence, so an expression that mixes them must
say which goes first with brackets. @vcl{p=a;(q=b,r=c)} is "p is a, or both q is b and r is c".
Written without the inner brackets, @vcl{p=a; q=b, r=c} is refused with @tt{unexpected comma}.

@subsection[#:tag "operators"]{Every form}

@tabular[#:style 'boxed #:sep @hspace[2]
(list (list @bold{form} @bold{meaning})
      (list @elem{@vcl{B}, @vcl{"B.123"}} "a code (quoted when it has characters a simple code cannot)")
      (list @vcl{a;b} "either: the union")
      (list @vcl{p=a,q=b} "both: the intersection (of filters)")
      (list @vcl{x - y} "x without y (at the top level only)")
      (list @vcl{(http://loinc.org)(a;b)} @elem{the codes of a system; a version as @vcl{(http://loinc.org|2.74)}})
      (list @vcl{(http://loinc.org)*} "every code of a system")
      (list @vcl{^http://hl7.org/fhir/ValueSet/payeetype} "the members of a value set")
      (list @vcl{prop=B} "the property has this value")
      (list @vcl{prop<<B} "B and everything below it (is-a)")
      (list @vcl{prop<B} "everything below B (descendent-of)")
      (list @vcl{prop<!B} "the direct children of B (child-of)")
      (list @vcl{prop~<<B} "not B nor anything below it (is-not-a)")
      (list @vcl{prop>>B} "B and everything above it (generalizes)")
      (list @vcl{prop!!<B} "the codes below B that have nothing below them (descendent-leaf)")
      (list @vcl{prop/"A[0-9]*"} "the property matches a regular expression (regex)")
      (list @elem{@vcl{prop^{a,b}}, @vcl{prop~^{a,b}}} "in, not in: a list of codes, a value set address, or a list of filters")
      (list @vcl{prop?true} "the property exists")
      (list @vcl{{concept<B}.prop} "of: the property's values over the members (R6)"))]

The words in brackets are the names FHIR gives these operators in a ValueSet's @tt{filter}.
Spaces are allowed; a line break is not.

@section[#:tag "expanding"]{Listing the codes: expanding}

A value set says which codes are in it; it does not have to list them. @italic{Expanding} a value
set is working out the list. The terminology tool @tt{fhir-tx} does it, and it takes a VCL value
set by its address, @tt{http://fhir.org/VCL?v1=} followed by the expression:

@verbatim|{
$ raco fhir-tx expand 'http://fhir.org/VCL?v1=(http://terminology.hl7.org/CodeSystem/v3-RoleCode)concept<!PRN' --package hl7.fhir.r4.core.tgz
{"expansion":{"contains":[{"code":"ADOPTP","display":"adoptive parent","system":"http://terminology.hl7.org/CodeSystem/v3-RoleCode","version":"2018-08-12"},{"code":"FTH","display":"father", … {"code":"STPPRN","display":"step parent","system":"http://terminology.hl7.org/CodeSystem/v3-RoleCode","version":"2018-08-12"}],"total":6},"resourceType":"ValueSet","url":"http://fhir.org/VCL?v1=(http://terminology.hl7.org/CodeSystem/v3-RoleCode)concept<!PRN"}
}|

Quote the address: it holds brackets and semicolons the shell would otherwise act on.

@bold{What expanding needs} is the content of the code system: its codes, their names, and which
code is under which. A rule such as "everything below PRN" cannot be worked out from the expression
alone. The tool reads code systems from FHIR packages. With no @litchar{--package} it reads the
FHIR R5 core package; the relationship codes above are in the R4 core package, which is why the
command names it. The same command without @litchar{--package} answers with no codes:

@verbatim|{
$ raco fhir-tx expand 'http://fhir.org/VCL?v1=(http://terminology.hl7.org/CodeSystem/v3-RoleCode)concept<!PRN'
{"expansion":{"contains":[],"total":0},"resourceType":"ValueSet","url":"http://fhir.org/VCL?v1=(http://terminology.hl7.org/CodeSystem/v3-RoleCode)concept<!PRN"}
}|

So an empty expansion of a rule usually means the code system was not at hand, not that the rule
matches nothing. The two largest code systems, LOINC and SNOMED CT, are not in the packages that
come with the tools, so a rule over them does not expand here.

@bold{Codes you listed} are treated differently. When the code system is at hand, each is looked up
in it: it gets its name, and a code the system does not have drops out. When it is not, the codes
are given back as you wrote them, without names:

@verbatim|{
$ raco fhir-tx expand 'http://fhir.org/VCL?v1=(http://loinc.org)(4548-4;2345-7)'
{"expansion":{"contains":[{"code":"4548-4","system":"http://loinc.org"},{"code":"2345-7","system":"http://loinc.org"}],"total":2},"resourceType":"ValueSet","url":"http://fhir.org/VCL?v1=(http://loinc.org)(4548-4;2345-7)"}
}|

@bold{Is this code in the set?} is the other question to ask of a value set:

@verbatim|{
$ raco fhir-tx validate-code 'http://fhir.org/VCL?v1=(http://hl7.org/fhir/administrative-gender)(male;female)' http://hl7.org/fhir/administrative-gender other
{"parameter":[{"name":"result","valueBoolean":false},{"name":"code","valueCode":"other"},{"name":"system","valueUri":"http://hl7.org/fhir/administrative-gender"},{"name":"message","valueString":"The code 'other' is not in the value set"}],"resourceType":"Parameters"}
}|

The same address works wherever the family takes a value set's address: a binding in a profile, the
@tt{$expand} and @tt{$validate-code} operations, FHIRPath's @tt{%terminologies.expand()}. The
@hyperlink["https://oloveluck.github.io/fhir/fhir-tx/index.html"]{fhir-tx} page describes the
terminology tool.

@section[#:tag "decompile"]{Reading a ValueSet as VCL}

A published ValueSet can be long, and most of it is not about which codes are in it.
@litchar{--decompile} prints the part that is, the @tt{compose}, as one line. This is the value set
of vital signs from the FHIR R4 core package:

@verbatim|{
$ raco vcl --decompile ValueSet-observation-vitalsignresult.json
(http://loinc.org)(85353-1;9279-1;8867-4;2708-6;8310-5;8302-2;9843-4;29463-7;39156-5;85354-9;8480-6;8462-4;8478-0)
}|

The file may be a whole ValueSet or just a @tt{compose}. Compiling the printed line gives the same
compose back. What VCL has no place for is left out: the names (displays) written beside the codes
and a few rarely used settings (@secref["limits"]).

@section{Running it}

@subsection{Command line}

The command turns an expression into a ValueSet, or a ValueSet into an expression.

@tabular[#:style 'boxed #:sep @hspace[2]
(list (list @sh{raco vcl '<expression>'} "the ValueSet as JSON, under the address made from the expression")
      (list @sh{raco vcl expression.vcl} "the same, the expression read from a file")
      (list @sh{raco vcl --decompile valueset.json} "the VCL of a ValueSet's compose"))]

A file holds one expression on one line. It may begin with a @tt{#lang vcl} line
(@secref["module"]) and end with a line break. An error in a file is reported at the file's own
line:

@verbatim|{
$ raco vcl broken.vcl
broken.vcl:2:50: vcl parse error: the expression ends after `female`
 2 | (http://hl7.org/fhir/administrative-gender)(male;female
   |                                                  ^^^^^^
}|

The argument is read as a file when a file of that name exists, and as an expression otherwise. So
a mistyped file name is taken for an expression: check the spelling if the answer looks strange.

An error is reported as text by default. @litchar{--format json} writes it as JSON and
@litchar{--format outcome} as a FHIR OperationOutcome, for a program to read. The command exits
with 0 when all is well, 1 on a VCL error, and 2 when it was called wrongly or cannot read the file
to decompile.

@subsection[#:tag "module"]{As a module}

A file whose first line is @tt{#lang vcl} is a Racket module, so a program can require it. The
expression is checked when the program is built: a mistake stops the build, at the line and column
in the @tt{.vcl} file where the expression stops.

@verbatim|{
#lang vcl
(http://hl7.org/fhir/administrative-gender)(male;female)
}|

Saved as @tt{sexes.vcl}, @racket[(require "sexes.vcl")] gives @racket[source] (the text),
@racket[expression] (the parsed expression), @racket[compose] (the @tt{ValueSet.compose} as JSON
data) and @racket[valueset] (the whole ValueSet, under the address made from the expression).
Requiring the module also registers the value set, so a profile's binding and @tt{$expand} find it
by that address. @sh{racket sexes.vcl} prints the ValueSet, indented.

@racketblock[
(require (only-in "sexes.vcl" [valueset sexes])
         (only-in fhir/terminology/operations $expand))          (code:comment "fhir-tx")
(hash-ref ($expand #:valueSet sexes) 'expansion)                (code:comment "the codes: male, female")
]

@subsection{From Racket}

The steps the module form does for you are functions. Each answers a Result
(@tt{fhir/result/result}): @racket[(ok value)], or @racket[(err e)] for an expression that is
refused.

@racketblock[
(require vcl/compile vcl/decompile fhir/result/result)
(ok-value (vcl->valueset "(http://loinc.org)(85354-9;55284-4)"))   (code:comment "a ValueSet jsexpr")
(ok-value (vcl->valueset "(http://loinc.org)4548-4"                (code:comment "under an address of your own")
                         #:url "http://example.org/ValueSet/a1c" #:name "A1c"))
(define c (ok-value (vcl->compose "(http://loinc.org)(85354-9;55284-4)")))   (code:comment "just the compose")
(compose->vcl c)                         (code:comment "back to text: \"(http://loinc.org)(85354-9;55284-4)\"")
(validation-error-message (err-error (vcl->compose "*")))          (code:comment "why an expression was refused")
]

@section{In an editor, and for an AI agent}

@itemlist[
@item{@bold{In an editor.} The family's language server,
@hyperlink["https://oloveluck.github.io/fhir/fhir-lsp/index.html"]{fhir-lsp}, underlines a mistake
in a @tt{.vcl} file as you type: it compiles the one expression. It loads @tt{vcl/support} for
this.}
@item{@bold{For an agent.} In an
@hyperlink["https://oloveluck.github.io/fhir/fhir-mcp/index.html"]{fhir-mcp} workspace a file
@tt{diabetes-labs.vcl} is a value set whose address is the workspace's own address followed by
@tt{/ValueSet/diabetes-labs}, and the workspace's CQL libraries, profiles and validation find it by
that address. Running the file
expands it, and @tt{explain} with a system and a code says which part of the expression lets the
code in or keeps it out. This is @racketmodname[vcl/workspace]. The repository's @tt{guide.md} is
the language written for an agent to read (fhir-mcp serves it as @tt{learn://vcl}), and
@tt{.claude/skills/vcl} is the same workflow for an agent using the command line.}]

@section[#:tag "limits"]{Limits}

@itemlist[
@item{@bold{VCL can say more than a ValueSet can hold.} These are valid VCL, but a ValueSet's
@tt{compose} has no way to write them, so they are refused with a message that says so: taking
codes out anywhere but at the top level of the expression; "and" between plain codes, a value set
or @vcl{*}, or around an "or" in brackets (only rules can be combined with "and"); two different
code systems inside one "and"; a @vcl{*} with no code system. For example
@vcl{(http://loinc.org)(4548-4; 17856-6), (http://loinc.org)17856-6} gives
@tt{conjunction of non-filter terms is not compose-expressible}.}
@item{@bold{Give the code system.} A code written with no code system compiles to a group that
names none, which is not a valid ValueSet.}
@item{@bold{Expanding needs the code system}, and LOINC and SNOMED CT are not shipped. A rule over
a code system that is not at hand expands to no codes, without a warning (@secref["expanding"]).}
@item{@bold{Lists of rules.} A list of filters inside @vcl{^{…}} and the source of an @italic{of}
(@vcl{{concept<B}.prop}) are stored in the ValueSet as VCL text, in the filter's @tt{value}.}
@item{@bold{The of operator} matches nothing when the terminology tool expands a VCL value set.
Every other operator expands, @vcl{>>} and @vcl{!!<} included.}
@item{@bold{Decompiling loses what VCL cannot say}: a group that has both listed codes and rules
keeps the codes only; names (displays) and designations of codes, and the compose's @tt{inactive}
and @tt{lockedDate}, are dropped.}
@item{@bold{The address.} In the address made from an expression only spaces are escaped (as
@tt{%20}); other characters are left as written.}
@item{@bold{One expression, one line.} A file holds a single expression, and the specification
does not allow a line break inside it.}
@item{@bold{One difference from the official grammar}: a list with a single code, @vcl{prop^{a}},
is accepted here, so that a decompiled value set with a one-code list compiles again.}]

@section[#:tag "words"]{Words used here}

@itemlist[
@item{@bold{Code}: a short identifier with an agreed meaning, such as @tt{4548-4} for the HbA1c
test. @bold{Concept}: FHIR's word for a code together with its meaning.}
@item{@bold{Code system}: a published catalogue of codes (LOINC, SNOMED CT, FHIR's own small ones),
named by a web address. A CodeSystem resource carries its content.}
@item{@bold{Value set}: a named set of codes, drawn from one or more code systems. In FHIR, a
ValueSet resource.}
@item{@bold{Compose}: the part of a ValueSet that says which codes are in it: groups to
@tt{include} and to @tt{exclude}, each a code system with listed codes or filters. A VCL expression
is a compose on one line.}
@item{@bold{Filter}: a rule that picks codes by a property instead of listing them, such as "PRN
and everything below it".}
@item{@bold{Expansion}, @bold{expanding}: the list of the codes a value set actually holds, and
working it out. It needs the content of the code systems.}
@item{@bold{Display}: the human-readable name of a code ("father" for @tt{FTH}).}
@item{@bold{Implicit url}: the address a VCL value set goes by without being given one,
@tt{http://fhir.org/VCL?v1=} followed by the expression.}
@item{@bold{Binding}: the statement in a profile that an element's code must come from a given
value set.}
@item{@bold{Package}: a @tt{.tgz} file of FHIR resources, such as the FHIR core specification. It
is where the tools find code systems.}
@item{@bold{Terminology service}: the tool that answers questions about codes: expand a value set,
check a code. Here, @tt{fhir-tx}.}
@item{@bold{Decompile}: to turn a ValueSet back into the VCL that states it.}]

@section{How it is tested}

@itemlist[
@item{All 60 example expressions on the VCL specification's page are read, written back as text and
read again, giving the same expression each time.}
@item{A compose turned into VCL and compiled again is the same compose.}
@item{Every example in the repository's @tt{guide.md} is compiled, and its table of operators is
compared with what the compiler does.}]

@sh{raco test .} in the repository runs them all. The repository's @tt{TESTING.md} has the table.

@section{Reference}

For programmers: the modules of the package and what each provides.

@subsection[#:style 'unnumbered]{@hash-lang[] @tt{vcl}}
@defmodulelang[vcl]

Provides @racket[source], @racket[expression], @racket[compose] and @racket[valueset], as
@secref["module"] describes.

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
