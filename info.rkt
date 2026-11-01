#lang info

;; fhir-vcl — part of the `fhir` family of Racket packages (FHIR as a family of #langs).
;; Every package in the family declares `(define collection "fhir")`, so they splice into the
;; one `fhir` collection: module paths (fhir/...) and #lang names are the same as in the monorepo.

(define collection "fhir")
(define version "0.2")
(define pkg-desc "VCL (ValueSet Compose Language) for Racket: parser, compiler to ValueSet.compose, decompiler and #lang fhir/vcl")
(define pkg-authors '(oloveluck))
(define deps '("base" "fhir-core" "brag-lib" "br-parser-tools-lib"))
(define build-deps '("rackunit-lib"))
