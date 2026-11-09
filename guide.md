# ValueSet Compose Language (VCL)

VCL writes a value set in one line: which codes from which code systems, by enumeration or by
filter, and which to leave out. An expression compiles to a FHIR `ValueSet.compose`, and back: a
compose decompiles to VCL. Every example on the specification's page parses here, and survives
printing and parsing again.

This guide is for writing VCL here: the language in brief, the ways to run it, and what to do when
something goes wrong. The specification is the reference for the language itself.

## Official reference
- VCL specification: https://build.fhir.org/ig/FHIR/ig-guidance/vcl.html

## Cheat sheet
```vcl
(http://loinc.org)(4548-4; 17856-6)
```
Two codes from LOINC. Each line below is an expression of its own:
```vcl
(http://snomed.info/sct)concept<<73211009
```
```vcl
(http://snomed.info/sct)concept<73211009
```
```vcl
(http://loinc.org)(4548-4; 17856-6) - (http://loinc.org)17856-6
```
```vcl
(http://loinc.org)*
```
```vcl
^http://hl7.org/fhir/ValueSet/administrative-gender
```
```vcl
(http://loinc.org)(COMPONENT="Hemoglobin A1c", SYSTEM="Bld")
```
In order: a concept and its descendants (an `is-a` filter); its descendants only (`descendent-of`);
an exclusion (`compose.exclude`); every code of a system; another value set
(`compose.include.valueSet`); two property filters that must both hold.

`;` is or and `,` is and, with no precedence between them: a part mixing them must be bracketed. A
system in round brackets applies to what follows it, and distributes over a bracketed list. A filter
is `property op value`, its operators the FHIR filter operators:

| VCL | FHIR | VCL | FHIR |
|---|---|---|---|
| `=` | `=` | `<<` | `is-a` |
| `<` | `descendent-of` | `~<<` | `is-not-a` |
| `<!` | `child-of` | `!!<` | `descendent-leaf` |
| `>>` | `generalizes` | `^{a,b}` | `in` |
| `~^{a,b}` | `not-in` | `/"regex"` | `regex` |
| `?true` | `exists` | | |

An expression is one line: the specification forbids newlines.

## Worked example
Hemoglobin A1c, by its two LOINC codes:
```vcl
(http://loinc.org)(4548-4; 17856-6)
```
It compiles to the compose
`{"include": [{"system": "http://loinc.org", "concept": [{"code": "4548-4"}, {"code": "17856-6"}]}]}`,
and its implicit value set url is the expression itself:
`http://fhir.org/VCL?v1=(http://loinc.org)(4548-4;%2017856-6)`.

## What a compose cannot say
VCL is wider than `ValueSet.compose`. These parse, but do not compile to a compose, and say so:
- an exclusion inside another part, `(http://loinc.org)4548-4 - ((http://loinc.org)* - (http://loinc.org)17856-6)`:
  `compose.exclude` applies to the whole value set, so exclusion is only supported at the top level;
- enumerations joined by `,` (and), `(http://loinc.org)(4548-4; 17856-6), (http://loinc.org)17856-6`:
  a compose can intersect filters, not lists of codes;
- `*` without a system: a compose names the system it takes every code from.

## Running it
**Command line.** `vcl` (or `raco vcl`):
```
vcl '(http://loinc.org)(4548-4; 17856-6)'       # the ValueSet, as JSON (url: the implicit VCL url)
vcl hba1c.vcl                                    # the expression in a file
vcl --decompile valueset.json                    # a ValueSet's (or a bare compose's) VCL
```
An expression that does not parse or compile is reported where it stops (`--format json` or
`outcome` for machine-readable diagnostics), with exit status 1.

**Expanding.** The terminology service (fhir-tx) reads a VCL url as a ValueSet:
`fhir-tx expand 'http://fhir.org/VCL?v1=(http://hl7.org/fhir/administrative-gender)(male;female)'`
lists the codes, with displays, from the code systems in its packages. Codes a VCL expression
enumerates are members without any code system; a filter needs the code system's content.

**As a module.** A file that starts with `#lang vcl` holds one expression and is a Racket module
providing `source`, `expression` (the AST), `compose` and `valueset`. The expression is checked when
the module compiles (an error at its line and column), and requiring the module registers the
ValueSet by its url, so the validator and the terminology service find it.

**In a workspace** (fhir-mcp). A `.vcl` file is the ValueSet `<canonical>/ValueSet/<file name>`:
CQL libraries, FSH bindings and validation see it by that url. `run` expands it with the
terminology service, over the code systems in the packages and in the workspace (without the
service installed, it lists the enumerated codes and says the rest could not be expanded).
`explain` with a `system|code` says which include or exclude of the expression admits or rules out
the code. `query("vcl", "<expression>")` expands an expression without a file.

## Common problems
- `lex error: unrecognized text` where a line breaks: an expression is one line (a file may end
  with a newline, and a `#lang vcl` line before it).
- `unexpected comma` in `a; b, c`: `;` and `,` have no precedence; bracket one side.
- `… is not compose-expressible`: see "What a compose cannot say".
- `the expression ends after http://loinc.org|4548-4`: a system goes in round brackets,
  `(http://loinc.org)4548-4`. A URI takes every character up to whitespace or a bracket, so
  without brackets the code is read as part of it.
- "does not expand": the expression filters a code system that is not in the packages (SNOMED CT and
  LOINC are not shipped). Enumerated codes are still members; filters need the code system.
