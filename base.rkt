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

(require (for-syntax racket/base syntax/parse
                     (only-in vcl/parser/parse parse-vcl)
                     (only-in fhir/result/result ok? err-error)
                     (only-in fhir/result/result validation-error-message)
                     (only-in fhir/diagnostic attached-diagnostic diagnostic-message diagnostic-loc
                              loc-line loc-column loc-position loc-span))
         json
         (only-in "parser/parse.rkt" parse-vcl)
         (only-in "compile.rkt" vcl->compose vcl->valueset)
         (only-in fhir/result/result ok-value ok-or-raise)
         (only-in fhir/registry register-resources!))

(provide (except-out (all-from-out racket/base) #%module-begin)
         (rename-out [vcl-module-begin #%module-begin])
         vcl-source)

;; compile-time validation: the expression must parse (its Result is re-derived at runtime). The
;; error is a syntax error at the character the parser stopped at: the expression's place in the
;; file (the reader's srcloc on the string) plus the diagnostic's place in the expression.
(define-syntax (vcl-source stx)
  (syntax-case stx ()
    [(_ src)
     (let ([r (parse-vcl (syntax-e #'src))])
       (unless (ok? r)
         (define d (attached-diagnostic (err-error r)))
         (define l (and d (diagnostic-loc d)))
         (if (and l (syntax-line #'src) (loc-line l) (loc-column l))
             (raise-syntax-error
              'vcl (diagnostic-message d)
              (datum->syntax #f (syntax-e #'src)
                             (list (syntax-source #'src)
                                   (+ (syntax-line #'src) (sub1 (loc-line l)))   ; (one line: the spec forbids newlines)
                                   (+ (syntax-column #'src) (sub1 (loc-column l)))
                                   (and (syntax-position #'src) (loc-position l) (+ (syntax-position #'src) (sub1 (loc-position l))))
                                   (or (loc-span l) 1))))
             (raise-syntax-error 'vcl (validation-error-message (err-error r)) stx)))
       #'src)]))

;; the module body the reader produces: exactly one (vcl-source "…") form
(begin-for-syntax
  (define-syntax-class source-form
    #:description "one (vcl-source \"…\") form, as the #lang vcl reader writes it"
    (pattern ((~datum vcl-source) src:str))))

(define-syntax (vcl-module-begin stx)
  (syntax-parse stx
    [(_ form:source-form) #'(vcl-module-body form)]))

(define-syntax-rule (vcl-module-body src-form)
  (#%module-begin
   (define source src-form)
   (define expression (ok-or-raise (parse-vcl source)))
   (define compose (ok-or-raise (vcl->compose expression)))
   (define valueset (ok-or-raise (vcl->valueset source)))
   ;; the module system as the FHIR registry: the value set resolves by its url once the module
   ;; is required (`$expand #:url`, a binding's value set)
   (register-resources! (list valueset) #:source (variable-reference->module-source (#%variable-reference)))
   (provide source expression compose valueset)
   (module+ main
     (displayln (jsexpr->string valueset)))))
