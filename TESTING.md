# Testing vcl

## Results

| Suite | What it checks | Result |
|---|---|---|
| The VCL spec page's examples (`tests/vendor/examples.txt`, from its Examples table) | each expression parses, and printing it and parsing the print gives the same expression | 60/60 |
| Decompile and compile | a compose decompiled to VCL and compiled again is the same compose | `decompile.rkt`'s tests |

Expressions the spec allows but `ValueSet.compose` cannot express (a nested exclusion, conjoined
enumerations, a bare `*`) are compile errors that say so, not approximations.

## Running them

```sh
raco test .          # all of them (190 checks)
```
