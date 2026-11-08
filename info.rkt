#lang info

(define collection "vcl")
(define version "0.3")
(define pkg-desc "VCL (ValueSet Compose Language): parser, compiler to ValueSet.compose, decompiler; the vcl command-line tool and #lang vcl")
(define pkg-authors '(oloveluck))
(define license 'MIT)
(define deps '("base" "fhir" "brag-lib" "br-parser-tools-lib"))
(define build-deps '("rackunit-lib" "scribble-lib" "racket-doc"))
(define scribblings '(("scribblings/vcl.scrbl" ())))
(define raco-commands '(("vcl" (submod vcl/cli main) "compile a VCL expression to a ValueSet; decompile a ValueSet to VCL" #f)))
(define test-omit-paths '("tests/vendor" "scribblings"))
