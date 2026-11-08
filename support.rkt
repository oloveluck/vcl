#lang racket/base

;;; support.rkt — what VCL offers the family's editor and agent hubs (fhir/lang/support): the
;;; diagnostics of a document (one expression, parsed and compiled to a compose). A VCL document
;;; declares nothing, so there is no outline. What an agent runs is workspace.rkt.

(require racket/contract racket/string
         fhir/lang/support
         (only-in fhir/result/result ok? ok-value err-error validation-error-message)
         (only-in fhir/diagnostic attached-diagnostic)
         (only-in "compile.rkt" vcl->compose))

(provide (contract-out [support lang-support?]))

(define (diagnose text path)
  (define r (vcl->compose (string-trim (blank-lang-line text))))
  (cond
    [(ok? r) '()]
    [else (define e (err-error r))
          (list (or (attached-diagnostic e) (positionless 'vcl 'compile (validation-error-message e) path)))]))

(define support (lang-support "vcl" diagnose (lambda (p) '()) (lambda (t f) '())
                              (lambda (pr t pos) #f) (lambda (pr t pos) #f) (lambda (pr t pos) '())))

(module+ test
  (require rackunit)
  (check-equal? (diagnose "(http://loinc.org)1234-5" "/tmp/nowhere/a.vcl") '())
  (check-true (pair? (diagnose "(http://loinc.org" "/tmp/nowhere/b.vcl"))))
