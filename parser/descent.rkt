#lang racket/base

;;; descent.rkt — the VCL grammar (grammar.rkt) as a recursive-descent parser: tokens -> the tree
;;; brag would give, in time linear in the tokens, or #f.
;;;
;;; brag's parser is general (it reads any context-free grammar) and costs time quadratic in a
;;; flat list: a value set of 800 enumerated codes took 1.4 s to parse, of 4,000 about half a
;;; minute. VCL's grammar is decided by at most three tokens of lookahead, so it is read here
;;; directly, rule by rule. This parser only ever ACCEPTS: on any token it does not expect it
;;; answers #f, and parse.rkt hands the tokens to brag, whose error (the place, "the expression
;;; ends after …", "unexpected comma") is the diagnostic. So grammar.rkt stays the specification's
;;; port and the error reporter, and an accepted expression has the tree brag gives it, with the
;;; same places (tests/descent-test.rkt compares the two over the specification's examples and
;;; generated expressions).
;;;
;;; A Tree is brag's datum for the grammar: (vcl (expr …)), rule names as heads, tokens as their
;;; strings — the shape `lower` (ast.rkt) reads. A Locs is (hasheq Tree-node -> loc): where each
;;; `simpleExpr` node stood, as parse.rkt's `syntax->datum/locs` records it from brag's syntax.

(require racket/contract
         (only-in brag/support token-struct? token-struct-type token-struct-val
                  token-struct-line token-struct-column token-struct-offset token-struct-span)
         (only-in fhir/diagnostic loc))

(provide (contract-out [descend (-> (listof token-struct?) (or/c (cons/c pair? hash?) #f))]))

;; the filter operators, by token type, and what each takes as its value
(define code-operators '(EQ IS-A IS-NOT-A DESC-OF GENERALIZES CHILD-OF DESC-LEAF EXISTS))
(define list-operators '(CARET NOT-IN))

;; descend : (listof Token) -> (cons Tree Locs) | #f
(define (descend tokens)
  (define toks (list->vector tokens))
  (define n (vector-length toks))
  (define locs (make-hasheq))
  (let/ec fail
    ;; the reader's state: the index of the next token
    (define i 0)
    (define (type-at k) (and (< k n) (token-struct-type (vector-ref toks k))))
    (define (peek [ahead 0]) (type-at (+ i ahead)))
    ;; take : symbol -> string   the next token, which must be of this type; its text
    (define (take type)
      (unless (eq? (peek) type) (fail #f))
      (begin0 (token-struct-val (vector-ref toks i)) (set! i (add1 i))))

    ;; vcl : expr EOF
    (define (vcl)
      (define e (expr))
      (unless (= i n) (fail #f))
      (list 'vcl e))
    ;; expr : subExpr [tail]
    (define (expr)
      (define head (sub-expr))
      (case (peek)
        [(COMMA) (list 'expr head (list 'tail (cons 'conjunction (repeated 'COMMA))))]
        [(SEMI) (list 'expr head (list 'tail (cons 'disjunction (repeated 'SEMI))))]
        [(DASH) (define d (take 'DASH)) (list 'expr head (list 'tail (list 'exclusion d (sub-expr))))]
        [else (list 'expr head)]))
    ;; repeated : symbol -> (listof string|Tree)   (SEP subExpr)+, flattened as brag gives it
    (define (repeated sep)
      (let loop ([acc '()])
        (if (eq? (peek) sep)
            (let* ([s (take sep)] [e (sub-expr)]) (loop (list* e s acc)))
            (reverse acc))))
    ;; subExpr : [systemUri] (simpleExpr | OPEN expr CLOSE)
    (define (sub-expr)
      (define system (and (system-uri-ahead?) (system-uri)))
      (define body
        (if (eq? (peek) 'OPEN)
            (let* ([o (take 'OPEN)] [e (expr)] [c (take 'CLOSE)]) (list o e c))
            (list (simple-expr))))
      (cons 'subExpr (if system (cons system body) body)))
    (define (system-uri-ahead?) (and (eq? (peek) 'OPEN) (eq? (peek 1) 'URI) (eq? (peek 2) 'CLOSE)))
    ;; systemUri : OPEN URI CLOSE
    (define (system-uri)
      (let* ([o (take 'OPEN)] [u (take 'URI)] [c (take 'CLOSE)]) (list 'systemUri o u c)))
    ;; simpleExpr : STAR | code | filter | includeVs   — located, as brag's syntax says
    (define (simple-expr)
      (define start i)
      (define node
        (cons 'simpleExpr
              (case (peek)
                [(STAR) (if (eq? (peek 1) 'DOT) (list (filter)) (list (take 'STAR)))]
                [(SCODE QUOTED) (if (or (memq (peek 1) code-operators) (memq (peek 1) list-operators)
                                        (memq (peek 1) '(REGEX DOT)))
                                    (list (filter))
                                    (list (code)))]
                [(CARET) (list (include-vs))]
                [(URI LCRLY) (list (filter))]
                [else (fail #f)])))
      (hash-set! locs node (span-loc start i))
      node)
    ;; includeVs : CARET (URI | systemUri)
    (define (include-vs)
      (define c (take 'CARET))
      (list 'includeVs c (if (eq? (peek) 'URI) (take 'URI) (system-uri))))
    ;; filter : property op value | (code | codeList | STAR | URI | filterList) DOT property
    (define (filter)
      (case (peek)
        [(SCODE QUOTED)
         (define t (peek 1))
         (cond [(eq? t 'DOT) (of-filter (code))]
               [(not (or (memq t code-operators) (memq t list-operators) (eq? t 'REGEX))) (fail #f)]
               [else
                (define p (list 'property (code)))
                (define op (take t))
                (list 'filter p op
                      (cond [(memq t code-operators) (code)]
                            [(eq? t 'REGEX) (list 'str (take 'QUOTED))]
                            [else (list-value)]))])]
        [(STAR) (of-filter (take 'STAR))]
        [(URI) (of-filter (take 'URI))]
        [(LCRLY) (of-filter (brace-list))]
        [else (fail #f)]))
    ;; of-filter : (string|Tree) -> Tree   source DOT property
    (define (of-filter source)
      (define d (take 'DOT))
      (list 'filter source d (list 'property (code))))
    ;; the value of `^` and `~^`: codeList | URI | filterList
    (define (list-value)
      (case (peek)
        [(URI) (take 'URI)]
        [(LCRLY) (brace-list)]
        [else (fail #f)]))
    ;; brace-list : -> Tree   a codeList (codes) or a filterList (filters), told by its first item:
    ;; a code followed by `,` or `}` is a code list's
    (define (brace-list)
      (define open (take 'LCRLY))
      (define codes? (and (memq (peek) '(SCODE QUOTED)) (memq (peek 1) '(COMMA RCRLY))))
      (define item (if codes? code filter))
      (let loop ([acc (list (item) open)])
        (case (peek)
          [(COMMA) (let* ([c (take 'COMMA)] [x (item)]) (loop (list* x c acc)))]
          [(RCRLY) (cons (if codes? 'codeList 'filterList) (reverse (cons (take 'RCRLY) acc)))]
          [else (fail #f)])))
    ;; code : SCODE | QUOTED
    (define (code)
      (case (peek)
        [(SCODE) (list 'code (take 'SCODE))]
        [(QUOTED) (list 'code (take 'QUOTED))]
        [else (fail #f)]))
    ;; span-loc : index index -> loc   from the first token's start to the last one's end
    (define (span-loc from to)
      (define first (vector-ref toks from))
      (define last (vector-ref toks (sub1 to)))
      (loc #f (token-struct-line first) (add1 (token-struct-column first)) (token-struct-offset first)
           (- (+ (token-struct-offset last) (token-struct-span last)) (token-struct-offset first))))

    (if (zero? n) #f (cons (vcl) locs))))

(module+ test
  (require rackunit (only-in "lexer.rkt" tokenize))
  (define (tree s) (let ([r (descend (tokenize s))]) (and r (car r))))
  (check-equal? (tree "(http://l)(a;b)")
                '(vcl (expr (subExpr (systemUri "(" "http://l" ")") "("
                                     (expr (subExpr (simpleExpr (code "a"))) (tail (disjunction ";" (subExpr (simpleExpr (code "b"))))))
                                     ")"))))
  (check-equal? (tree "p^{q=1,r<<2}")
                '(vcl (expr (subExpr (simpleExpr (filter (property (code "p")) "^"
                                                         (filterList "{" (filter (property (code "q")) "=" (code "1")) ","
                                                                     (filter (property (code "r")) "<<" (code "2")) "}")))))))
  (check-equal? (tree "{a}.c") '(vcl (expr (subExpr (simpleExpr (filter (codeList "{" (code "a") "}") "." (property (code "c"))))))))
  ;; what is not VCL is not accepted here (brag says why)
  (for ([s (in-list '("a;b,c" "(http://l" "p=" "p/x" "{a,b=1}.c" "http://x" "a b" "(a))" "{}"))])
    (check-false (tree s) s))
  ;; a long list is read in linear time
  (define long (string-append "(http://l)(" (apply string-append (for/list ([k 20000]) (format "c~a;" k))) "z)"))
  (define t0 (current-inexact-milliseconds))
  (check-true (pair? (tree long)))
  (check-true (< (- (current-inexact-milliseconds) t0) 2000)))
