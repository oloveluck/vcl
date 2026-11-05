#lang racket/base

;;; support.rkt — what VCL offers the family's editor and agent hubs (fhir/lang/support): the
;;; diagnostics of a document (one expression, parsed and compiled to a compose) and the tool that
;;; compiles an expression to a ValueSet. A VCL document declares nothing, so there is no outline.

(require racket/contract racket/string json
         fhir/lang/support
         (only-in fhir/result/result ok? ok-value err-error validation-error-message)
         (only-in fhir/diagnostic attached-diagnostic)
         (only-in "compile.rkt" vcl->compose vcl->valueset))

(provide (contract-out [support lang-support?]))

(define (diagnose text path)
  (define r (vcl->compose (string-trim (blank-lang-line text))))
  (cond
    [(ok? r) '()]
    [else (define e (err-error r))
          (list (or (attached-diagnostic e) (positionless 'vcl 'compile (validation-error-message e) path)))]))

(define tools
  (list
   (tool "vcl_valueset"
         "Compile a VCL expression (the ValueSet Compose Language) to a ValueSet resource."
         (text-schema 'vcl "the VCL expression")
         (lambda (args)
           (define src (string-arg args 'vcl))
           (cond [(not src) (missing 'vcl)]
                 [else (define r (vcl->valueset src))
                       (if (ok? r) (values (jsexpr->string (ok-value r)) #f) (values (validation-error-message (err-error r)) #t))])))))

(define support (lang-support "vcl" diagnose (lambda (p) '()) (lambda (t f) '())
                              (lambda (pr t pos) #f) (lambda (pr t pos) #f) (lambda (pr t pos) '()) tools))

(module+ test
  (require rackunit)
  (check-equal? (diagnose "(http://loinc.org)1234-5" "/tmp/nowhere/a.vcl") '())
  (check-true (pair? (diagnose "(http://loinc.org" "/tmp/nowhere/b.vcl")))
  (define-values (t e) (call-tool (car tools) (hasheq 'vcl "(http://loinc.org)1234-5")))
  (check-false e) (check-equal? (hash-ref (string->jsexpr t) 'resourceType) "ValueSet")
  (define-values (t2 e2) (call-tool (car tools) (hasheq)))
  (check-true e2))
