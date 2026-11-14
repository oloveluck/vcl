#lang racket/base

;;; parse.rkt — string -> Result<VclExpr> (memoized, Result-not-exceptions — the cql pattern).
;;;
;;; text -> tokens (lexer.rkt) -> tree -> AST (ast.rkt's `lower`). The tree comes from the
;;; recursive-descent reading of the grammar (descent.rkt: linear time); when it does not accept the
;;; tokens, from brag's parser of grammar.rkt, whose error is the diagnostic. A lex error, a parse
;;; error and an empty text are an `err` carrying an invalid-encoding payload with the positioned
;;; diagnostic attached (fhir/diagnostic `attached-diagnostic`).

(require racket/contract
         (prefix-in g: "grammar.rkt")
         "lexer.rkt" "ast.rkt" "descent.rkt"
         (only-in fhir/result/result ok err result?)
         (only-in fhir/result/result invalid-encoding)
         (only-in brag/support token token-struct-type token-struct-val token-struct-offset)
         (only-in fhir/diagnostic diagnostic exn->diagnostic diagnostic->string attach-diagnostic!
                  tokens->last-position error-position loc))

(provide (contract-out [parse-vcl (-> string? result?)]))

(define spec-url "https://build.fhir.org/ig/FHIR/ig-guidance/vcl.html")

;; the memo: text -> Result. A language server parses at every keystroke and the terminology
;; service compiles every implicit VCL url it meets, so it is BOUNDED: emptied at its limit
(define cache (make-hash))
(define cache-limit 4096)

;; parse-vcl : string -> Result<VclExpr>
(define (parse-vcl src)
  (hash-ref cache src
            (lambda ()
              (define r (parse-text src))
              (when (>= (hash-count cache) cache-limit) (hash-clear! cache))
              (hash-set! cache src r)
              r)))

;; parse-text : string -> Result<VclExpr>
(define (parse-text src)
  (with-handlers ([exn:fail? (lambda (e) (failure (exn->diagnostic e 'vcl)))])
    (define toks (tokenize src))
    (cond
      [(null? toks) (failure (diagnostic 'vcl 'parse 'error "the expression is empty" #f))]
      [(descend toks) => (lambda (tree+locs) (ok (lower (car tree+locs) (located-in (cdr tree+locs)))))]
      [else (brag-parse toks)])))

;; brag-parse : (listof Token) -> Result<VclExpr>   the grammar's own parse: its tree, or its error
;; worded (fhir/diagnostic): "the expression ends after `<<`" when the input ran out, else
;; "unexpected comma `,`", at the token
(define (brag-parse toks)
  (define last-pos (tokens->last-position toks token-struct-offset))
  (with-handlers ([exn:fail? (lambda (e)
                               (failure (exn->diagnostic e 'vcl #:last-position last-pos #:unit "expression"
                                                         #:ran-out? (ran-out-probe toks last-pos))))])
    (define-values (d locs) (syntax->datum/locs (g:parse (token-thunk toks))))
    (ok (lower d (located-in locs)))))

;; failure : diagnostic -> err   the error payload, its message the positioned one-liner
(define (failure d)
  (err (attach-diagnostic! (invalid-encoding 'VCL spec-url (diagnostic->string d)) d)))
(define ((located-in locs) node) (hash-ref locs node #f))
;; token-thunk : (listof Token) -> (-> Token|void)   the tokens, one a call, as brag reads them
(define (token-thunk toks)
  (lambda () (if (null? toks) (void) (begin0 (car toks) (set! toks (cdr toks))))))

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

;; ran-out-probe : tokens last-position -> (-> boolean)   re-parse with a sentinel token after the
;; last one: if the error moves to the sentinel, the input was a valid prefix that ran out
(define ((ran-out-probe toks last-pos))
  ;; the sentinel is a COPY of the last token (a type the grammar knows), placed after it
  (define last-tok (car (reverse toks)))
  (and last-pos
       (with-handlers ([exn:fail? (lambda (e) (let ([p (error-position e)]) (and p (> p last-pos))))])
         (g:parse-to-datum (token-thunk (append toks (list (token (token-struct-type last-tok) (token-struct-val last-tok)
                                                                  #:position (+ last-pos 100000) #:line 1 #:column 0)))))
         #f)))

(module+ test
  (require fhir/diagnostic (only-in fhir/result/result err-error ok? ok-value))
  (require rackunit (only-in racket/string string-join))
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
  ;; no expression at all (brag's words for it were "unexpected no-tokens `#f`", as fhirpath's were)
  (check-equal? (diag "") "vcl parse error: the expression is empty")
  (check-equal? (diag " \t ") "vcl parse error: the expression is empty")
  ;; each simple term remembers where it stood (line, column, position, span), for the compiler
  (define (where node) (let ([l (attached-loc node)]) (and l (list (loc-line l) (loc-column l) (loc-position l) (loc-span l)))))
  (check-equal? (map where (vcl-disj-exprs (p "abc ; (http://loinc.org)d ; concept << B")))
                (list '(1 1 1 3) #f '(1 29 29 12)))                     ; the middle one is a (system) group…
  (check-equal? (where (vcl-sub-expr (cadr (vcl-disj-exprs (p "abc ; (http://loinc.org)d ; concept << B")))))
                '(1 25 25 1))                                          ; …whose term is located
  ;; a value set of several thousand enumerated codes parses in well under a second (brag alone:
  ;; 1.4 s for 800, quadratic)
  (define codes (for/list ([k 5000]) (format "~a-~a" (+ 10000 k) (modulo k 10))))
  (define big (string-append "(http://loinc.org)(" (string-join codes ";") ")"))
  (define t0 (current-inexact-milliseconds))
  (check-equal? (length (vcl-disj-exprs (vcl-sub-expr (p big)))) 5000)
  (check-true (< (- (current-inexact-milliseconds) t0) 1000)))

;; brag's own tree and places, for tests/descent-test.rkt (which holds descent.rkt to it)
(module+ grammar-tree
  (provide brag-tree)
  ;; brag-tree : (listof Token) -> (cons Tree Locs)   raises when the grammar does not accept them
  (define (brag-tree toks)
    (define-values (d locs) (syntax->datum/locs (g:parse (token-thunk toks))))
    (cons d locs)))
