#lang racket/base

;;; lexer.rkt — VCL source text -> its tokens.
;;;
;;; A Token is brag's token structure (type, value, line, column, offset, span); the types are
;;; the vendored official grammar's (vcl.g4), with `IN` named CARET and `-` for `_`:
;;;   URI          [a-zA-Z]+ ':' [uri-chars]+ ('|' version)?   — NOTE the char set greedily eats
;;;                ';', '&', '^', '{', '}' etc.; that is faithful to the g4 and is exactly why the
;;;                grammar delimits a system URI with round brackets.
;;;   SCODE        [a-zA-Z0-9][-_a-zA-Z0-9]*
;;;   QUOTED       "..." with backslash escaping ONLY \" and \\
;;;   operators    ~<< << <! < >> ~^ ^ !!< ? / = . * - ( ) { } ; ,   (longest match wins)
;;; Spaces and tabs are skipped; newlines are PROHIBITED by the spec and are a lex error.
;;; Letters and digits are ASCII's, as the g4 writes them (`café` is quoted; a URI's other
;;; characters are percent-encoded): Unicode's were accepted until 2026-11-13.
;;;
;;; One reading of the g4 is ours: in the URI character set `[a-zA-Z0-9?=:;&_%+-.@#$^!{}/]` the
;;; three characters `+-.` are, as ANTLR reads a set, the RANGE `+`..`.`, which adds `,`. They are
;;; read here as the three characters (every other character of the set is listed singly, and a
;;; comma that touches a URI — `p^http://x/vs,q=1` — would otherwise never separate two filters).

(require brag/support
         br-parser-tools/lex
         (only-in fhir/diagnostic diagnostic loc raise-diagnostic)
         (prefix-in : br-parser-tools/lex-sre)
         racket/contract)

(provide (contract-out
          ;; the tokens of an expression, without the skipped space; a lex error is raised as a
          ;; positioned diagnostic (exn:fail:diagnostic)
          [tokenize (-> string? (listof token-struct?))]))

(define (trim-ends s) (substring s 1 (sub1 (string-length s))))
;; only \" and \\ are escapable (spec)
(define (unescape s) (regexp-replace* #px"\\\\([\"\\\\])" s "\\1"))

(define-lex-abbrevs
  [letter (:or (:/ "a" "z") (:/ "A" "Z"))]
  [digit (:/ "0" "9")]
  [uri-char (:or letter digit "?" "=" ":" ";" "&" "_" "%" "+" "-" "." "@" "#" "$" "^" "!" "{" "}" "/")])

;; tok : symbol string position position -> Token   a token that knows where it stood
(define (tok type value start end)
  (token type value
         #:line (position-line start) #:column (position-col start)
         #:position (position-offset start) #:span (- (position-offset end) (position-offset start))))

(define vcl-lexer
  (lexer
   [(eof) eof]
   [(:+ (:or " " "\t")) (vcl-lexer input-port)]

   ;; URI before SCODE (both can start with letters); version tail after '|' excludes | ( )
   [(:: (:+ letter) ":" (:+ uri-char) (:? (:: "|" (:* (:~ "|" "(" ")")))))
    (tok 'URI lexeme start-pos end-pos)]

   [(:: "\"" (:* (:or (:: "\\" (:or "\"" "\\")) (:~ "\"" "\\"))) "\"")
    (tok 'QUOTED (unescape (trim-ends lexeme)) start-pos end-pos)]

   [(:: (:or letter digit) (:* (:or letter digit "-" "_")))
    (tok 'SCODE lexeme start-pos end-pos)]

   ;; operators — the lexer picks the longest match, so ~<< beats ~^ beats ^ etc.
   ["~<<" (tok 'IS-NOT-A lexeme start-pos end-pos)]
   ["<<"  (tok 'IS-A lexeme start-pos end-pos)]
   ["<!"  (tok 'CHILD-OF lexeme start-pos end-pos)]
   ["<"   (tok 'DESC-OF lexeme start-pos end-pos)]
   [">>"  (tok 'GENERALIZES lexeme start-pos end-pos)]
   ["~^"  (tok 'NOT-IN lexeme start-pos end-pos)]
   ["^"   (tok 'CARET lexeme start-pos end-pos)]
   ["!!<" (tok 'DESC-LEAF lexeme start-pos end-pos)]
   ["?"   (tok 'EXISTS lexeme start-pos end-pos)]
   ["/"   (tok 'REGEX lexeme start-pos end-pos)]
   ["="   (tok 'EQ lexeme start-pos end-pos)]
   ["."   (tok 'DOT lexeme start-pos end-pos)]
   ["*"   (tok 'STAR lexeme start-pos end-pos)]
   ["-"   (tok 'DASH lexeme start-pos end-pos)]
   ["("   (tok 'OPEN lexeme start-pos end-pos)]
   [")"   (tok 'CLOSE lexeme start-pos end-pos)]
   ["{"   (tok 'LCRLY lexeme start-pos end-pos)]
   ["}"   (tok 'RCRLY lexeme start-pos end-pos)]
   [";"   (tok 'SEMI lexeme start-pos end-pos)]
   [","   (tok 'COMMA lexeme start-pos end-pos)]

   ;; anything else is no token: say what, where it starts
   [any-char (unrecognized lexeme start-pos input-port)]))

;; unrecognized : string position input-port -> !   the lex diagnostic for a character no token
;; starts with, at that character: the text up to the next space is quoted, and the three mistakes
;; that can be told from the character are named
(define (unrecognized first start in)
  (define rest (let ([s (peek-string 29 0 in)]) (if (eof-object? s) "" s)))
  (define word (string-append first (car (regexp-match #rx"^[^ \t\r\n]*" rest))))
  (define c (string-ref first 0))
  (raise-diagnostic
   (diagnostic 'vcl 'lex 'error
               (cond [(memv c '(#\newline #\return))
                      "a line break is not permitted in a VCL expression"]
                     [(char=? c #\")
                      (format "unrecognized text `~a` (a quoted value ends with `\"`, and only `\\\"` and `\\\\` are escapes)" word)]
                     [(or (char-alphabetic? c) (char-numeric? c))
                      (format "unrecognized text `~a` (a code with characters other than A-Z, a-z, 0-9, `-` and `_` is quoted)" word)]
                     [else (format "unrecognized text `~a`" word)])
               (loc #f (position-line start) (add1 (position-col start)) (position-offset start) #f))))

;; tokenize : string -> (listof Token)
(define (tokenize str)
  (define in (open-input-string str))
  (port-count-lines! in)
  (let loop ([acc '()])
    (define t (vcl-lexer in))
    (if (eof-object? t) (reverse acc) (loop (cons t acc)))))

(module+ test
  (require rackunit (only-in fhir/diagnostic exn:fail:diagnostic? exn:fail:diagnostic-diagnostic
                             diagnostic-message diagnostic-loc loc-line loc-column loc-position))
  (define (types s) (map token-struct-type (tokenize s)))
  (define (vals s) (map token-struct-val (tokenize s)))
  ;; longest-match operator discipline
  (check-equal? (types "concept~<<X") '(SCODE IS-NOT-A SCODE))
  (check-equal? (types "a<<b") '(SCODE IS-A SCODE))
  (check-equal? (types "a<!b") '(SCODE CHILD-OF SCODE))
  (check-equal? (types "a<b") '(SCODE DESC-OF SCODE))
  (check-equal? (types "a~^{x,y}") '(SCODE NOT-IN LCRLY SCODE COMMA SCODE RCRLY))
  ;; a URI eats ; & ^ … until whitespace/paren — the g4's deliberate greed
  (check-equal? (types "^http://ex.org/vs?a=1;b=2") '(CARET URI))
  (check-equal? (types "(http://loinc.org)(a;b)") '(OPEN URI CLOSE OPEN SCODE SEMI SCODE CLOSE))
  ;; … but not a comma: `+-.` in the g4's set is read as three characters, not ANTLR's range
  (check-equal? (vals "p^http://x.org/vs+a-b.c,q=1") '("p" "^" "http://x.org/vs+a-b.c" "," "q" "=" "1"))
  ;; URI|version keeps the version tail
  (check-equal? (vals "(http://x.org|2.1)") '("(" "http://x.org|2.1" ")"))
  ;; quoting: only \" and \\ escape
  (check-equal? (vals "\"a\\\"b\\\\c\"") '("a\"b\\c"))
  ;; a token knows where it stood (0-based column, 1-based offset, as brag counts)
  (check-equal? (for/list ([t (in-list (tokenize "ab ; \"c d\""))])
                  (list (token-struct-line t) (token-struct-column t) (token-struct-offset t) (token-struct-span t)))
                '((1 0 1 2) (1 3 4 1) (1 5 6 5)))
  ;; what is no token is a lex diagnostic at its first character, quoting the text that starts there
  (define (lex-error s)
    (with-handlers ([exn:fail:diagnostic? (lambda (e)
                                            (define d (exn:fail:diagnostic-diagnostic e))
                                            (define l (diagnostic-loc d))
                                            (list (diagnostic-message d) (loc-line l) (loc-column l) (loc-position l)))])
      (tokenize s) #f))
  (check-equal? (lex-error "a @b c") '("unrecognized text `@b`" 1 3 3))
  ;; the spec prohibits newlines (the message used to quote the text AFTER the line break)
  (check-equal? (lex-error "a\nb") '("a line break is not permitted in a VCL expression" 1 2 2))
  ;; a quoted value that does not close, or holds another escape
  (check-equal? (car (lex-error "p=\"a\\nb\"")) "unrecognized text `\"a\\nb\"` (a quoted value ends with `\"`, and only `\\\"` and `\\\\` are escapes)")
  (check-equal? (cdr (lex-error "p=\"a")) '(1 3 3))
  ;; ASCII letters and digits only, as the g4 writes them: other letters are quoted, or percent-encoded
  (check-equal? (types "\"café\"") '(QUOTED))
  (check-equal? (lex-error "(http://a)café")
                '("unrecognized text `é` (a code with characters other than A-Z, a-z, 0-9, `-` and `_` is quoted)" 1 14 14))
  (check-pred pair? (lex-error "(http://ä.org)x"))
  (check-pred pair? (lex-error "(ħttp://a.org)x")))
