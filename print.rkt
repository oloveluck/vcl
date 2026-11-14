#lang racket/base

;;; print.rkt — VclExpr -> VCL text: the canonical form, which parses back to the same expression.
;;;
;;; Two things of the grammar decide the form:
;;;   * `,` and `;` have no precedence (the specification: "there are no operator precedence rules
;;;     for comma and semicolon"), so a member of a conjunction or a disjunction that is itself
;;;     compound is bracketed;
;;;   * a URI takes every character of its set — `;`, `}`, `.`, `-` among them — up to a space or a
;;;     bracket, and after a `|` (a version) everything up to a bracket or a `|`. So a URI that
;;;     something follows ends with a space (`^http://x/vs ;(http://loinc.org)a`, `{p^http://x/vs }`,
;;;     `http://x/vs .p`), and a value set with a version is written in round brackets, the
;;;     grammar's other form for it (`^(http://x/vs|1.0)`). Printed without them, those parsed back
;;;     as one long URI, or not at all.
;;; A value that looks like a URI is a URI only after `^`/`~^`; after another operator it is a code,
;;; quoted (`p="http://x/y"`), as a decompiled compose can hold one.

(require racket/contract racket/string racket/match
         "parser/ast.rkt")

(provide (contract-out [vcl-print (-> any/c string?)]))

;; vcl-print : VclExpr -> string
(define (vcl-print a)
  (match a
    [(vcl-sub (cons u v) inner)
     (format "(~a~a)~a" u (if v (string-append "|" v) "") (member-text inner))]
    [(vcl-conj es) (members es ",")]
    [(vcl-disj es) (members es ";")]
    [(vcl-excl b r) (format "(~a)-(~a)" (vcl-print b) (vcl-print r))]
    [(vcl-code c) (print-code c)]
    [(vcl-star) "*"]
    [(vcl-include t) (if (string-contains? t "|") (format "^(~a)" t) (string-append "^" t))]
    [(vcl-filter prop op v)
     (string-append (print-code prop) (operator-lexeme op) (print-value op v))]
    [(vcl-of source prop) (string-append (followed source (print-of-source source)) "." (print-code prop))]
    [(vcl-code-list codes) (format "{~a}" (string-join (map print-code codes) ","))]
    [(vcl-filter-list fs)                                     ; `}` follows the last filter too
     (format "{~a}" (string-join (for/list ([f (in-list fs)]) (followed f (vcl-print f))) ","))]))

;; members : (listof VclExpr) string -> string   joined by the separator; each but the last is
;; followed by it, the last by what follows the whole (its own `followed` decides there)
(define (members es sep)
  (define last-i (sub1 (length es)))
  (string-join (for/list ([e (in-list es)] [i (in-naturals)])
                 (if (= i last-i) (member-text e) (followed e (member-text e))))
               sep))

;; member-text : VclExpr -> string   a compound expression in brackets, else its own text
(define (member-text e) (if (compound? e) (format "(~a)" (vcl-print e)) (vcl-print e)))
(define (compound? e) (or (vcl-conj? e) (vcl-disj? e) (vcl-excl? e)))

;; followed : VclExpr string -> string   the text, with a space when it ends in a URI
(define (followed e text) (if (ends-in-uri? e) (string-append text " ") text))

;; ends-in-uri? : VclExpr|string -> boolean   whether the printed text ends with a URI token
(define (ends-in-uri? e)
  (match e
    [(? string?) (uri? e)]                                    ; an `of` source
    [(vcl-include t) (not (string-contains? t "|"))]          ; `^(t)` ends with a bracket
    [(vcl-filter _ (or 'in 'not-in) (? string? v)) (uri? v)]
    [(vcl-sub _ inner) (and (not (compound? inner)) (ends-in-uri? inner))]
    [(or (vcl-conj es) (vcl-disj es))
     (define last (car (reverse es)))
     (and (not (compound? last)) (ends-in-uri? last))]
    [_ #f]))

(define (print-value op v)
  (match v
    [(? string? s) (cond [(eq? op 'regex) (quote-str s)]
                         [(and (memq op '(in not-in)) (uri? s)) s]
                         [else (print-code s)])]
    [_ (vcl-print v)]))
(define (print-of-source s)
  (match s [(? string?) s] [(vcl-code c) (print-code c)] [_ (vcl-print s)]))
(define (uri? s) (regexp-match? #px"^[a-zA-Z]+:" s))
;; a code prints bare when it is a simple SCODE, quoted otherwise
(define (print-code c)
  (if (regexp-match? #px"^[a-zA-Z0-9][-_a-zA-Z0-9]*$" c) c (quote-str c)))
(define (quote-str s)
  (format "\"~a\"" (string-replace (string-replace s "\\" "\\\\") "\"" "\\\"")))

(module+ test
  (require rackunit (only-in "parser/parse.rkt" parse-vcl) (only-in fhir/result/result ok? ok-value))
  ;; print∘parse is the identity on the expression, the URI cases included
  (define (fix s)
    (define a (ok-value (parse-vcl s)))
    (define r (parse-vcl (vcl-print a)))
    (check-true (ok? r) (format "~a printed as ~a, which does not parse" s (vcl-print a)))
    (when (ok? r) (check-equal? (ok-value r) a s)))
  (for-each fix '("(http://loinc.org)(a;b)" "concept<<B" "parent^{LP1,LP2}"
                  "(a;b)-(c)" "^http://x.org/vs" "has_ingredient^{has_tradename=2201670}"
                  "{concept<B}.codeprop" "ingredient?true" "(http://x.org|2.1)z"
                  ;; each printed as one long URI, or unparseable, before (2026-11-13)
                  "^http://x.org/vs ; (http://loinc.org)a" "^http://a/vs , ^http://b/vs"
                  "(http://a){p^http://vs }.q" "(http://a)http://x .prop" "{a^http://vs ,b=c}.d"
                  "^(http://x.org/vs|1.0) ; (http://a)b" "(http://a)p~^http://vs ;q=1"))
  (check-equal? (vcl-print (ok-value (parse-vcl "^http://x.org/vs ; (http://loinc.org)a")))
                "^http://x.org/vs ;(http://loinc.org)a")
  (check-equal? (vcl-print (ok-value (parse-vcl "^(http://x.org/vs|1.0)"))) "^(http://x.org/vs|1.0)")
  ;; a value that looks like a URI is a code after `=`: quoted, so it reads back as one
  (check-equal? (vcl-print (vcl-filter "p" '= "http://x/y")) "p=\"http://x/y\"")
  (check-equal? (ok-value (parse-vcl "p=\"http://x/y\"")) (vcl-filter "p" '= "http://x/y")))
