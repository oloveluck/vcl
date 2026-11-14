#lang racket/base

;;; support.rkt — what VCL offers the family's editor and agent hubs (fhir/lang/support): the
;;; diagnostics of a document (one expression, parsed and compiled to a compose). A VCL document
;;; declares nothing, so there is no outline. What an agent runs is workspace.rkt.

(require racket/contract
         fhir/lang/support
         (only-in fhir/result/result ok? err-error validation-error-message)
         (only-in fhir/diagnostic attached-diagnostic)
         (only-in "compile.rkt" vcl->compose)
         (only-in "text.rkt" file-expression in-file-text))

(provide (contract-out [support lang-support?]))

;; diagnose : string path -> (listof diagnostic)   the expression's problem, at its place in the
;; document (after a `#lang vcl` line it was reported a line or more early)
(define (diagnose text path)
  (define r (vcl->compose (file-expression text)))
  (cond
    [(ok? r) '()]
    [else (define e (err-error r))
          (list (or (let ([d (attached-diagnostic e)]) (and d (in-file-text d text)))
                    (positionless 'vcl 'compile (validation-error-message e) path)))]))

(define support (lang-support "vcl" diagnose (lambda (p) '()) (lambda (t f) '())
                              (lambda (pr t pos) #f) (lambda (pr t pos) #f) (lambda (pr t pos) '())))

(module+ test
  (require rackunit (only-in fhir/diagnostic diagnostic-loc loc-line loc-column))
  (check-equal? (diagnose "(http://loinc.org)1234-5" "/tmp/nowhere/a.vcl") '())
  (check-true (pair? (diagnose "(http://loinc.org" "/tmp/nowhere/b.vcl")))
  ;; at its line and column in the document, after a `#lang vcl` line, a blank one and indentation
  (define d (car (diagnose "#lang vcl\n\n  (http://loinc.org)4548-4; 17856-6\n" "/tmp/nowhere/c.vcl")))
  (check-equal? (list (loc-line (diagnostic-loc d)) (loc-column (diagnostic-loc d))) '(3 29)))
