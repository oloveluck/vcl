#lang racket/base

;;; text.rkt — a `.vcl` file's text: the one expression it holds, and a problem found in the
;;; expression moved to its place in the file.
;;;
;;; A file holds one expression, perhaps after a `#lang vcl` line, blank lines and indentation,
;;; and perhaps followed by a line break. The expression is compiled alone, so its diagnostics are
;;; positioned in it (line 1); the command line, the workspace and the editor report them in the
;;; file. Each did this itself until 2026-11-13: the editor's answer was a line or more early after
;;; a `#lang vcl` line, and the command line refused a blank line after it.

(require racket/contract racket/string
         (only-in fhir/diagnostic diagnostic diagnostic? diagnostic-loc loc loc-source loc-line loc-column loc-position))

(provide (contract-out
          ;; file-expression : string -> string   the expression in a file's text
          [file-expression (-> string? string?)]
          ;; in-file-text : diagnostic string -> diagnostic   positioned in the file, not the expression
          [in-file-text (-> diagnostic? string? diagnostic?)]
          ;; with-file : diagnostic (or/c path-string? #f) -> diagnostic   names the file, when it names none
          [with-file (-> diagnostic? (or/c path-string? #f) diagnostic?)]))

;; prefix : string -> string   what stands before the expression: a `#lang` line, and space
(define (prefix text) (car (regexp-match #px"^(?:#lang[^\n]*)?\\s*" text)))

(define (file-expression text) (string-trim (substring text (string-length (prefix text)))))

;; the expression is one line: the lines, the columns and the characters before it count
(define (in-file-text d text)
  (define before (prefix text))
  (define l (diagnostic-loc d))
  (define lines (for/sum ([c (in-string before)]) (if (char=? c #\newline) 1 0)))
  (define indent (string-length (car (regexp-match #px"[^\n]*$" before))))
  (cond [(or (not l) (not (loc-line l)) (string=? before "")) d]
        [else (struct-copy diagnostic d
                           [loc (struct-copy loc l
                                             [line (+ (loc-line l) lines)]
                                             [column (and (loc-column l) (+ (loc-column l) indent))]
                                             [position (and (loc-position l) (+ (loc-position l) (string-length before)))])])]))

(define (with-file d source)
  (define l (diagnostic-loc d))
  (define s (if (path? source) (path->string source) source))
  (cond [(or (not s) (and l (loc-source l))) d]
        [else (struct-copy diagnostic d [loc (if l (struct-copy loc l [source s]) (loc s #f #f #f #f))])]))

(module+ test
  (require rackunit)
  (check-equal? (file-expression "#lang vcl\n\n  (http://a)x\n") "(http://a)x")
  (check-equal? (file-expression "(http://a)x") "(http://a)x")
  (define d (diagnostic 'vcl 'compile 'error "m" (loc #f 1 5 5 1)))
  (check-equal? (diagnostic-loc (in-file-text d "#lang vcl\n\n  (http://a)x\n")) (loc #f 3 7 18 1))
  (check-equal? (diagnostic-loc (in-file-text d "(http://a)x")) (loc #f 1 5 5 1))
  (check-equal? (loc-source (diagnostic-loc (with-file d "a.vcl"))) "a.vcl")
  (check-equal? (diagnostic-loc (with-file (diagnostic 'vcl 'parse 'error "m" #f) "a.vcl")) (loc "a.vcl" #f #f #f #f))
  (check-equal? (loc-source (diagnostic-loc (with-file (with-file d "a.vcl") "b.vcl"))) "a.vcl"))
