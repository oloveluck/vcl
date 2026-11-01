# CLAUDE.md — fhir-vcl

Conventions, HTDP design style, and the conformance ratchet table live in the main `fhir` repo's
CLAUDE.md (`~/Projects/fhir`); this file holds only the notes for this package. Cross-directory
imports use collection paths (`fhir/model/node`, never `../model/node.rkt`): the family of packages
splices into the one `fhir` collection, so a directory can move between repos without edits.

## VCL lang (`#lang fhir/vcl`, `vcl/`)
VCL — the ValueSet Compose Language (build.fhir.org/ig/FHIR/ig-guidance/vcl.html), a compact
URL-embeddable syntax for ValueSet composes — as the 5th brag lang. `vcl/parser/vcl.g4` is the
official ANTLR grammar vendored verbatim; `grammar.rkt` ports it rule-for-rule (documented
deviations: a named `tail` rule; codeList accepts a singleton so decompiled one-code `in` filters
round-trip). The lexer is faithful to the g4's deliberate URI greed (a URI token eats `;&^{}`
until whitespace/paren — hence the bracketed `(system)` form). Prefab AST + `lower`
(`parser/ast.rkt`), memoized `parse-vcl -> Result` (the cql pattern). `vcl/compile.rkt` maps AST →
ValueSet.compose: disjunction → include entries, conjunction → one include's AND'd filters,
top-level `-` → exclude, `(system)` distributes (codes collapse into one concept list), `^uri` →
valueSet, the 11 filter ops + R6 `of`; NOT compose-expressible (nested exclusion, conjoined
enumerations, bare `*`) errs clearly. `vcl-print` re-brackets compound members (the spec has NO
`,`/`;` precedence). `vcl/decompile.rkt` is the reverse (compose→VCL; nested filter values
reparse via the real grammar). Conformance: all **60 spec examples** (vendored,
`vcl/tests/vendor/`) parse AND survive the print∘parse fixpoint; compose round-trip law tested.
`#lang fhir/vcl` (one expression per file; parse errors are COMPILE errors) provides
source/expression/compose/valueset; `raco fhir vcl <expr>` prints the ValueSet. **Implicit VCL
ValueSets work in `$expand`**: `terminology/service.rkt` recognizes `http://fhir.org/VCL?v1=…`,
percent-decodes (spec SHALL), compiles, and expands against its index — so `%terminologies` and
the validator see VCL urls as real ValueSets.
