#lang racket/base

;;; decompile.rkt — ValueSet.compose (jsexpr) -> VCL text (the GoFSH direction).
;;;
;;; Inverse of compile.rkt's mapping: each include entry becomes a (system)-prefixed group —
;;; concepts as a disjunction; its filters and value sets (`^uri`), which all hold together, as a
;;; conjunction — multiple includes join as a disjunction, and excludes subtract as
;;; (includes)-(excludes). The law (tested): for compose-expressible expressions,
;;; vcl->compose ∘ compose->vcl  is the identity on compose. An include that lists concepts keeps
;;; them alone (VCL cannot AND a list of codes with anything: its filters and value sets are lost).

(require racket/contract racket/string racket/list racket/match
         json
         "parser/ast.rkt"
         "print.rkt"
         (only-in "compile.rkt" vcl->compose)
         (only-in "parser/parse.rkt" parse-vcl)
         (only-in fhir/result/result ok? ok-value err-error validation-error-message))

(provide (contract-out [compose->vcl (-> jsexpr? string?)]))

;; compose->vcl : compose -> string
(define (compose->vcl compose)
  (define includes (hash-ref compose 'include '()))
  (when (null? includes) (raise-argument-error 'compose->vcl "a compose with at least one include" compose))
  (define inc (disj (map include->ast includes)))
  (define exc (let ([es (hash-ref compose 'exclude '())])
                (and (pair? es) (disj (map include->ast es)))))
  (vcl-print (if exc (vcl-excl inc exc) inc)))

(define (disj asts) (if (null? (cdr asts)) (car asts) (vcl-disj asts)))
(define (conj asts) (if (null? (cdr asts)) (car asts) (vcl-conj asts)))

;; one include/exclude entry -> its AST group
(define (include->ast e)
  (define sys (let ([s (hash-ref e 'system #f)])
                (and s (cons s (hash-ref e 'version #f)))))
  (define rules (append (map filter->ast (hash-ref e 'filter '()))
                        (map vcl-include (hash-ref e 'valueSet '()))))
  (define inner
    (cond
      [(pair? (hash-ref e 'concept '()))
       (disj (for/list ([c (in-list (hash-ref e 'concept))]) (vcl-code (hash-ref c 'code))))]
      [(pair? rules) (conj rules)]               ; filters and value sets all hold (an AND)
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
  (define r (parse-vcl (string-append "x^" v)))
  (unless (ok? r)
    (error 'compose->vcl "a filter's value ~s is not a VCL list: ~a" v (validation-error-message (err-error r))))
  (match (ok-value r)
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
              "(http://l)ingredient?true"
              ;; a URI that something follows, and value sets in one include (2026-11-13)
              "^http://a/vs ; (http://loinc.org)x" "^http://a/vs , ^http://b/vs"
              "(http://a)(p=x, ^http://v/a)" "(http://a){p^http://vs }.q" "(http://a)http://x .p"
              "(http://a)p^{q^http://x/vs }"))
  ;; composes not written by the compiler
  (define (again c) (ok-value (vcl->compose (compose->vcl c))))
  ;; an include's value sets hold together (R5 on: intersection): `^a;^b` read back as ONE value set
  ;; whose url was "http://a/vs;^http://b/vs"
  (define two-vs (hasheq 'include (list (hasheq 'valueSet '("http://a/vs" "http://b/vs")))))
  (check-equal? (compose->vcl two-vs) "^http://a/vs ,^http://b/vs")
  (check-equal? (again two-vs) two-vs)
  ;; filters and value sets of one include are kept together (the value sets were dropped)
  (define both (hasheq 'include (list (hasheq 'system "http://s" 'filter (list (hasheq 'property "p" 'op "=" 'value "x"))
                                              'valueSet '("http://a/vs")))))
  (check-equal? (again both) both)
  ;; a value written as a URI after `=` is a code: quoted (it printed bare and did not parse)
  (define uri-code (hasheq 'include (list (hasheq 'system "http://s" 'filter (list (hasheq 'property "p" 'op "=" 'value "http://x/y"))))))
  (check-equal? (again uri-code) uri-code)
  ;; an `of` over a value set, and a nested list holding one, read back (they did not parse)
  (for ([v (in-list '("http://x/vs" "{q^http://x/vs }"))])
    (define c (hasheq 'include (list (hasheq 'system "http://s" 'filter (list (hasheq 'property "p" 'op "of" 'value v))))))
    (check-equal? (again c) c v))
  ;; a nested list that is not VCL is said (it was `ok-value: contract violation`)
  (check-exn #rx"compose->vcl: a filter's value \"[{]q\\^http://x/vs[}]\" is not a VCL list"
             (lambda () (compose->vcl (hasheq 'include (list (hasheq 'system "http://s" 'filter (list (hasheq 'property "p" 'op "in" 'value "{q^http://x/vs}"))))))))
  ;; a compose without an include is said (it was `cdr: contract violation`)
  (check-exn #rx"compose->vcl: contract violation\n  expected: a compose with at least one include"
             (lambda () (compose->vcl (hasheq 'include '())))))
