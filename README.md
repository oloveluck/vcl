# vcl — ValueSet Compose Language

[VCL](https://build.fhir.org/ig/FHIR/ig-guidance/vcl.html), the compact, URL-embeddable syntax for a
ValueSet's compose: a parser, a compiler to `ValueSet.compose`, and a decompiler back to VCL. All 60
examples on the spec page parse; [TESTING.md](TESTING.md) has the details.

Part of the [fhir](https://github.com/oloveluck/fhir) family of FHIR languages and tools.

## Command line

[Build the family's tools](https://github.com/oloveluck/fhir#getting-the-tools) once and put
`dist/bin` on your `PATH`; they run without Racket. With Racket installed, `raco vcl` is the same.

```sh
vcl '(http://loinc.org)(8480-6;8462-4)'      # the ValueSet, as JSON
vcl diabetes.vcl                              # an expression in a file
vcl --decompile valueset.json                 # a ValueSet's compose, as VCL
```

```
$ vcl '(http://loinc.org)(8480-6;8462-4)'
{"compose":{"include":[{"concept":[{"code":"8480-6"},{"code":"8462-4"}],"system":"http://loinc.org"}]},"name":"VCLExpression","resourceType":"ValueSet","status":"active","url":"http://fhir.org/VCL?v1=(http://loinc.org)(8480-6;8462-4)"}
```

An expression that doesn't parse is reported where it stops, with exit status 1.

## In Racket

A `.vcl` file that starts with `#lang vcl` is a module holding one expression, checked when compiled:

```racket
#lang racket/base
(require "bp.vcl")
valueset            ; the ValueSet, registered by its url for the validator and terminology service
```

## Develop

```sh
raco pkg install --link --auto ../fhir/fhir ../fhir/fhir-spec .   # repos side by side
raco test .
```

Reference: [oloveluck.github.io/vcl](https://oloveluck.github.io/vcl/). Architecture: `CLAUDE.md`.
License: MIT.
