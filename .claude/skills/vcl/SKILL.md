---
name: vcl
description: Write, check, compile, decompile and expand ValueSet Compose Language (VCL) expressions without an MCP server — `raco vcl` (an expression or a .vcl file to its ValueSet, a ValueSet back to VCL), expansion through fhir-tx, `#lang vcl` modules, and the Racket API. Use when writing a value set in VCL, turning a ValueSet compose into VCL, or expanding a value set an expression defines.
---

# VCL without MCP

Read [`guide.md`](../../../guide.md) first: the language in brief, a checked cheat sheet and
operator table, what a compose cannot say, and the common problems (that guide is what fhir-mcp
serves as `learn://vcl`). This skill is the workflow around it.

`vcl` and `raco vcl` are the same tool (the standalone build is `dist/bin/vcl`).

## The loop
1. **Compile.** `raco vcl '<expression>'` prints the ValueSet (its url is the implicit VCL url,
   `http://fhir.org/VCL?v1=<expression>`), or the error where the expression stops, exit 1:
   ```
   <expression>:1:28: vcl parse error: the expression ends after `17856-6`
   ```
   `raco vcl file.vcl` reads one expression from a file (a `#lang vcl` line before it is allowed);
   errors are placed on the file's own line. A file name with no file is `vcl: cannot read <path>`,
   exit 2 (it is not compiled as an expression). Codes or filters with no `(system)` are a compile
   error at the term, exit 1 (`a code requires a (system) prefix to be compose-expressible: male`
   for `male;female`): a ValueSet must name their code system. `--format json` (or `outcome`) puts the diagnostics on
   stdout as JSON (`line`, `column`, `message`, `phase`).
2. **Check what it means.** Read the `compose` back: each include is a system with codes or
   filters, an exclude is what `-` removes. `raco vcl --decompile valueset.json` prints any
   ValueSet's compose (or a bare compose) as VCL; decompiled text compiles back to the same compose.
3. **Expand.** With fhir-tx installed, the terminology service reads a VCL url as a ValueSet:
   ```
   raco fhir-tx expand 'http://fhir.org/VCL?v1=(http://hl7.org/fhir/administrative-gender)(male;female)'
   raco fhir-tx validate-code 'http://fhir.org/VCL?v1=(http://hl7.org/fhir/administrative-gender)(male;female)' \
       http://hl7.org/fhir/administrative-gender other          # => result false
   ```
   Quote the url (it holds `;`, `(`, spaces). Filters expand only over code systems in the packages
   (`--package <tgz|name>` adds one); enumerated codes are members either way.

Using the result elsewhere: give the ValueSet a url of your own and save it (a CQL `--valuesets`
directory, an FSH project's input), or reference the VCL url itself where a value set url is
accepted (the terminology service and the validator resolve it).

## From Racket
A `.vcl` file starting with `#lang vcl` is a module. The expression is checked when it compiles
(an error at its line and column), and requiring it registers the ValueSet by its url, so the
validator and the terminology service find it:
```racket
#lang racket/base
(require "bp.vcl")
(hash-ref valueset 'url)     ; => "http://fhir.org/VCL?v1=(http://loinc.org)(8480-6;%208462-4)"
compose                      ; the ValueSet.compose; also `source` and `expression` (the AST)
```
The functions, each answering a Result (`fhir/result/result`):
```racket
(require vcl/compile vcl/decompile fhir/result/result fhir/operation (only-in fhir/terminology/operations))
(ok-value (vcl->compose "(http://loinc.org)(4548-4; 17856-6)"))                       ; the compose
(ok-value (vcl->valueset "(http://loinc.org)4548-4" #:url "http://example.org/ValueSet/a1c"))  ; a ValueSet
(compose->vcl compose)                                                                 ; VCL text
(apply-operation "$expand" (ok-value (vcl->valueset expr)))                            ; expanded, through fhir-tx
```
A refused expression is `(err e)`; `(validation-error-message e)` says why ("exclusion is only
supported at the top level", …).

## Working on the package itself
`CLAUDE.md` is the architecture. `raco test .` runs everything: the specification's 60 examples
(parse, print, parse again), the compose round trip, and `tests/guide-test.rkt`, which keeps
guide.md's examples and claims true.
