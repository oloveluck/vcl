# fhir-vcl

VCL (ValueSet Compose Language) for Racket: parser, compiler to ValueSet.compose, decompiler and #lang fhir/vcl.

Part of **fhir — FHIR as a family of Racket `#lang`s** (main repo: `oloveluck/fhir`). This package
contributes `vcl/` to the shared `fhir` collection. `#lang fhir/vcl`.

## Depends on

`fhir-core`
(Racket packages; link them first) plus `brag-lib`, `br-parser-tools-lib`.

## Develop

```sh
raco pkg install --link --auto .     # link into the `fhir` collection
raco test vcl/
```

The `raco fhir` CLI and the conformance-suite runners are driven from the main `fhir` package:

```
raco fhir vcl '<expr>'   (prints the ValueSet)
```

Architecture notes: `CLAUDE.md` here; conventions and the ratchet table: the main repo's `CLAUDE.md`.
