#lang racket/base

;;; decompile.rkt — ValueSet.compose (jsexpr) -> VCL text (the GoFSH direction).
;;;
;;; Inverse of compile.rkt's mapping: each include entry becomes a (system)-prefixed group —
;;; concepts as a disjunction, filters as a conjunction, valueSet as ^uri — multiple includes
;;; join as a disjunction, and excludes subtract as (includes)-(excludes). The law (tested):
;;; for compose-expressible expressions,  vcl->compose ∘ compose->vcl  is the identity on compose.

(require racket/contract racket/string racket/list racket/match
         json
         "parser/ast.rkt"
         (only-in "compile.rkt" vcl-print vcl->compose)
         (only-in "parser/parse.rkt" parse-vcl)
         (only-in fhir/result/result ok-value))

(provide (contract-out [compose->vcl (-> jsexpr? string?)]))

(define (compose->vcl compose)
  (define inc (disj (map include->ast (hash-ref compose 'include '()))))
  (define exc (let ([es (hash-ref compose 'exclude '())])
                (and (pair? es) (disj (map include->ast es)))))
  (vcl-print (if exc (vcl-excl inc exc) inc)))

(define (disj asts) (if (null? (cdr asts)) (car asts) (vcl-disj asts)))

;; one include/exclude entry -> its AST group
(define (include->ast e)
  (define sys (let ([s (hash-ref e 'system #f)])
                (and s (cons s (hash-ref e 'version #f)))))
  (define inner
    (cond
      [(pair? (hash-ref e 'concept '()))
       (disj (for/list ([c (in-list (hash-ref e 'concept))]) (vcl-code (hash-ref c 'code))))]
      [(pair? (hash-ref e 'filter '()))
       (let ([fs (map filter->ast (hash-ref e 'filter))])
         (if (null? (cdr fs)) (car fs) (vcl-conj fs)))]
      [(pair? (hash-ref e 'valueSet '()))
       (disj (for/list ([vs (in-list (hash-ref e 'valueSet))]) (vcl-include vs)))]
      [else (vcl-star)]))                       ; system-only include = the whole code system
  (if sys (vcl-sub sys inner) inner))

;; one compose filter -> vcl-filter / vcl-of, reconstructing the structured value forms
(define (filter->ast f)
  (define prop (hash-ref f 'property))
  (define op (string->symbol (hash-ref f 'op)))
  (define v (hash-ref f 'value ""))
  (cond
    [(eq? op 'of) (vcl-of (of-source v) prop)]
    [(and (memq op '(in not-in)) (uri? v)) (vcl-filter prop op v)]
    [(and (memq op '(in not-in)) (string-prefix? v "{"))       ; a nested filterList's VCL text
     (vcl-filter prop op (reparse-structured v))]
    [(memq op '(in not-in)) (vcl-filter prop op (vcl-code-list (string-split v ",")))]
    [else (vcl-filter prop op v)]))

(define (of-source v)
  (cond [(uri? v) v]
        [(string-prefix? v "{") (reparse-structured v)]
        [else (vcl-code v)]))
(define (uri? s) (regexp-match? #px"^[a-zA-Z]+:" s))

;; a structured value stored as VCL text ({...} filterList) parses back to its AST — by parsing
;; a minimal enclosing expression with the REAL grammar and extracting the value
(define (reparse-structured v)
  (match (ok-value (parse-vcl (string-append "x^" v)))
    [(vcl-filter _ 'in inner) inner]))

(module+ test
  (require rackunit)
  ;; the round-trip law: compose -> vcl -> compose is the identity
  (define (law s)
    (define c (ok-value (vcl->compose s)))
    (check-equal? (ok-value (vcl->compose (compose->vcl c))) c s))
  (for-each law
            '("(http://loinc.org)(a;b)"
              "(http://loinc.org)*"
              "(http://x.org|2.1)z"
              "(http://snomed.info/sct)concept<<17311000168105"
              "(http://loinc.org)(COMPONENT=LP212516-1,PROPERTY=LP6817-3)"
              "^http://hl7.org/fhir/ValueSet/payeetype"
              "((http://a)(x;y))-((http://a)z)"
              "(http://l)parent^{LP1,LP2}"
              "(http://a)x;(http://b)y"
              "(http://l)COMPONENT/\".*Dichloroethane.*\""
              "(http://l)ingredient?true")))
