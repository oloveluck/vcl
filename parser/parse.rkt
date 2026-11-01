#lang racket/base

;;; parse.rkt — string -> Result<VclExpr> (memoized, Result-not-exceptions — the cql pattern).

(require racket/contract
         (prefix-in g: "grammar.rkt")
         "lexer.rkt" "ast.rkt"
         (only-in fhir/result/result ok err ok? result?)
         (only-in fhir/result/result invalid-encoding))

(provide (contract-out [parse-vcl (-> string? result?)]))

(define cache (make-hash))

(define (parse-vcl src)
  (hash-ref! cache src
             (lambda ()
               (with-handlers ([exn:fail? (lambda (e)
                                            (err (invalid-encoding 'VCL
                                                  "https://build.fhir.org/ig/FHIR/ig-guidance/vcl.html"
                                                  (exn-message e))))])
                 (ok (lower (g:parse-to-datum (tokenize (open-input-string src)))))))))

(module+ test
  (require rackunit (only-in fhir/result/result ok-value))
  (define (p s) (ok-value (parse-vcl s)))
  ;; the spec's Examples table, as AST shapes
  (check-equal? (p "B") (vcl-code "B"))
  (check-equal? (p "\"B.123\"") (vcl-code "B.123"))
  (check-equal? (p "*") (vcl-star))
  (check-equal? (p "concept << B") (vcl-filter "concept" 'is-a "B"))
  (check-equal? (p "parent = B") (vcl-filter "parent" '= "B"))
  (check-equal? (p "a , b") (vcl-conj (list (vcl-code "a") (vcl-code "b"))))
  (check-equal? (p "a ; b") (vcl-disj (list (vcl-code "a") (vcl-code "b"))))
  (check-equal? (p "^http://example.com/ValueSet/123")
                (vcl-include "http://example.com/ValueSet/123"))
  (check-equal? (p "(http://loinc.org)(a;b)")
                (vcl-sub (cons "http://loinc.org" #f)
                         (vcl-disj (list (vcl-code "a") (vcl-code "b")))))
  (check-equal? (p "(http://x.org|2.1)z")
                (vcl-sub (cons "http://x.org" "2.1") (vcl-code "z")))
  (check-equal? (p "property^{123,456}")
                (vcl-filter "property" 'in (vcl-code-list '("123" "456"))))
  (check-equal? (p "code/\"A[0-9]*\\\\.9\"") (vcl-filter "code" 'regex "A[0-9]*\\.9"))
  (check-equal? (p "ingredient?true") (vcl-filter "ingredient" 'exists "true"))
  (check-equal? (p "concept~<<929360061000036106")
                (vcl-filter "concept" 'is-not-a "929360061000036106"))
  ;; the R6 "of" operator, reversed arguments
  (check-equal? (p "B.codeprop") (vcl-of (vcl-code "B") "codeprop"))
  (check-equal? (p "{concept<B}.codeprop")
                (vcl-of (vcl-filter-list (list (vcl-filter "concept" 'descendent-of "B"))) "codeprop"))
  ;; nested filters (in with a filterList)
  (check-equal? (p "has_ingredient^{has_tradename=2201670}")
                (vcl-filter "has_ingredient" 'in
                            (vcl-filter-list (list (vcl-filter "has_tradename" '= "2201670")))))
  ;; exclusion
  (check-equal? (p "(a;b)-(c)")
                (vcl-excl (vcl-disj (list (vcl-code "a") (vcl-code "b"))) (vcl-code "c")))
  ;; a parse error is a Result, not an exception
  (check-false (ok? (parse-vcl "((("))))
