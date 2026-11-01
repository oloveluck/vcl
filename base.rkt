#lang racket/base

;;; base.rkt — the module language for #lang vcl.
;;;
;;; The reader hands over the file's single VCL expression as (vcl-source "…"). The module
;;; language parses it AT COMPILE TIME (a bad expression is a syntax error, like every other lang
;;; here), then provides:
;;;   source     : the original text
;;;   expression : the VCL AST (prefab)
;;;   compose    : the ValueSet.compose jsexpr
;;;   valueset   : the full ValueSet resource jsexpr (url = the implicit VCL url)
;;; `main` prints the ValueSet JSON.

(require (for-syntax racket/base
                     (only-in vcl/parser/parse parse-vcl)
                     (only-in fhir/result/result ok? err-error)
                     (only-in fhir/result/result validation-error-message))
         json
         (only-in "parser/parse.rkt" parse-vcl)
         (only-in "compile.rkt" vcl->compose vcl->valueset)
         (only-in fhir/result/result ok-value ok-or-raise))

(provide (except-out (all-from-out racket/base) #%module-begin)
         (rename-out [vcl-module-begin #%module-begin])
         vcl-source)

;; compile-time validation: the expression must parse (its Result is re-derived at runtime)
(define-syntax (vcl-source stx)
  (syntax-case stx ()
    [(_ src)
     (let ([r (parse-vcl (syntax-e #'src))])
       (unless (ok? r)
         (raise-syntax-error 'vcl (validation-error-message (err-error r)) stx))
       #'src)]))

(define-syntax-rule (vcl-module-begin src-form)
  (#%module-begin
   (define source src-form)
   (define expression (ok-or-raise (parse-vcl source)))
   (define compose (ok-or-raise (vcl->compose expression)))
   (define valueset (ok-or-raise (vcl->valueset source)))
   (provide source expression compose valueset)
   (module+ main
     (displayln (jsexpr->string valueset)))))
