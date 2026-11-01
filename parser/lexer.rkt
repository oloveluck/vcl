#lang racket/base

;;; lexer.rkt — VCL source text -> the token stream brag consumes.
;;;
;;; Tokens follow the vendored official grammar (vcl.g4) exactly:
;;;   URI          [a-zA-Z]+ ':' [uri-chars]+ ('|' version)?   — NOTE the char set greedily eats
;;;                ';', '&', '^', '{', '}' etc.; that is faithful to the g4 and is exactly why the
;;;                grammar delimits a system URI with round brackets.
;;;   SCODE        [a-zA-Z0-9][-_a-zA-Z0-9]*
;;;   QUOTED       "..." with backslash escaping ONLY \" and \\
;;;   operators    ~<< << <! < >> ~^ ^ !!< ? / = . * - ( ) { } ; ,   (longest match wins)
;;; Spaces and tabs are skipped; newlines are PROHIBITED by the spec and raise a lex error.

(require brag/support
         br-parser-tools/lex
         (prefix-in : br-parser-tools/lex-sre)
         racket/contract)

(provide (contract-out [tokenize (-> input-port? any/c)]))

(define (trim-ends s) (substring s 1 (sub1 (string-length s))))
;; only \" and \\ are escapable (spec)
(define (unescape s) (regexp-replace* #px"\\\\([\"\\\\])" s "\\1"))

(define vcl-lexer
  (lexer
   [(eof) (void)]
   [(:or " " "\t") (token 'WS lexeme #:skip? #t)]
   [(:or "\n" "\r") (error 'vcl "newlines are not permitted in a VCL expression")]

   ;; URI before SCODE (both can start with letters); version tail after '|' excludes | ( )
   [(:: (:+ alphabetic) ":"
        (:+ (:or alphabetic numeric "?" "=" ":" ";" "&" "_" "%" "+" "-" "." "@" "#" "$" "^" "!" "{" "}" "/"))
        (:? (:: "|" (:* (:~ "|" "(" ")")))))
    (token 'URI lexeme)]

   [(:: "\"" (:* (:or (:: "\\" (:or "\"" "\\")) (:~ "\"" "\\"))) "\"")
    (token 'QUOTED (unescape (trim-ends lexeme)))]

   [(:: (:or alphabetic numeric) (:* (:or alphabetic numeric "-" "_")))
    (token 'SCODE lexeme)]

   ;; operators — the lexer picks the longest match, so ~<< beats ~^ beats ^ etc.
   ["~<<" (token 'IS-NOT-A lexeme)]
   ["<<"  (token 'IS-A lexeme)]
   ["<!"  (token 'CHILD-OF lexeme)]
   ["<"   (token 'DESC-OF lexeme)]
   [">>"  (token 'GENERALIZES lexeme)]
   ["~^"  (token 'NOT-IN lexeme)]
   ["^"   (token 'CARET lexeme)]
   ["!!<" (token 'DESC-LEAF lexeme)]
   ["?"   (token 'EXISTS lexeme)]
   ["/"   (token 'REGEX lexeme)]
   ["="   (token 'EQ lexeme)]
   ["."   (token 'DOT lexeme)]
   ["*"   (token 'STAR lexeme)]
   ["-"   (token 'DASH lexeme)]
   ["("   (token 'OPEN lexeme)]
   [")"   (token 'CLOSE lexeme)]
   ["{"   (token 'LCRLY lexeme)]
   ["}"   (token 'RCRLY lexeme)]
   [";"   (token 'SEMI lexeme)]
   [","   (token 'COMMA lexeme)]))

(define (tokenize ip)
  (define (next-token) (vcl-lexer ip))
  next-token)

(module+ test
  (require rackunit)
  (define (toks s)
    (define next (tokenize (open-input-string s)))
    (let loop ([acc '()])
      (define t (next))
      (if (void? t) (reverse acc)
          (loop (if (and (token-struct? t) (eq? (token-struct-type t) 'WS)) acc (cons t acc))))))
  (define (types s) (map token-struct-type (toks s)))
  ;; longest-match operator discipline
  (check-equal? (types "concept~<<X") '(SCODE IS-NOT-A SCODE))
  (check-equal? (types "a<<b") '(SCODE IS-A SCODE))
  (check-equal? (types "a<!b") '(SCODE CHILD-OF SCODE))
  (check-equal? (types "a<b") '(SCODE DESC-OF SCODE))
  (check-equal? (types "a~^{x,y}") '(SCODE NOT-IN LCRLY SCODE COMMA SCODE RCRLY))
  ;; a URI eats ; & ^ … until whitespace/paren — the g4's deliberate greed
  (check-equal? (types "^http://ex.org/vs?a=1;b=2") '(CARET URI))
  (check-equal? (types "(http://loinc.org)(a;b)") '(OPEN URI CLOSE OPEN SCODE SEMI SCODE CLOSE))
  ;; URI|version keeps the version tail
  (check-equal? (map token-struct-val (toks "(http://x.org|2.1)")) '("(" "http://x.org|2.1" ")"))
  ;; quoting: only \" and \\ escape
  (check-equal? (map token-struct-val (toks "\"a\\\"b\\\\c\"")) '("a\"b\\c"))
  ;; the spec prohibits newlines
  (check-exn exn:fail? (lambda () (types "a\nb"))))
