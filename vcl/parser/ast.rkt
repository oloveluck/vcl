#lang racket/base

;;; ast.rkt — the VCL AST (prefab, HTDP data definitions) + `lower` from brag's datum tree.
;;;
;;; A VclExpr is one of:
;;;   (vcl-sub system expr)      system : (cons uri version|#f) | #f — a (system) prefix scope
;;;   (vcl-conj (listof expr))   comma  — AND
;;;   (vcl-disj (listof expr))   semi   — OR
;;;   (vcl-excl base removed)    dash   — base minus removed
;;;   (vcl-code c)               a single code
;;;   (vcl-star)                 all codes
;;;   (vcl-include target)       ^vs    — target : uri string (may carry |version)
;;;   (vcl-filter prop op value) op : '= 'is-a 'is-not-a 'descendent-of 'regex 'in 'not-in
;;;                                   'generalizes 'child-of 'descendent-leaf 'exists
;;;                              value : string (code/regex/uri) | vcl-code-list | vcl-filter-list
;;;   (vcl-of source prop)       R6 "of": source . prop — source : vcl-code | vcl-code-list |
;;;                              vcl-star | uri-string | vcl-filter-list
;;; A VclCodeList is (vcl-code-list (listof string)); a VclFilterList is
;;; (vcl-filter-list (listof vcl-filter|vcl-of)).

(require racket/contract racket/list racket/match)

(provide (struct-out vcl-sub) (struct-out vcl-conj) (struct-out vcl-disj) (struct-out vcl-excl)
         (struct-out vcl-code) (struct-out vcl-star) (struct-out vcl-include)
         (struct-out vcl-filter) (struct-out vcl-of)
         (struct-out vcl-code-list) (struct-out vcl-filter-list)
         (contract-out [lower (-> any/c any/c)]))

(struct vcl-sub (system expr) #:prefab)
(struct vcl-conj (exprs) #:prefab)
(struct vcl-disj (exprs) #:prefab)
(struct vcl-excl (base removed) #:prefab)
(struct vcl-code (c) #:prefab)
(struct vcl-star () #:prefab)
(struct vcl-include (target) #:prefab)
(struct vcl-filter (prop op value) #:prefab)
(struct vcl-of (source prop) #:prefab)
(struct vcl-code-list (codes) #:prefab)
(struct vcl-filter-list (filters) #:prefab)

;; the g4 operator token -> the FHIR filter-operator symbol
(define op-of
  (hash 'EQ '= 'IS-A 'is-a 'IS-NOT-A 'is-not-a 'DESC-OF 'descendent-of 'REGEX 'regex
        'CARET 'in 'NOT-IN 'not-in 'GENERALIZES 'generalizes 'CHILD-OF 'child-of
        'DESC-LEAF 'descendent-leaf 'EXISTS 'exists))

;; ---- lower : brag datum -> AST (structural recursion over the rule tree) ----
(define (lower d)
  (match d
    [(list 'vcl e) (lower e)]
    [(list 'expr sub) (lower sub)]
    [(list 'expr sub (list 'tail t)) (attach (lower sub) t)]
    [(list 'subExpr inner) (lower inner)]
    [(list 'subExpr (and su (list 'systemUri _ ...)) inner)
     (vcl-sub (lower-system su) (lower inner))]
    ;; grouped: (subExpr [systemUri] OPEN expr CLOSE) — brag keeps the token strings
    [(list 'subExpr "(" e ")") (lower e)]
    [(list 'subExpr (and su (list 'systemUri _ ...)) "(" e ")")
     (vcl-sub (lower-system su) (lower e))]
    [(list 'simpleExpr "*") (vcl-star)]
    [(list 'simpleExpr (and c (list 'code _))) (vcl-code (code-str c))]
    [(list 'simpleExpr inner) (lower inner)]
    [(list 'includeVs "^" (? string? uri)) (vcl-include uri)]
    [(list 'includeVs "^" (list 'systemUri "(" uri ")")) (vcl-include uri)]
    [(cons 'filter parts) (lower-filter parts)]
    [(cons 'filterList parts)
     (vcl-filter-list (for/list ([p (in-list parts)] #:when (filter-node? p)) (lower p)))]
    [(cons 'codeList parts)
     (vcl-code-list (for/list ([p (in-list parts)] #:when (code-node? p)) (code-str p)))]
    [_ (error 'vcl "cannot lower: ~s" d)]))

;; a conjunction/disjunction/exclusion tail attaches its subExprs to the head
(define (attach head t)
  (match t
    [(cons 'conjunction parts) (vcl-conj (cons head (subexprs parts)))]
    [(cons 'disjunction parts) (vcl-disj (cons head (subexprs parts)))]
    [(list 'exclusion "-" sub) (vcl-excl head (lower sub))]))
(define (subexprs parts)
  (for/list ([p (in-list parts)] #:when (and (pair? p) (eq? (car p) 'subExpr))) (lower p)))

(define (lower-system su)
  (match su
    [(list 'systemUri "(" uri ")")
     (match (regexp-match #px"^([^|]*)(?:\\|(.*))?$" uri)
       [(list _ u v) (cons u v)])]))

;; filter rule parts: prop-op-value, or the reversed "of" form (source DOT property)
(define (lower-filter parts)
  (match parts
    [(list src "." (and p (list 'property _)))
     (vcl-of (lower-of-source src) (prop-str p))]
    [(list-rest (and p (list 'property _)) (? string? op-lexeme) vals)
     (define op (hash-ref op-of (lexeme->token op-lexeme)))
     (vcl-filter (prop-str p) op (lower-value (car vals)))]
    [_ (error 'vcl "cannot lower filter: ~s" parts)]))

;; brag hands operator tokens back as their lexeme strings — recover the token identity
(define (lexeme->token s)
  (match s ["=" 'EQ] ["<<" 'IS-A] ["~<<" 'IS-NOT-A] ["<" 'DESC-OF] ["/" 'REGEX] ["^" 'CARET]
           ["~^" 'NOT-IN] [">>" 'GENERALIZES] ["<!" 'CHILD-OF] ["!!<" 'DESC-LEAF] ["?" 'EXISTS]))

(define (lower-value v)
  (match v
    [(? string?) v]                                       ; a URI token
    [(list 'code _) (code-str v)]
    [(list 'str s) s]
    [(cons 'codeList _) (lower v)]
    [(cons 'filterList _) (lower v)]))

(define (lower-of-source src)
  (match src
    [(? string? s) (if (equal? s "*") (vcl-star) s)]      ; URI, or the STAR lexeme
    [(list 'code _) (vcl-code (code-str src))]
    [(cons 'codeList _) (lower src)]
    [(cons 'filterList _) (lower src)]))

(define (code-str c) (match c [(list 'code s) s]))
(define (prop-str p) (match p [(list 'property c) (code-str c)]))
(define (filter-node? p) (and (pair? p) (eq? (car p) 'filter)))
(define (code-node? p) (and (pair? p) (eq? (car p) 'code)))
