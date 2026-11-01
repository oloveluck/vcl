#lang s-exp syntax/module-reader

;;; reader.rkt — the #lang fhir/vcl reader.
;;;
;;; A .vcl file is ONE VCL expression (whitespace-trimmed; the spec prohibits newlines inside an
;;; expression, but the file may end with one). The reader emits a single (vcl-source "…") form;
;;; the module language fhir/vcl/base parses/compiles it.

fhir/vcl/base

#:read        vcl-read
#:read-syntax vcl-read-syntax
#:whole-body-readers? #t

(require (only-in racket/port port->string)
         (only-in racket/string string-trim))

(define (vcl-read-syntax src in)
  (list (datum->syntax #f (list 'vcl-source (string-trim (port->string in))))))

(define (vcl-read in)
  (map syntax->datum (vcl-read-syntax #f in)))
