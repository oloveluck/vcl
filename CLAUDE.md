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

**A workspace problem at its own line** (2026-11-13): `workspace.rkt` cut the `#lang vcl` line off
before compiling and reported a problem at the expression's line 1 — one line early in the file.
`in-text` moves it by what stood before the expression (`prefix`: the `#lang` line, blank lines,
indentation), as the command line already did.


**Quality, performance and specification pass** (2026-11-13). The specification page's source
(FHIR/ig-guidance `input/pagecontent/vcl.md`; build.fhir.org itself was not reachable) was read
again: the grammar and the 60 examples are byte-identical to the vendored ones (SOURCE.txt files
say so). Held to a dump of everything the package gives over the 60 examples and ~90 probes
(AST, print and reparse, compose, decompile and the law, ValueSet, editor and workspace
diagnostics): every difference is one named below. Tests 238 -> 338.
- **Parsing is linear** (`parser/descent.rkt`, `descend`). brag's parser is quadratic in a flat
  list: 800 enumerated codes took 1.4 s, 4,000 about half a minute (a bench of several thousand
  never finished). The grammar is LL(3), so it is read directly, rule by rule, producing brag's own
  tree and the `simpleExpr` places `lower` reads; it only ever ACCEPTS — on any token it does not
  expect it answers #f and `parse.rkt` hands the tokens to brag (`brag-parse`), whose error is the
  diagnostic, so every message is brag's as before. 800 codes 2 ms, 8,000 23 ms; compile, print
  and decompile were already linear (8,000: 2-3 ms each). `tests/descent-test.rkt`: the two
  parsers agree, tree and places, on the 60 examples and 1,500 generated expressions (1,183
  accepted by both, 317 refused by both; it fails on a planted off-by-one). The memo is bounded
  (`cache-limit`, emptied at 4,096 texts: the terminology service compiles every implicit url).
- **The lexer** (`lexer.rkt`, now `tokenize : string -> (listof Token)`, positions from `lexer`'s
  own start/end, no srcloc wrapping, no WS tokens): letters and digits are ASCII's, as the g4 writes
  them (BEHAVIOUR: `café` unquoted and `http://ä.org` were accepted; the spec: codes with other
  characters are quoted, URIs percent-encoded); the g4's `+-.` inside the URI set is read as three
  characters, not ANTLR's range that holds the comma (unchanged behaviour, now said). A lex error
  quotes the text from the character that failed (it quoted what FOLLOWED it, `` `` `` for `@`),
  and says the three mistakes it can tell: a line break (`a line break is not permitted in a VCL
  expression`), a quoted value that does not end or holds another escape, an unquoted non-ASCII
  letter. An empty text is `the expression is empty` (brag's `unexpected no-tokens `#f``), as
  fhirpath says it.
- **The printer is its own module** (`print.rkt`, `vcl-print`, still provided by compile.rkt too),
  with ONE operator table (`filter-operators` in ast.rkt, `operator-lexeme`; ast.rkt had two,
  compile.rkt a third) and one bracketing function (`member-text`: `group` and `print-member` were
  the same). BEHAVIOUR (each broke print∘parse or the decompile law): a URI that something follows
  is printed with a space after it (`followed`, `ends-in-uri?`: `^vs ;…`, `{p^uri }`, `uri .p`; it
  was read back as one long URI, or not at all); a value set with a version as `^(uri|v)` (the
  version tail takes any character but a bracket); a URI-looking value after an operator other than
  `^`/`~^` is quoted (a decompiled `p=http://x/y` did not parse).
- **Compile** (compile.rkt): BEHAVIOUR — an `exists` value other than true/false is refused at the
  term (the g4's comment, FHIR's filter.value); a code holding a comma in a `^{…}` list is refused
  (the compose's value is one comma-separated list); value sets in a conjunction are one include's
  `valueSet` list, with its filters (`conj->include`: R5 on, an include's value sets intersect;
  they were refused as "non-filter terms"); the implicit url (`implicit-url`, now provided)
  percent-encodes `%`, whitespace, `#`, `&`, `+` and non-ASCII so that decoding gives the
  expression back (the spec: a reader SHALL percent-decode; `(http://x/a%28b%29)c` came back as
  `(http://x/a(b))c`, which does not lex) and leaves the rest as the spec's own example writes it.
- **Decompile** (decompile.rkt): BEHAVIOUR — an include's value sets are a conjunction, with its
  filters (`valueSet: [a, b]` printed `^a;^b`, which recompiled to ONE value set
  `http://a;^http://b`; filters dropped the value sets); a compose with no include and a nested
  list that is not VCL are said (`cdr`/`ok-value` contract violations).
- **One reading of a `.vcl` file's text** (`text.rkt`: `file-expression`, `in-file-text`,
  `with-file`) for cli.rkt (`shift`, its own head stripping, `with-source`), workspace.rkt
  (`prefix`, `in-text`, `in-file`) and support.rkt (`blank-lang-line` + trim). BEHAVIOUR: the
  editor put a problem in a `#lang vcl` file a line or more early (always line 1); `raco vcl`
  refused a blank line after `#lang vcl` (a lex error at it). workspace.rkt lost a module-level
  redefinition of an imported `exn:fail:diagnostic-diagnostic` through `dynamic-require`.
- Decided against / left: a conjunction around a disjunction (`p=x,(q=y;r=z)`) is refused though
  it distributes into includes (DNF; the text would not round-trip and can grow exponentially);
  `^vs,^vs` is read with R5's intersection (R4 said union); `(s)(a;b),^vs` (codes AND a value set,
  which a compose can hold) stays refused; a versioned URI as a `^` value can only end its list
  (the grammar has no bracketed form there); `of` and nested filter lists are not in FHIR R6
  ballot4's filter-operator codes (the manual's Limits say so).
