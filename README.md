# vcl — ValueSet Compose Language for Racket

VCL (build.fhir.org/ig/FHIR/ig-guidance/vcl.html), the compact URL-embeddable syntax for ValueSet composes: a brag port of the official grammar, a compiler to `ValueSet.compose`, a decompiler back to VCL, and `#lang vcl`. All 60 spec examples parse and survive the print∘parse fixpoint.

Part of **fhir — FHIR as a family of Racket `#lang`s** ([oloveluck/fhir](https://github.com/oloveluck/fhir)).
Collection `vcl`. `#lang vcl` — a `.vcl` file is a module; `racket file` prints the compiled JSON.
Reference: [oloveluck.github.io/vcl](https://oloveluck.github.io/vcl/).

## Install

```sh
raco pkg install vcl          # once published on pkgs.racket-lang.org
# from source, with the family repos side by side:
raco pkg install --link --auto ../fhir/fhir .
```

Depends on `fhir` (only `fhir/result/result`).

## Use

```racket
(require vcl/compile vcl/decompile)   ; vcl->valueset : string -> Result<jsexpr> ; compose->vcl : jsexpr -> string
```

```sh
raco vcl '(http://loinc.org)(a;b)'      # ValueSet JSON (implicit VCL url)
raco vcl expression.vcl
raco vcl --decompile valueset.json
```

## Develop

```sh
raco test .          # unit tests (the conformance runners are explicit: see the --tck commands above)
```

Architecture notes: `CLAUDE.md`. Conventions, design style and the family-wide conformance table: the
main repo's `CLAUDE.md`. License: MIT (vendored test corpora keep their own terms — see `tests/vendor`).
