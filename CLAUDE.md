# CLAUDE.md — vcl

Conventions, HTDP design style, and the conformance ratchet table live in the main `fhir` repo's
CLAUDE.md (`~/Projects/fhir`); this file holds only the notes for this package. This repo root IS the
`vcl` collection (`(define collection "vcl")`): modules are `vcl/compile` etc., and imports of the
foundation use collection paths (`fhir/model/node`, never a relative path into another package).
The CLI is `cli.rkt` (`raco vcl`); the conformance runner(s) live in `tests/` behind `--tck`.

## VCL lang (`#lang vcl`, `vcl/`)
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
`#lang vcl` (one expression per file; parse errors are COMPILE errors) provides
source/expression/compose/valueset; `raco vcl <expr>` prints the ValueSet. **Implicit VCL
ValueSets work in `$expand`**: `terminology/service.rkt` recognizes `http://fhir.org/VCL?v1=…`,
percent-decodes (spec SHALL), compiles, and expands against its index — so `%terminologies` and
the validator see VCL urls as real ValueSets.

**Editor and agent support** (`support.rkt`, through `fhir/lang/support`): a document's diagnostics
(the one expression compiled to a compose); the language server loads it by collection name.

**Workspace support** (`workspace.rkt`): each `.vcl` file is the ValueSet `<canonical>/ValueSet/<stem>`
(name from the stem); `run` expands it by `$expand` (fhir-tx, dynamic-required — it depends on vcl),
else lists the enumerated codes and says so; `explain` of `system|code` evaluates each include and
exclude of the compose alone (printed back as VCL) and says which hold the code.

**Documentation for users and agents** (2026-11-09; the family's pattern, see the main repo's
CLAUDE.md). `guide.md` is the language for agents — cheat sheet, the operator table, a worked
example, what a compose cannot say, running it, common problems — provided by `vcl/workspace` as
`guide` (fhir-mcp's `learn://vcl`); `tests/guide-test.rkt` compiles every ```vcl block and checks
its claims (the operator table against the compiler, the worked example's compose and url, the
refusals, the command line on a `#lang vcl` file). `.claude/skills/vcl/SKILL.md` is the workflow
without MCP (every command in it was run). `scribblings/vcl.scrbl` is the manual;
`tests/docs-test.rkt` renders it and fails on a broken reference to its own sections or `vcl/…`
bindings. Writing them found and fixed: `raco vcl <file>` rejected EVERY file with a `#lang vcl`
line (blanking the line kept a newline, which VCL's lexer forbids; the line is now removed and a
diagnostic moved back to the file's line), and a `#lang vcl` module's parse error was positioned in
the bare expression (`<input>:1:28`), not the file (the reader now gives the string its srcloc and
the macro raises at the exact character). Also found then, and fixed in fhir-tx: `$expand`'s and
`$validate-code`'s `url` input did not compile an unregistered VCL url (the operations' resolver now
falls back to the implicit VCL ValueSet, as `raco fhir-tx expand` and `%terminologies` did).

**A file that is not there; terms with no system** (2026-11-13). Found writing the manual, each
with a test that fails without the fix (`tests/cli-test.rkt`, compile.rkt's and cli.rkt's tests):
- `raco vcl nothere.vcl` compiled the file NAME as an expression (the code `nothere`, its property
  `vcl`), exit 0. An argument that can only be a file (`file-like?` in cli.rkt: it ends in `.vcl` or
  has a `/`, and has none of the characters an expression with either needs — brackets, `^`, quotes,
  operators) is opened as one: with no file, the family's `vcl: cannot read <path>`, exit 2.
  `(http://example.org/cs)panadol.vcl` and `^http://…/ValueSet/x` are still expressions.
- `a;b` compiled to includes with no `system`. The grammar makes the `(system)` prefix optional and
  the specification's examples use it (`A;B`, `concept<<B`, `(10007-3;10008-1)` — the 60 still parse
  and round-trip; nothing in the parser changed but positions), but a compose include that lists
  concepts or filters SHALL name their system (FHIR's vsd-1, vsd-2: the family's validator refused
  the ValueSet `raco vcl` printed). So the COMPILE step refuses a code or a filter that reaches its
  include with no system (`with-system`: `a code requires a (system) prefix to be
  compose-expressible: a`); `^valueset` needs none.
- **Refusals are positioned.** The parser keeps where each simple term stood (parse.rkt
  `syntax->datum/locs` over brag's syntax, `lower`'s `loc-of`, `attach-loc!` on the term — fml's
  pattern); compile.rkt raises a Refusal with the term (`refuse`), and the error carries a `compile`
  diagnostic (`attached-diagnostic`) at the term, or at the first term of a group (`term-loc`), with
  the message alone (the command line printed `VCL: invalid encoding "vcl: …" (see …)`). All four
  older refusals go the same way; `validation-error-message` is unchanged. An AST built by hand has
  no place.
- `#lang vcl` compiles the expression to its compose when the module is BUILT (base.rkt's
  `vcl-source` checks `vcl->compose`, not only the parse): a refusal is a syntax error at the term
  (`a;b`, `*` were a run-time error with a stack trace). workspace.rkt gives a problem that names no
  file its file (`in-file`: a parse error had none, so the hub could not list it under the file).
