#lang racket/base

;;; compile.rkt — VclExpr -> ValueSet.compose (jsexpr), and the ValueSet with its implicit url.
;;; (The printer back to VCL text is print.rkt; `vcl-print` is provided here as well.)
;;;
;;; The compose mapping (https://build.fhir.org/ig/FHIR/ig-guidance/vcl.html "VCL Structure"):
;;;   top-level exclusion  -> compose.exclude entries (its removed side, same mapping as include)
;;;   disjunction          -> separate include entries (compose includes UNION)
;;;   conjunction          -> ONE include with several filters (compose filters AND) and value
;;;                           sets (`^a,^b`: an include's value sets intersect, FHIR R5 on — R4
;;;                           said union); conjoining code enumerations is not compose-expressible
;;;                           -> err
;;;   (system) prefix      -> include.system (+.version from a |version suffix)
;;;   codes                -> include.concept ; within one system group a disjunction of codes
;;;                           collapses into one include's concept list
;;;   *                    -> an include with system only (all codes)
;;;   ^uri                 -> include.valueSet
;;;   filters              -> include.filter {property,op,value}; an `in`/`not-in` codeList value
;;;                           joins with commas (the FHIR filter value convention); a nested
;;;                           filterList or `of` source serializes as its VCL text (the R6 nested
;;;                           form carries the expression textually)
;;;
;;; Not compose-expressible (clear errs, never silent): exclusion below the top level,
;;; conjunction of enumerations, `*` with no system, an `exists` filter whose value is not `true`
;;; or `false` (the g4: "only true and false are valid codes here"; FHIR's filter.value says the
;;; same), a code holding a comma in a `^{…}`/`~^{…}` list (the compose writes the list as one
;;; comma-separated value), and a code or a filter with no system — the
;;; grammar makes the (system) prefix optional (the specification's examples write `A;B` and
;;; `concept<<B`), but a compose include that lists concepts or filters SHALL name their system
;;; (FHIR's vsd-1 and vsd-2), so the ValueSet would be invalid. Each refusal is a `compile`
;;; diagnostic attached to the error (fhir/diagnostic `attached-diagnostic`), positioned at the
;;; term when the expression was parsed from text.

(require racket/contract racket/string racket/list racket/match
         json
         "parser/ast.rkt"
         "print.rkt"
         (only-in "parser/parse.rkt" parse-vcl)
         (only-in fhir/result/result ok err ok? ok-value result? result-bind invalid-encoding)
         (only-in fhir/diagnostic diagnostic attach-diagnostic! attached-loc))

(provide
 (contract-out
  [vcl->compose  (-> (or/c string? any/c) result?)]     ; text or AST -> Result<compose jsexpr>
  [vcl->valueset (->* (string?) (#:url (or/c string? #f) #:name (or/c string? #f)) result?)]
  [vcl-print     (-> any/c string?)]                    ; AST -> canonical VCL text (print.rkt)
  ;; the implicit value set url of an expression: http://fhir.org/VCL?v1= and the expression,
  ;; percent-encoded where a url would not carry it back
  [implicit-url  (-> string? string?)]))

(define spec-url "https://build.fhir.org/ig/FHIR/ig-guidance/vcl.html")
(define (vcl-err msg) (err (invalid-encoding 'VCL spec-url msg)))

;; A Refusal is (exn:vcl:refused message marks term): a term a compose cannot hold.
(struct exn:vcl:refused exn:fail (term))
;; refuse : VclExpr format-string any ... -> !
(define (refuse term fmt . args)
  (raise (exn:vcl:refused (apply format fmt args) (current-continuation-marks) term)))
;; refusal->err : Refusal -> err   the error, with its diagnostic: the message, at the term
(define (refusal->err e)
  (define payload (invalid-encoding 'VCL spec-url (string-append "vcl: " (exn-message e))))
  (err (attach-diagnostic! payload (diagnostic 'vcl 'compile 'error (exn-message e) (term-loc (exn:vcl:refused-term e))))))
;; term-loc : VclExpr -> loc|#f   where the term stood: its own place, else its first part's
(define (term-loc t)
  (or (attached-loc t)
      (match t
        [(vcl-sub _ inner) (term-loc inner)]
        [(or (vcl-conj (cons e _)) (vcl-disj (cons e _))) (term-loc e)]
        [(vcl-excl base _) (term-loc base)]
        [_ #f])))

;; ---- compile -----------------------------------------------------------------

(define (vcl->compose x)
  (define ast-r (if (string? x) (parse-vcl x) (ok x)))
  (result-bind ast-r
    (lambda (ast)
      (with-handlers ([exn:vcl:refused? refusal->err]
                      [exn:fail? (lambda (e) (vcl-err (exn-message e)))])
        (define-values (inc exc) (split-exclusion ast))
        (ok (drop-empty
             (hasheq 'include (append-map (lambda (b) (branch->includes b #f)) (branches inc))
                     'exclude (if exc
                                  (append-map (lambda (b) (branch->includes b #f)) (branches exc))
                                  '()))))))))

(define (drop-empty h)
  (for/hasheq ([(k v) (in-hash h)] #:unless (null? v)) (values k v)))

;; a top-level exclusion splits into (include-side, exclude-side)
(define (split-exclusion ast)
  (match ast
    [(vcl-excl base removed) (values base removed)]
    [_ (values ast #f)]))

;; the OR branches of an expr (disjunction flattens; anything else is one branch)
(define (branches ast)
  (match ast
    [(vcl-disj es) (append-map branches es)]
    [_ (list ast)]))

;; one OR branch -> (listof include-jsexpr). `sys` is the inherited (uri . version) or #f.
(define (branch->includes b sys)
  (match b
    [(vcl-sub system inner)
     ;; a system prefix scopes its whole group; a disjunction inside collapses per kind
     (system-group (or system sys) inner)]
    [(vcl-conj es) (list (conj->include es sys))]
    [(vcl-excl _ _) (refuse b "exclusion is only supported at the top level")]
    [(vcl-disj es) (append-map (lambda (e) (branch->includes e sys)) es)]
    [_ (list (simple->include b sys))]))

;; a (system)(...) group: codes merge into ONE include's concept list; filter/other branches
;; become separate includes carrying the system
(define (system-group sys inner)
  (define bs (branches inner))
  (define codes (filter vcl-code? bs))
  (define others (filter (lambda (b) (not (vcl-code? b))) bs))
  (append
   (if (pair? codes)
       (list (with-system sys (car codes) (hasheq 'concept (for/list ([c (in-list codes)])
                                                             (hasheq 'code (vcl-code-c c))))))
       '())
   (append-map (lambda (b) (branch->includes b sys)) others)))

;; a conjunction: every conjunct is a filter or a value set (an include ANDs its filters, and its
;; value sets with them and with each other)
(define (conj->include es sys)
  (define-values (fs vss)
    (for/fold ([fs '()] [vss '()] #:result (values (reverse fs) (reverse vss))) ([e (in-list es)])
      (match (strip-sub e)
        [(and f (or (vcl-filter _ _ _) (vcl-of _ _))) (values (cons (filter->jsexpr f) fs) vss)]
        [(vcl-include vs) (values fs (cons vs vss))]
        [other (refuse other "conjunction of non-filter terms is not compose-expressible: ~a"
                       (vcl-print other))])))
  (with-system (conj-system es sys) (car es)
    (for/hasheq ([k (in-list '(filter valueSet))] [v (in-list (list fs vss))] #:when (pair? v)) (values k v))))

;; a conjunction's system: an inherited one, or a single agreed (system) prefix on its terms
(define (conj-system es sys)
  (define own (remove-duplicates (filter values (map (lambda (e) (match e [(vcl-sub s _) s] [_ #f])) es))))
  (cond [(null? own) sys]
        [(and (null? (cdr own)) (or (not sys) (equal? (car own) sys))) (car own)]
        [else (refuse (car es) "conflicting systems in one conjunction")]))
(define (strip-sub e) (match e [(vcl-sub _ inner) inner] [_ e]))

;; one simple term -> one include entry
(define (simple->include b sys)
  (match b
    [(vcl-code c) (with-system sys b (hasheq 'concept (list (hasheq 'code c))))]
    [(vcl-star) (if sys (with-system sys b (hasheq))
                    (refuse b "* requires a (system) prefix to be compose-expressible"))]
    [(vcl-include vs) (with-system sys b (hasheq 'valueSet (list vs)))]
    [(and f (or (vcl-filter _ _ _) (vcl-of _ _)))
     (with-system sys b (hasheq 'filter (list (filter->jsexpr f))))]))

;; with-system : (cons uri version|#f)|#f VclExpr include -> include   the include with its system.
;; An include of concepts or filters SHALL name one (FHIR's vsd-1, vsd-2): without, the term that
;; made it is refused (`a;b`, `concept<<B`); an include of value sets needs none
(define (with-system sys term h)
  (match sys
    [#f (cond [(hash-has-key? h 'concept)
               (refuse term "a code requires a (system) prefix to be compose-expressible: ~a" (vcl-print term))]
              [(hash-has-key? h 'filter)
               (refuse term "a filter requires a (system) prefix to be compose-expressible: ~a" (vcl-print term))]
              [else h])]
    [(cons u #f) (hash-set h 'system u)]
    [(cons u v) (hash-set* h 'system u 'version v)]))

;; a filter -> {property, op, value}; structured values serialize per the compose conventions
(define (filter->jsexpr f)
  (match f
    [(vcl-filter _ 'exists (and v (not (or "true" "false"))))
     (refuse f "an exists filter's value is true or false: ~a" (vcl-print f))]
    [(vcl-filter _ (or 'in 'not-in) (vcl-code-list (list _ ... (? (lambda (c) (string-contains? c ",")) c) _ ...)))
     (refuse f "a code in a ^{…} list cannot hold a comma (the compose writes the list as one comma-separated value): ~s" c)]
    [(vcl-filter prop op v)
     (hasheq 'property prop 'op (symbol->string op) 'value (filter-value v))]
    [(vcl-of source prop)
     (hasheq 'property prop 'op "of" 'value (of-source-text source))]))

(define (filter-value v)
  (match v
    [(? string?) v]
    [(vcl-code-list codes) (string-join codes ",")]      ; the FHIR in/not-in value convention
    [(vcl-filter-list _) (vcl-print v)]))                ; R6 nested filter -> its VCL text
(define (of-source-text s)
  (match s [(? string?) s] [(vcl-code c) c] [_ (vcl-print s)]))

(define (vcl->valueset src #:url [url #f] #:name [name #f])
  (result-bind (vcl->compose src)
    (lambda (compose)
      (ok (drop-empty
           (hasheq 'resourceType "ValueSet"
                   'status "active"
                   'url (or url (implicit-url src))
                   'name (or name "VCLExpression")
                   'compose compose))))))

;; ---- the implicit url ----------------------------------------------------------------
;; implicit-url : string -> string   `http://fhir.org/VCL?v1=` and the expression, percent-encoded
;; where a url would not carry it back: the specification says the expression part "is
;; percent-encoded" and that a reader SHALL percent-decode it, so what decodes must be the
;; expression. Encoded: `%` (a URI in VCL holds its own %-escapes — `%28` for a bracket — which a
;; decoder would otherwise turn into the bracket), whitespace and what is not ASCII (a url holds
;; neither), `#` (it ends a url's query), `&` and `+` (a query's parameter separator, a form's
;; space). The rest stays as written, as the specification's own example writes it
;; (`http://fhir.org/VCL?v1=(http://loinc.org)(parent^{LP46821-2,LP259418-4})`). Until 2026-11-13
;; only spaces were encoded.
(define (implicit-url src)
  (string-append "http://fhir.org/VCL?v1=" (percent-encode src)))
(define (percent-encode s)
  (apply string-append
         (for/list ([c (in-string s)])
           (if (or (char<=? c #\space) (char>? c #\~) (memv c '(#\% #\# #\& #\+)))
               (apply string-append (for/list ([b (in-bytes (string->bytes/utf-8 (string c)))])
                                      (string-append "%" (string-upcase (if (< b 16) (format "0~x" b) (format "~x" b))))))
               (string c)))))

(module+ test
  (require rackunit
           (only-in net/uri-codec uri-decode)
           (only-in fhir/result/result err-error validation-error-message)
           (only-in fhir/diagnostic attached-diagnostic diagnostic-phase diagnostic-message diagnostic-loc
                    loc-line loc-column loc-span))
  (define (C s) (ok-value (vcl->compose s)))
  ;; a system group of codes -> one include with a concept list
  (check-equal? (C "(http://loinc.org)(a;b)")
                (hasheq 'include (list (hasheq 'system "http://loinc.org"
                                               'concept (list (hasheq 'code "a") (hasheq 'code "b"))))))
  ;; version suffix
  (check-equal? (hash-ref (car (hash-ref (C "(http://x.org|2.1)z") 'include)) 'version) "2.1")
  ;; * with a system = the whole code system
  (check-equal? (C "(http://loinc.org)*")
                (hasheq 'include (list (hasheq 'system "http://loinc.org"))))
  ;; disjunction across systems -> separate includes
  (check-equal? (length (hash-ref (C "(http://a)x;(http://b)y") 'include)) 2)
  ;; conjunction of filters -> ONE include, several filters (AND)
  (check-equal? (C "(http://loinc.org)(COMPONENT=LP212516-1,PROPERTY=LP6817-3)")
                (hasheq 'include
                        (list (hasheq 'system "http://loinc.org"
                                      'filter (list (hasheq 'property "COMPONENT" 'op "=" 'value "LP212516-1")
                                                    (hasheq 'property "PROPERTY" 'op "=" 'value "LP6817-3"))))))
  ;; ValueSet include
  (check-equal? (C "^http://hl7.org/fhir/ValueSet/payeetype")
                (hasheq 'include (list (hasheq 'valueSet (list "http://hl7.org/fhir/ValueSet/payeetype")))))
  ;; top-level exclusion -> compose.exclude
  (define ce (C "((http://a)(x;y))-((http://a)z)"))
  (check-equal? (length (hash-ref ce 'include)) 1)
  (check-equal? (hash-ref (car (hash-ref ce 'exclude)) 'concept) (list (hasheq 'code "z")))
  ;; in-filter with a code list joins with commas
  (check-equal? (hash-ref (car (hash-ref (car (hash-ref (C "(http://l)parent^{LP1,LP2}") 'include))
                                         'filter))
                          'value)
                "LP1,LP2")
  ;; is-a filter
  (check-equal? (car (hash-ref (C "(http://snomed.info/sct)concept<<17311000168105") 'include))
                (hasheq 'system "http://snomed.info/sct"
                        'filter (list (hasheq 'property "concept" 'op "is-a" 'value "17311000168105"))))
  ;; NOT compose-expressible: conjunction of enumerations, nested exclusion, bare *
  (check-false (ok? (vcl->compose "a,b")))
  (check-false (ok? (vcl->compose "(a;(b)-(c))")))
  (check-false (ok? (vcl->compose "*")))
  ;; a code or a filter with no (system): the grammar allows it (the specification's own examples),
  ;; a compose cannot hold it — its include would name no system, an invalid ValueSet (vsd-1, vsd-2;
  ;; `a;b` used to compile to one). Refused at the term, the message without wrapping.
  (define (why s)
    (define e (err-error (vcl->compose s)))
    (define d (attached-diagnostic e))
    (list (diagnostic-phase d) (diagnostic-message d)
          (let ([l (diagnostic-loc d)]) (and l (list (loc-line l) (loc-column l) (loc-span l))))))
  (check-equal? (why "a;b") '(compile "a code requires a (system) prefix to be compose-expressible: a" (1 1 1)))
  (check-equal? (why "(http://loinc.org)4548-4; 17856-6")
                '(compile "a code requires a (system) prefix to be compose-expressible: 17856-6" (1 27 7)))
  (check-equal? (why "concept << B")
                '(compile "a filter requires a (system) prefix to be compose-expressible: concept<<B" (1 1 12)))
  (check-equal? (why "(http://loinc.org)a;(p=x,q=y)")
                '(compile "a filter requires a (system) prefix to be compose-expressible: p=x" (1 22 3)))
  (check-equal? (why "B.codeprop")
                '(compile "a filter requires a (system) prefix to be compose-expressible: B.codeprop" (1 1 10)))
  (check-equal? (why "((http://a)x)-(y)")
                '(compile "a code requires a (system) prefix to be compose-expressible: y" (1 16 1)))
  (check-regexp-match #rx"a code requires a \\(system\\) prefix"
                      (validation-error-message (err-error (vcl->compose "a;b"))))
  ;; the system may come from an enclosing group; a value set needs none
  (check-true (ok? (vcl->compose "(http://loinc.org)(a;(p=x,q=y);(b;c))")))
  (check-true (ok? (vcl->compose "^http://x.org/vs ; (http://loinc.org)a")))   ; (a URI token eats a `;` that touches it)
  ;; the other refusals are positioned the same way; an AST not parsed from text has no place
  (check-equal? (why "(http://a)x;*") '(compile "* requires a (system) prefix to be compose-expressible" (1 13 1)))
  (check-equal? (why "(http://a)(x;y),(http://a)p=q")
                '(compile "conjunction of non-filter terms is not compose-expressible: x;y" (1 12 1)))
  (check-equal? (why "(http://a)x - ((http://a)y - (http://a)z)")
                '(compile "exclusion is only supported at the top level" (1 26 1)))
  (check-equal? (caddr (let ([d (attached-diagnostic (err-error (vcl->compose (vcl-code "a"))))])
                         (list (diagnostic-phase d) (diagnostic-message d) (diagnostic-loc d))))
                #f)
  ;; an exists filter takes true or false (the g4's comment; FHIR's filter.value): `p?maybe` compiled
  (check-true (ok? (vcl->compose "(http://a)p?false")))
  (check-equal? (why "(http://a)p?maybe") '(compile "an exists filter's value is true or false: p?maybe" (1 11 7)))
  ;; a code of an in-list holding a comma would split when the compose's value is read back
  (check-equal? (why "(http://a)p^{x,\"y,z\"}")
                '(compile "a code in a ^{…} list cannot hold a comma (the compose writes the list as one comma-separated value): \"y,z\"" (1 11 11)))
  ;; value sets in a conjunction are one include's value sets (they intersect, FHIR R5 on), with its
  ;; filters; they were refused as "non-filter terms"
  (check-equal? (C "^http://v/a , ^http://v/b")
                (hasheq 'include (list (hasheq 'valueSet '("http://v/a" "http://v/b")))))
  (check-equal? (C "(http://a)(p=x, ^http://v/a)")
                (hasheq 'include (list (hasheq 'system "http://a" 'filter (list (hasheq 'property "p" 'op "=" 'value "x"))
                                               'valueSet '("http://v/a")))))
  (check-equal? (why "(http://a)(x, ^http://v/a)")
                '(compile "conjunction of non-filter terms is not compose-expressible: x" (1 12 1)))
  ;; the implicit url decodes to the expression (the specification: a reader SHALL percent-decode
  ;; it); `%`, `#`, `&`, `+`, spaces and what is not ASCII are encoded, the rest left as the
  ;; specification's own example writes it
  (check-equal? (implicit-url "(http://loinc.org)(parent^{LP46821-2,LP259418-4})")
                "http://fhir.org/VCL?v1=(http://loinc.org)(parent^{LP46821-2,LP259418-4})")
  (check-equal? (implicit-url "(http://x.org/a%28b%29)c ; (http://y.org/s?a=1&b=2#f)\"d+é\"")
                "http://fhir.org/VCL?v1=(http://x.org/a%2528b%2529)c%20;%20(http://y.org/s?a=1%26b=2%23f)\"d%2B%C3%A9\"")
  (for ([e (in-list '("(http://x.org/a%28b%29)c" "(http://a)p=\"x y\" , q=\"é+&#%\"" "(http://loinc.org)(4548-4; 17856-6)"))])
    (check-equal? (uri-decode (substring (implicit-url e) (string-length "http://fhir.org/VCL?v1="))) e))
  ;; print∘parse fixpoint on canonical text
  (define (fix s) (define a (ok-value (parse-vcl s)))
                  (check-equal? (ok-value (parse-vcl (vcl-print a))) a s))
  (for-each fix '("(http://loinc.org)(a;b)" "concept<<B" "parent^{LP1,LP2}"
                  "(a;b)-(c)" "^http://x.org/vs" "has_ingredient^{has_tradename=2201670}"
                  "{concept<B}.codeprop" "ingredient?true" "(http://x.org|2.1)z")))
