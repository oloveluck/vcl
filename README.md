# vcl — ValueSet Compose Language

A *value set* is a named set of codes: "the lab tests used to follow diabetes", "the codes that
mean a parent". FHIR writes one as a ValueSet resource, a page of JSON.
[VCL](https://build.fhir.org/ig/FHIR/ig-guidance/vcl.html) writes it on one line: which codes, from
which code system, listed one by one or described by a rule. This package turns a VCL expression
into the ValueSet resource and a ValueSet back into VCL; a mistake is reported where the expression
stops.

```
$ vcl '(http://loinc.org)(4548-4;2345-7)'
{"compose":{"include":[{"concept":[{"code":"4548-4"},{"code":"2345-7"}],"system":"http://loinc.org"}]},"name":"VCLExpression","resourceType":"ValueSet","status":"active","url":"http://fhir.org/VCL?v1=(http://loinc.org)(4548-4;2345-7)"}
$ vcl --decompile ValueSet-marital-status.json
(http://terminology.hl7.org/CodeSystem/v3-MaritalStatus)*;(http://terminology.hl7.org/CodeSystem/v3-NullFlavor)UNK
```

The first line names two LOINC codes and prints the ValueSet for them. The second reads a value set
FHIR publishes and prints it as VCL: every marital status, and "unknown".

## Install

Build the [fhir family's tools](https://github.com/oloveluck/fhir#install) once; `vcl` is one of
them. With Racket, `raco vcl` is the same command.

## Documentation

**[oloveluck.github.io/vcl](https://oloveluck.github.io/vcl/)**: what a value set is, a first
example explained step by step, how to write an expression, listing the codes a value set holds,
and the reference.

- How well it works (all 60 examples of the VCL specification): [TESTING.md](TESTING.md).
- For AI agents: [guide.md](guide.md), a cheat sheet and the common problems, each example tested;
  and the [vcl skill](.claude/skills/vcl/SKILL.md).
- How it is built: [CLAUDE.md](CLAUDE.md).

Part of the [fhir](https://github.com/oloveluck/fhir) family. License: MIT.
