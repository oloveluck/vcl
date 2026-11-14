#lang racket/base

;;; cli-test.rkt — `raco vcl` as a person calls it, on the two mistakes it once let through:
;;;   * a file name with no file (`nothere.vcl`) was compiled as an expression ("the code nothere,
;;;     its property vcl"), exit 0: it is the family's one-line "cannot read", exit 2;
;;;   * codes with no code system (`a;b`) compiled to a ValueSet whose include names no system,
;;;     which FHIR refuses (vsd-1, vsd-2): it is a compile error at the code, exit 1 — at the
;;;     command line, and when a `#lang vcl` module is built.
;;; Expressions that are not files still compile, the ones with `.vcl` or `/` in them included.

(require rackunit racket/file racket/port racket/string racket/system json)

;; vcl : string ... -> (values exit-code stdout stderr)   `raco vcl <args>` from directory `dir`
(define dir (make-temporary-directory "vcl-cli-~a"))
(define (vcl . args)
  (define out (open-output-string))
  (define err (open-output-string))
  (define code (parameterize ([current-output-port out] [current-error-port err] [current-directory dir])
                 (apply system*/exit-code (find-executable-path (find-system-path 'exec-file)) "-l" "raco" "vcl" args)))
  (values code (get-output-string out) (get-output-string err)))
(define (lines s) (string-split s "\n"))

(test-case "a file name with no file is `cannot read`, exit 2"
  (for ([arg (in-list '("nothere.vcl" "sets/nothere.vcl" "./nothere" "NOTHERE.VCL"))])
    (define-values (code out err) (vcl arg))
    (check-equal? code 2 arg)
    (check-equal? out "" arg)
    (check-equal? (length (lines err)) 1 err)
    (check-regexp-match #rx"^vcl: cannot read .*[Nn][Oo][Tt][Hh][Ee][Rr][Ee]" err)))

(test-case "a file that is there is read, whatever its name"
  (display-to-file "(http://loinc.org)(8480-6; 8462-4)\n" (build-path dir "bp"))
  (define-values (code out err) (vcl "bp"))
  (check-equal? code 0 err)
  (check-equal? (hash-ref (car (hash-ref (hash-ref (string->jsexpr out) 'compose) 'include)) 'system) "http://loinc.org"))

(test-case "an expression is still an expression"
  (for ([e (in-list '("(http://loinc.org)(4548-4; 17856-6)"
                      "^http://hl7.org/fhir/ValueSet/administrative-gender"
                      "(http://loinc.org)COMPONENT/\".*Dichloroethane.*\""
                      "(http://example.org/cs)panadol.vcl"))])                 ; the property `vcl` of a code
    (define-values (code out err) (vcl e))
    (check-equal? code 0 (string-append e ": " err))
    (check-equal? (hash-ref (string->jsexpr out) 'resourceType) "ValueSet" e)))

(test-case "codes of no code system are a compile error at the code, exit 1"
  (define-values (code out err) (vcl "a;b"))
  (check-equal? code 1)
  (check-equal? out "")
  (check-equal? (car (lines err)) "<expression>:1:1: vcl compile error: a code requires a (system) prefix to be compose-expressible: a")
  (define-values (code2 out2 err2) (vcl "--format" "json" "(http://loinc.org)4548-4; 17856-6"))
  (check-equal? code2 1)
  (define d (car (hash-ref (string->jsexpr out2) 'diagnostics)))
  (check-equal? (list (hash-ref d 'phase) (hash-ref d 'line) (hash-ref d 'column) (hash-ref d 'message))
                '("compile" 1 27 "a code requires a (system) prefix to be compose-expressible: 17856-6"))
  ;; in a file, on the file's line
  (display-to-file "#lang vcl\na;b\n" (build-path dir "nosystem.vcl"))
  (define-values (code3 out3 err3) (vcl "nosystem.vcl"))
  (check-equal? code3 1)
  (check-equal? (car (lines err3)) "nosystem.vcl:2:1: vcl compile error: a code requires a (system) prefix to be compose-expressible: a"))

(test-case "a file with a blank line after its #lang line is read (it was a lex error at the blank line)"
  (display-to-file "#lang vcl\n\n  (http://loinc.org)(8480-6; 8462-4)\n" (build-path dir "blank.vcl"))
  (define-values (code out err) (vcl "blank.vcl"))
  (check-equal? code 0 err)
  (display-to-file "#lang vcl\n\n  (http://loinc.org)4548-4; 17856-6\n" (build-path dir "blank-bad.vcl"))
  (define-values (code2 out2 err2) (vcl "blank-bad.vcl"))
  (check-equal? code2 1)
  (check-equal? (car (lines err2)) "blank-bad.vcl:3:29: vcl compile error: a code requires a (system) prefix to be compose-expressible: 17856-6"))

(test-case "a #lang vcl module of codes with no system does not build: a syntax error at the code"
  (define file (build-path dir "nosystem.vcl"))
  (define e (with-handlers ([exn:fail:syntax? values])
              (parameterize ([current-namespace (make-base-namespace)]
                             [current-load-relative-directory dir])
                (expand (with-input-from-file file
                          (lambda () (port-count-lines! (current-input-port))
                            (parameterize ([read-accept-reader #t]) (read-syntax file))))))
              #f))
  (check-pred exn:fail:syntax? e)
  (check-regexp-match #rx"a code requires a \\(system\\) prefix to be compose-expressible: a" (exn-message e))
  (define stx (car (exn:fail:syntax-exprs e)))
  (check-equal? (list (syntax-line stx) (syntax-column stx)) '(2 0)))

(delete-directory/files dir)
