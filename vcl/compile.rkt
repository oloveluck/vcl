#lang racket/base

;;; compile.rkt — VclExpr -> ValueSet.compose (jsexpr), and the printer back to VCL text.
;;;
;;; The compose mapping (https://build.fhir.org/ig/FHIR/ig-guidance/vcl.html "VCL Structure"):
;;;   top-level exclusion  -> compose.exclude entries (its removed side, same mapping as include)
;;;   disjunction          -> separate include entries (compose includes UNION)
;;;   conjunction          -> ONE include with several filters (compose filters AND);
;;;                           conjoining code enumerations is not compose-expressible -> err
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
;;; conjunction of enumerations, a bare `of` at include level with no property context.

(require racket/contract racket/string racket/list racket/match
         json
         "parser/ast.rkt"
         (only-in "parser/parse.rkt" parse-vcl)
         (only-in fhir/result/result ok err ok? ok-value result? result-bind invalid-encoding))

(provide
 (contract-out
  [vcl->compose  (-> (or/c string? any/c) result?)]     ; text or AST -> Result<compose jsexpr>
  [vcl->valueset (->* (string?) (#:url (or/c string? #f) #:name (or/c string? #f)) result?)]
  [vcl-print     (-> any/c string?)]))                  ; AST -> canonical VCL text

(define spec-url "https://build.fhir.org/ig/FHIR/ig-guidance/vcl.html")
(define (vcl-err msg) (err (invalid-encoding 'VCL spec-url msg)))

;; ---- compile -----------------------------------------------------------------

(define (vcl->compose x)
  (define ast-r (if (string? x) (parse-vcl x) (ok x)))
  (result-bind ast-r
    (lambda (ast)
      (with-handlers ([exn:fail? (lambda (e) (vcl-err (exn-message e)))])
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
    [(vcl-excl _ _) (error 'vcl "exclusion is only supported at the top level")]
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
       (list (with-system sys (hasheq 'concept (for/list ([c (in-list codes)])
                                                 (hasheq 'code (vcl-code-c c))))))
       '())
   (append-map (lambda (b) (branch->includes b sys)) others)))

;; a conjunction: every conjunct must be a filter (compose ANDs filters within an include)
(define (conj->include es sys)
  (define fs (for/list ([e (in-list es)])
               (match (strip-sub e)
                 [(and f (or (vcl-filter _ _ _) (vcl-of _ _))) (filter->jsexpr f)]
                 [other (error 'vcl "conjunction of non-filter terms is not compose-expressible: ~a"
                               (vcl-print other))])))
  (with-system (conj-system es sys) (hasheq 'filter fs)))

;; a conjunction's system: an inherited one, or a single agreed (system) prefix on its terms
(define (conj-system es sys)
  (define own (remove-duplicates (filter values (map (lambda (e) (match e [(vcl-sub s _) s] [_ #f])) es))))
  (cond [(null? own) sys]
        [(and (null? (cdr own)) (or (not sys) (equal? (car own) sys))) (car own)]
        [else (error 'vcl "conflicting systems in one conjunction")]))
(define (strip-sub e) (match e [(vcl-sub _ inner) inner] [_ e]))

;; one simple term -> one include entry
(define (simple->include b sys)
  (match b
    [(vcl-code c) (with-system sys (hasheq 'concept (list (hasheq 'code c))))]
    [(vcl-star) (if sys (with-system sys (hasheq))
                    (error 'vcl "* requires a (system) prefix to be compose-expressible"))]
    [(vcl-include vs) (with-system sys (hasheq 'valueSet (list vs)))]
    [(and f (or (vcl-filter _ _ _) (vcl-of _ _)))
     (with-system sys (hasheq 'filter (list (filter->jsexpr f))))]))

(define (with-system sys h)
  (match sys
    [#f h]
    [(cons u #f) (hash-set h 'system u)]
    [(cons u v) (hash-set* h 'system u 'version v)]))

;; a filter -> {property, op, value}; structured values serialize per the compose conventions
(define (filter->jsexpr f)
  (match f
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
                   'url (or url (string-append "http://fhir.org/VCL?v1="
                                               (string-replace src " " "%20")))
                   'name (or name "VCLExpression")
                   'compose compose))))))

;; ---- print (AST -> canonical VCL text) ----------------------------------------
(define op-sym
  (hash '= "=" 'is-a "<<" 'is-not-a "~<<" 'descendent-of "<" 'regex "/" 'in "^" 'not-in "~^"
        'generalizes ">>" 'child-of "<!" 'descendent-leaf "!!<" 'exists "?"))

(define (vcl-print a)
  (match a
    [(vcl-sub (cons u v) inner)
     (format "(~a~a)~a" u (if v (string-append "|" v) "") (group inner))]
    ;; the spec defines NO precedence between , and ; — a compound member must re-bracket
    [(vcl-conj es) (string-join (map print-member es) ",")]
    [(vcl-disj es) (string-join (map print-member es) ";")]
    [(vcl-excl b r) (format "(~a)-(~a)" (vcl-print b) (vcl-print r))]
    [(vcl-code c) (print-code c)]
    [(vcl-star) "*"]
    [(vcl-include t) (string-append "^" t)]
    [(vcl-filter prop op v)
     (string-append (print-code prop) (hash-ref op-sym op) (print-value op v))]
    [(vcl-of source prop) (string-append (print-of-source source) "." (print-code prop))]
    [(vcl-code-list codes) (format "{~a}" (string-join (map print-code codes) ","))]
    [(vcl-filter-list fs) (format "{~a}" (string-join (map vcl-print fs) ","))]))

;; a compound expr under a system prefix prints inside brackets
(define (group inner)
  (match inner
    [(or (vcl-conj _) (vcl-disj _) (vcl-excl _ _)) (format "(~a)" (vcl-print inner))]
    [_ (vcl-print inner)]))

;; a conjunction/disjunction member that is itself compound re-brackets
(define (print-member e)
  (match e
    [(or (vcl-conj _) (vcl-disj _) (vcl-excl _ _)) (format "(~a)" (vcl-print e))]
    [_ (vcl-print e)]))

(define (print-value op v)
  (match v
    [(? string? s) (if (memq op '(regex)) (quote-str s) (print-code-or-uri s))]
    [_ (vcl-print v)]))
(define (print-of-source s)
  (match s [(? string?) s] [(vcl-code c) (print-code c)] [_ (vcl-print s)]))
(define (print-code-or-uri s) (if (regexp-match? #px"^[a-zA-Z]+:" s) s (print-code s)))
;; a code prints bare when it is a simple SCODE, quoted otherwise
(define (print-code c)
  (if (regexp-match? #px"^[a-zA-Z0-9][-_a-zA-Z0-9]*$" c) c (quote-str c)))
(define (quote-str s)
  (format "\"~a\"" (string-replace (string-replace s "\\" "\\\\") "\"" "\\\"")))

(module+ test
  (require rackunit)
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
  ;; print∘parse fixpoint on canonical text
  (define (fix s) (define a (ok-value (parse-vcl s)))
                  (check-equal? (ok-value (parse-vcl (vcl-print a))) a s))
  (for-each fix '("(http://loinc.org)(a;b)" "concept<<B" "parent^{LP1,LP2}"
                  "(a;b)-(c)" "^http://x.org/vs" "has_ingredient^{has_tradename=2201670}"
                  "{concept<B}.codeprop" "ingredient?true" "(http://x.org|2.1)z")))
