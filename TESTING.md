# Testing vcl

## Results

| Suite | What it checks | Result |
|---|---|---|
| The VCL spec page's examples (`tests/vendor/examples.txt`, from its Examples table) | each expression parses, and printing it and parsing the print gives the same expression | 60/60 |
| Decompile and compile | a compose decompiled to VCL and compiled again is the same compose | `decompile.rkt`'s tests |
| The guide (`tests/guide-test.rkt`) | every VCL example in guide.md compiles; its operator table is the compiler's; the worked example's compose and url, and the refusals it describes, are as written; the command line reads a `#lang vcl` file and places an error on the file's line | passes |
| The manual (`tests/docs-test.rkt`) | scribblings/vcl.scrbl renders with no broken reference to its own sections or bindings | passes |
| The command line (`tests/cli-test.rkt`) | a file name with no file is "cannot read" (exit 2), not an expression; codes with no code system are a compile error at the code (exit 1), at the command line and when a `#lang vcl` module is built; expressions with `.vcl` or `/` in them still compile | passes |

Expressions the spec allows but `ValueSet.compose` cannot express (a nested exclusion, conjoined
enumerations, a bare `*`, a code or a filter with no code system) are compile errors that say so,
positioned at the term, not approximations.

## Running them

```sh
raco test .          # all of them (236 checks)
```
