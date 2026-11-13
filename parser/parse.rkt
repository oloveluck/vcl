#lang racket/base

;;; parse.rkt — string -> Result<VclExpr> (memoized, Result-not-exceptions — the cql pattern).

(require racket/contract
         (prefix-in g: "grammar.rkt")
         "lexer.rkt" "ast.rkt"
         (only-in fhir/result/result ok err ok? result?)
         (only-in fhir/result/result invalid-encoding)
         (only-in brag/support token srcloc-token? srcloc-token-token token-struct-type token-struct-val token-struct? token-struct-skip? token-struct-offset)
         (only-in fhir/diagnostic exn->diagnostic diagnostic->string attach-diagnostic! tokens->last-position error-position loc))

(provide (contract-out [parse-vcl (-> string? result?)]))

(define cache (make-hash))

(define (parse-vcl src)
  (hash-ref! cache src
             (lambda ()
               ;; the error message is the positioned one-liner; the diagnostic itself is attached
               ;; to the payload (attached-diagnostic) for machine-readable output
               (define last-pos #f) (define toks* '())
               (with-handlers ([exn:fail? (lambda (e)
                                            (define d (exn->diagnostic e 'vcl #:last-position last-pos #:unit "expression"
                                                                       #:ran-out? (ran-out-probe toks* last-pos)))
                                            (err (attach-diagnostic!
                                                  (invalid-encoding 'VCL "https://build.fhir.org/ig/FHIR/ig-guidance/vcl.html"
                                                                    (diagnostic->string d))
                                                  d)))])
                 (define toks (collect (tokenize (open-input-string src))))
                 (set! last-pos (tokens->last-position toks real-position)) (set! toks* toks)
                 (define-values (d locs)
                   (syntax->datum/locs (g:parse (let ([ts toks]) (lambda () (if (null? ts) (void) (begin0 (car ts) (set! ts (cdr ts)))))))))
                 (ok (lower d (lambda (node) (hash-ref locs node #f))))))))
;; syntax->datum/locs : syntax -> (values datum (hasheq datum-node -> loc))   brag's tree as the
;; datum `lower` reads, and where each simple term (a code, `*`, `^vs`, a filter) stood: the
;; compiler points there when a compose cannot hold the term (fml's parser does the same for rules)
(define (syntax->datum/locs stx)
  (define locs (make-hasheq))
  (define (walk s)
    (define l (syntax->list s))
    (cond [l (define d (map walk l))
             (when (and (pair? d) (eq? (car d) 'simpleExpr) (syntax-line s))
               (hash-set! locs d (loc #f (syntax-line s) (let ([c (syntax-column s)]) (and c (add1 c)))
                                      (syntax-position s) (syntax-span s))))
             d]
          [else (syntax-e s)]))
  (values (walk stx) locs))
;; probe-token : token|srcloc-token -> token-struct|#f   (skip tokens excluded)
(define (probe-token t)
  (define k (if (srcloc-token? t) (srcloc-token-token t) t))
  (and (token-struct? k) (not (token-struct-skip? k)) k))
;; ran-out-probe : tokens last-position -> (-> boolean)   re-parse with a sentinel token after the
;; last one: if the error moves to the sentinel, the input was a valid prefix that ran out
(define ((ran-out-probe toks last-pos) )
  ;; the sentinel is a COPY of the last real token (a type the grammar knows), placed after it
  (define last-real (for/last ([t (in-list toks)] #:when (probe-token t)) (probe-token t)))
  (and last-pos last-real
       (with-handlers ([exn:fail? (lambda (e) (let ([p (error-position e)]) (and p (> p last-pos))))])
         (g:parse-to-datum (let ([ts (append toks (list (token (token-struct-type last-real) (token-struct-val last-real)
                                                                #:position (+ last-pos 100000) #:line 1 #:column 0)))])
                             (lambda () (if (null? ts) (void) (begin0 (car ts) (set! ts (cdr ts)))))))
         #f)))
(define (collect next) (let loop ([acc '()]) (define t (next)) (if (void? t) (reverse acc) (loop (cons t acc)))))
(define (real-position t) (and (token-struct? t) (not (token-struct-skip? t)) (token-struct-offset t)))

(module+ test
  (require fhir/diagnostic (only-in fhir/result/result err-error))
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
  (check-false (ok? (parse-vcl "(((")))
  ;; diagnostics: the error payload carries one
  (define (diag s) (diagnostic->string (attached-diagnostic (err-error (parse-vcl s)))))
  (check-equal? (diag "(http://loinc.org)concept <<") "<input>:1:27: vcl parse error: the expression ends after `<<`")
  (check-equal? (diag "(http://loinc.org)concept << ,") "<input>:1:30: vcl parse error: unexpected comma `,`")
  ;; each simple term remembers where it stood (line, column, position, span), for the compiler
  (define (where node) (let ([l (attached-loc node)]) (and l (list (loc-line l) (loc-column l) (loc-position l) (loc-span l)))))
  (check-equal? (map where (vcl-disj-exprs (p "abc ; (http://loinc.org)d ; concept << B")))
                (list '(1 1 1 3) #f '(1 29 29 12)))                     ; the middle one is a (system) group…
  (check-equal? (where (vcl-sub-expr (cadr (vcl-disj-exprs (p "abc ; (http://loinc.org)d ; concept << B")))))
                '(1 25 25 1)))                                         ; …whose term is located
