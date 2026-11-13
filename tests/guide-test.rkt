#lang racket/base

;;; guide-test.rkt — guide.md (the language guide agents read: fhir-mcp serves it as learn://vcl,
;;; the vcl skill points to it) keeps its promises: every ```vcl block parses and compiles to a
;;; compose, the operator table is the compiler's, the worked example compiles to the compose and
;;; url the text gives, and what the text says a compose cannot say is refused. Also the command
;;; line on a `#lang vcl` file (it once rejected every such file: blanking the #lang line left a
;;; newline the lexer forbids).

(require rackunit racket/runtime-path racket/file racket/list racket/string racket/port racket/system racket/match json
         (only-in vcl/compile vcl->compose vcl->valueset)
         (only-in vcl/parser/parse parse-vcl)
         (only-in vcl/workspace guide)
         (only-in fhir/result/result ok? ok-value err-error validation-error-message))

(define-runtime-path guide-file "../guide.md")
(define text (file->string guide-file))
(define blocks (map (lambda (b) (string-trim (cadr b))) (regexp-match* #px"```vcl\n(.*?)```" text #:match-select values)))
(define (compose-of e) (let ([r (vcl->compose e)]) (and (ok? r) (ok-value r))))
(define (refusal e) (let ([r (vcl->compose e)]) (and (not (ok? r)) (validation-error-message (err-error r)))))

(test-case "the guide the workspace serves is this file"
  (check-equal? guide text))

(test-case "every vcl block parses and compiles to a compose"
  (check-true (>= (length blocks) 8))
  (for ([b (in-list blocks)])
    (check-true (ok? (parse-vcl b)) b)
    (check-true (hash? (compose-of b)) b)))

(test-case "the cheat sheet compiles as the text says"
  (define (filters e) (hash-ref (car (hash-ref (compose-of e) 'include)) 'filter))
  (check-equal? (hash-ref (car (filters "(http://snomed.info/sct)concept<<73211009")) 'op) "is-a")
  (check-equal? (hash-ref (car (filters "(http://snomed.info/sct)concept<73211009")) 'op) "descendent-of")
  (check-true (pair? (hash-ref (compose-of "(http://loinc.org)(4548-4; 17856-6) - (http://loinc.org)17856-6") 'exclude)))
  (check-equal? (hash-ref (compose-of "(http://loinc.org)*") 'include) (list (hasheq 'system "http://loinc.org")))
  (check-equal? (hash-ref (car (hash-ref (compose-of "^http://hl7.org/fhir/ValueSet/administrative-gender") 'include)) 'valueSet)
                '("http://hl7.org/fhir/ValueSet/administrative-gender"))
  (check-equal? (length (filters "(http://loinc.org)(COMPONENT=\"Hemoglobin A1c\", SYSTEM=\"Bld\")")) 2))

(test-case "the operator table is the compiler's"
  ;; each row of the table: `| vcl | fhir | vcl | fhir |`
  (define rows (for*/list ([l (in-list (string-split text "\n"))]
                           #:when (regexp-match? #px"^\\| `" l)
                           [pair (in-list (regexp-match* #px"`([^`]+)` \\| `([^`]+)`" l #:match-select cdr))])
                 pair))
  (check-equal? (length rows) 11)
  (for ([r (in-list rows)])
    (match-define (list vcl fhir) r)
    (define e* (cond [(member vcl '("^{a,b}" "~^{a,b}" "?true")) (string-append "(http://x)concept" vcl)]
                     [(equal? vcl "/\"regex\"") "(http://x)concept/\"a.*\""]
                     [(equal? vcl "=") "(http://x)concept=\"v\""]
                     [else (string-append "(http://x)concept" vcl "v")]))
    (define c (compose-of e*))
    (check-true (hash? c) e*)
    (when c (check-equal? (hash-ref (car (hash-ref (car (hash-ref c 'include)) 'filter)) 'op) fhir e*))))

(test-case "the worked example compiles to the compose and url the text gives"
  (define e "(http://loinc.org)(4548-4; 17856-6)")
  (check-true (string-contains? text (string-append "```vcl\n" e "\n```")))
  (check-equal? (compose-of e)
                (hasheq 'include (list (hasheq 'system "http://loinc.org" 'concept (list (hasheq 'code "4548-4") (hasheq 'code "17856-6"))))))
  (check-equal? (hash-ref (ok-value (vcl->valueset e)) 'url) "http://fhir.org/VCL?v1=(http://loinc.org)(4548-4;%2017856-6)")
  (check-true (string-contains? text "http://fhir.org/VCL?v1=(http://loinc.org)(4548-4;%2017856-6)")))

(test-case "what a compose cannot say is refused, as the text says"
  (check-regexp-match #rx"only supported at the top level"
                      (refusal "(http://loinc.org)4548-4 - ((http://loinc.org)* - (http://loinc.org)17856-6)"))
  (check-regexp-match #rx"conjunction of non-filter terms"
                      (refusal "(http://loinc.org)(4548-4; 17856-6), (http://loinc.org)17856-6"))
  (check-regexp-match #rx"requires a \\(system\\) prefix" (refusal "*"))
  (check-equal? (refusal "4548-4; 17856-6")
                "VCL: invalid encoding \"vcl: a code requires a (system) prefix to be compose-expressible: 4548-4\" (see https://build.fhir.org/ig/FHIR/ig-guidance/vcl.html)")
  (check-true (string-contains? text "a code requires a (system) prefix to be compose-expressible: 4548-4"))
  (check-regexp-match #rx"a filter requires a \\(system\\) prefix" (refusal "concept<<73211009"))
  (check-regexp-match #rx"a code requires a \\(system\\) prefix to be compose-expressible: 17856-6"
                      (refusal "(http://loinc.org)4548-4; 17856-6"))      ; the common problem
  (check-true (hash? (compose-of "^http://hl7.org/fhir/ValueSet/administrative-gender")))   ; a value set needs none
  ;; and the common problems: no precedence between ; and , ; a system outside brackets
  (check-false (ok? (parse-vcl "(http://loinc.org)4548-4;(http://snomed.info/sct)73211009, (http://loinc.org)x")))
  (check-false (ok? (parse-vcl "http://loinc.org|4548-4"))))

(test-case "the command line reads a #lang vcl file, and places an error on its line"
  (define dir (make-temporary-directory))
  (define (vcl . args)
    (define out (open-output-string))
    (define code (parameterize ([current-output-port out] [current-error-port out])
                   (apply system*/exit-code (find-executable-path (find-system-path 'exec-file)) "-l" "raco" "vcl" args)))
    (values code (get-output-string out)))
  (define good (build-path dir "good.vcl"))
  (define bad (build-path dir "bad.vcl"))
  (display-to-file "#lang vcl\n(http://loinc.org)(8480-6; 8462-4)\n" good)
  (display-to-file "#lang vcl\n(http://loinc.org)(8480-6; 8462-4\n" bad)
  (define-values (c1 o1) (vcl (path->string good)))
  (check-equal? c1 0 o1)
  (check-equal? (hash-ref (string->jsexpr o1) 'compose) (compose-of "(http://loinc.org)(8480-6; 8462-4)"))
  (define-values (c2 o2) (vcl "--format" "json" (path->string bad)))
  (check-equal? c2 1)
  (define d (car (hash-ref (string->jsexpr o2) 'diagnostics)))
  (check-equal? (list (hash-ref d 'line) (hash-ref d 'column)) '(2 28))
  (delete-directory/files dir))
