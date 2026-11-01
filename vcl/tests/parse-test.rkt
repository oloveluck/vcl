#lang racket/base

;;; parse-test.rkt — every VCL expression the spec publishes must parse.
;;;
;;; The corpus is vendored verbatim (vendor/examples.txt — the spec page's Examples table +
;;; Additional Examples list). Two display artifacts of the spec page are normalized at load,
;;; NOT in the vendored file: typographic quotes (“ ”) become ASCII quotes, and the table's
;;; doubled backslash (markdown escaping) stays as-is — the parser handles both forms.

(require rackunit racket/runtime-path racket/file racket/string
         (only-in "../parser/parse.rkt" parse-vcl)
         (only-in fhir/result/result ok? err-error))

(define-runtime-path examples "vendor/examples.txt")

;; the spec page renders some quotes typographically — normalize for parsing
(define (normalize s) (string-replace (string-replace s "“" "\"") "”" "\""))

(define exprs (filter (lambda (l) (positive? (string-length (string-trim l))))
                      (file->lines examples)))
(check-true (>= (length exprs) 55))

(for ([e (in-list exprs)])
  (define r (parse-vcl (normalize e)))
  (check-true (ok? r) (format "did not parse: ~a~a" e
                              (if (ok? r) "" (format "  [~a]" (err-error r))))))

;; print ∘ parse is a fixpoint on the WHOLE corpus: re-parsing the canonical print of any
;; spec expression yields the identical AST
(require (only-in "../compile.rkt" vcl-print)
         (only-in fhir/result/result ok-value))
(for ([e (in-list exprs)])
  (define ast (ok-value (parse-vcl (normalize e))))
  (check-equal? (ok-value (parse-vcl (vcl-print ast))) ast
                (format "print/parse fixpoint broke on: ~a" e)))
