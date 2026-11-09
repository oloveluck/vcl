#lang s-exp syntax/module-reader

;;; reader.rkt — the #lang vcl reader.
;;;
;;; A .vcl file is ONE VCL expression (whitespace-trimmed; the spec prohibits newlines inside an
;;; expression, but the file may end with one). The reader emits a single (vcl-source "…") form;
;;; the module language vcl/base parses/compiles it.

vcl/base

#:read        vcl-read
#:read-syntax vcl-read-syntax
#:whole-body-readers? #t

(require (only-in racket/port port->string)
         (only-in racket/string string-trim))

(define (vcl-read-syntax src in)
  ;; the expression string carries its place in the file (after leading whitespace), so a parse error
  ;; is reported at its line and column there
  (port-count-lines! in)
  (let skip () (when (and (char? (peek-char in)) (char-whitespace? (peek-char in))) (read-char in) (skip)))
  (define-values (line col pos) (port-next-location in))
  (define text (string-trim (port->string in)))
  (list (datum->syntax #f (list 'vcl-source (datum->syntax #f text (list src line col pos (string-length text)))))))

(define (vcl-read in)
  (map syntax->datum (vcl-read-syntax #f in)))
