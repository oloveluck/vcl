#lang racket/base

;;; descent-test.rkt — the recursive-descent parser (parser/descent.rkt) is brag's parse of the
;;; grammar (parser/grammar.rkt), only faster: wherever it accepts, the tree and the place of every
;;; term are brag's; it accepts everything brag accepts among the specification's examples and
;;; the generated expressions below, and nothing brag refuses.

(require rackunit racket/runtime-path racket/file racket/string racket/list
         (only-in "../parser/lexer.rkt" tokenize)
         (only-in "../parser/descent.rkt" descend)
         (submod "../parser/parse.rkt" grammar-tree))

(define-runtime-path examples "vendor/examples.txt")
(define (normalize s) (string-replace (string-replace s "“" "\"") "”" "\""))
(define corpus (for/list ([l (in-list (file->lines examples))] #:unless (string=? (string-trim l) "")) (normalize l)))

;; places : Tree Locs -> (listof (cons node loc))   every located node, in the tree's order
(define (places tree locs)
  (let walk ([t tree])
    (if (pair? t)
        (append (let ([l (hash-ref locs t #f)]) (if l (list (cons t l)) '())) (append-map walk t))
        '())))

;; agree : string -> (or/c 'both 'neither)   fails the check when the two parsers differ
(define (agree s)
  (define toks (with-handlers ([exn:fail? (lambda (e) #f)]) (tokenize s)))
  (cond
    [(not toks) 'neither]
    [else
     (define fast (descend toks))
     (define slow (with-handlers ([exn:fail? (lambda (e) #f)]) (brag-tree toks)))
     (cond [(and fast slow)
            (check-equal? (car fast) (car slow) s)
            (check-equal? (places (car fast) (cdr fast)) (places (car slow) (cdr slow)) s)
            'both]
           [else (check-false (or fast slow) (format "~a: descent ~a, brag ~a" s (and fast #t) (and slow #t)))
                 'neither])]))

(test-case "the specification's examples: the same tree, the same places"
  (for ([e (in-list corpus)]) (check-equal? (agree e) 'both e)))

;; gen : random depth -> string   an expression over every form of the grammar, sometimes broken
(define (gen r depth)
  (define (pick . xs) (list-ref xs (random (length xs) r)))
  (define (code) (pick "a" "B" "10007-3" "\"B.1\"" "\"x y\"" "true"))
  (define (uri) (pick "http://x.org/cs" "http://x.org|1.0" "urn:oid:1.2"))
  (define (op) (pick "=" "<<" "~<<" "<" ">>" "<!" "!!<" "?"))
  (define (flist d) (string-append "{" (string-join (for/list ([k (add1 (random 3 r))]) (filt d)) ",") "}"))
  (define (clist) (string-append "{" (string-join (for/list ([k (add1 (random 3 r))]) (code)) ",") "}"))
  (define (filt d)
    (case (random (if (> d 0) 7 5) r)
      [(0 1) (string-append (code) (op) (code))]
      [(2) (string-append (code) "/\"a.*\"")]
      [(3) (string-append (code) (pick "^" "~^") (pick (clist) (string-append (uri) " ")))]
      [(4) (string-append (pick (code) "*" (clist) (string-append (uri) " ")) "." (code))]
      [else (string-append (code) (pick "^" "~^") (flist (sub1 d)))]))
  (define (simple d) (pick (code) "*" (filt d) (string-append "^" (uri) " ") (string-append "^(" (uri) ")")))
  (define (sub d)
    (string-append (if (zero? (random 3 r)) (string-append "(" (uri) ")") "")
                   (if (and (> d 0) (zero? (random 3 r))) (string-append "(" (expr (sub1 d)) ")") (simple d))))
  (define (expr d)
    (define head (sub d))
    (case (random 4 r)
      [(0) head]
      [(1) (string-join (cons head (for/list ([k (add1 (random 3 r))]) (sub d))) " , ")]
      [(2) (string-join (cons head (for/list ([k (add1 (random 3 r))]) (sub d))) " ; ")]
      [else (string-append head " - " (sub d))]))
  (define e (expr depth))
  ;; one in four is broken: a token dropped, doubled or swapped
  (if (zero? (random 4 r))
      (let* ([k (random (max 1 (string-length e)) r)] [cut (min (string-length e) (+ k 1 (random 3 r)))])
        (pick (string-append (substring e 0 k) (substring e cut))
              (string-append (substring e 0 k) (pick ";" "," ")" "(" "{" "}" "." "-" "^") (substring e k))))
      e))

(test-case "generated expressions: descent accepts what brag accepts, with brag's tree"
  (define r (make-pseudo-random-generator))
  (parameterize ([current-pseudo-random-generator r]) (random-seed 20261113))
  (define outcomes (for/list ([k 1500]) (agree (gen r (random 3 r)))))
  ;; both kinds were met, in numbers
  (check-true (> (count (lambda (o) (eq? o 'both)) outcomes) 600))
  (check-true (> (count (lambda (o) (eq? o 'neither)) outcomes) 100)))
