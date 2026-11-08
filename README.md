# vcl — ValueSet Compose Language

[VCL](https://build.fhir.org/ig/FHIR/ig-guidance/vcl.html), the compact, URL-embeddable syntax for a
ValueSet's compose: a port of the official grammar, a compiler to `ValueSet.compose`, and a
decompiler back to VCL. All 60 examples on the spec page parse and survive printing and re-parsing.
The terminology service expands implicit VCL ValueSets (`http://fhir.org/VCL?v1=…`) like any other.

Part of the [fhir](https://github.com/oloveluck/fhir) family of FHIR languages and tools.

## Command line

`vcl` is one of the family's command-line tools, which run without Racket:
[build them once](https://github.com/oloveluck/fhir#getting-the-tools) and put `dist/bin` on your
`PATH`. With Racket and the packages installed, `raco vcl` runs the same commands.

```sh
vcl '(http://loinc.org)(8480-6;8462-4)'      # an expression: the ValueSet, as JSON
vcl diabetes.vcl                              # an expression in a file
vcl --decompile valueset.json                 # a ValueSet's compose, as VCL
```

```
$ vcl '(http://loinc.org)(8480-6;8462-4)'
{"compose":{"include":[{"concept":[{"code":"8480-6"},{"code":"8462-4"}],"system":"http://loinc.org"}]},"name":"VCLExpression","resourceType":"ValueSet","status":"active","url":"http://fhir.org/VCL?v1=(http://loinc.org)(8480-6;8462-4)"}
```

A filter such as `(http://snomed.info/sct)concept<<73211009` becomes an `is-a` filter. An expression
that doesn't parse is reported where it stops, with exit status 1:

```
$ vcl '(http://loinc.org)(8480-6;'
<expression>:1:26: vcl parse error: the expression ends after `;`
 1 | (http://loinc.org)(8480-6;
   |                          ^
```

## In Racket

`#lang vcl` makes a `.vcl` file a module holding one expression. It is checked when the module is
compiled, and the ValueSet is registered by its url, so the validator and the terminology service
find it. With `bp.vcl`:

```racket
#lang vcl
(http://loinc.org)(8480-6;8462-4)
```

a Racket program uses it like any module:

```racket
#lang racket/base
(require "bp.vcl")
valueset            ; the ValueSet (also: source, expression, compose)
```

`racket bp.vcl` prints the ValueSet. As a library, `vcl/compile` turns an expression into a ValueSet
(`vcl->valueset`, a Result) and `vcl/decompile` a compose back into VCL (`compose->vcl`).

## Develop

From source, with the family's repositories side by side:

```sh
raco pkg install --link --auto ../fhir/fhir ../fhir/fhir-spec .
raco test .          # unit tests, including the spec's 60 examples
```

Reference documentation: [oloveluck.github.io/vcl](https://oloveluck.github.io/vcl/). Architecture
notes: `CLAUDE.md`; the family's conventions and conformance table are in the fhir repository's
`CLAUDE.md`. License: MIT (vendored test corpora keep their own terms, see `tests/vendor`).
