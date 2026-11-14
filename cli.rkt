#lang racket/base

;;; cli.rkt — `raco vcl`: the command line for the VCL (ValueSet Compose Language) package.
;;;
;;;   raco vcl '<expression>'            compile a VCL expression to its ValueSet (implicit-url form)
;;;   raco vcl <file.vcl>                same, reading the (one-line) expression from a file. The
;;;                                      argument is a file when one of that name exists, or when it
;;;                                      can only be meant as one (`file-like?`): then a file that is
;;;                                      not there is "cannot read", exit 2, not an expression
;;;   raco vcl --decompile <valueset.json>   print the VCL expression for a ValueSet's compose
;;; Exit codes: 0 ok · 1 VCL error · 2 usage.

(require json
         (only-in racket/file file->string)
         (only-in vcl/compile vcl->valueset)
         (only-in vcl/decompile compose->vcl)
         (only-in vcl/text file-expression in-file-text with-file)
         (only-in fhir/result/result ok? ok-value err-error validation-error-message)
         (only-in fhir/diagnostic diagnostic attached-diagnostic emit-diagnostics format-flag))

(provide compile-expression decompile-file file-like?)

;; file-like? : string -> boolean   an argument that can only be meant as a file: it ends in `.vcl`
;; or has a `/`, and has none of the characters an expression with either needs (a system's or a
;; group's brackets, `^` before a value set's url, the quotes of a regex after `/`). `nothere.vcl`
;; used to be compiled as the expression "code nothere, its property vcl", exit 0.
(define (file-like? arg)
  (and (or (regexp-match? #rx"(?i:[.]vcl)$" arg) (regexp-match? #rx"/" arg))
       (not (regexp-match? #rx"[][(){};,=<>^?*\"~!|]" arg))))

;; report : diagnostic text -> exit 1   (format from --format)
(define current-format (make-parameter 'text))
(define (report d text)
  (emit-diagnostics (list d) #:format (current-format) #:text-of (lambda (_) text))
  (exit 1))

;; compile-expression : string [source] [#:file-text t] -> void   print the ValueSet JSON for a VCL
;; expression, or exit 1. Given the text of the file it came from (a `#lang vcl` line, blank lines,
;; indentation before it: text.rkt), a diagnostic is moved back to its place there.
(define (compile-expression expr [source "<expression>"] #:file-text [file-text #f])
  (define r (vcl->valueset expr))
  (unless (ok? r)
    (define e (err-error r))
    (define d (or (attached-diagnostic e) (diagnostic 'vcl 'compile 'error (validation-error-message e) #f)))
    (report (with-file (if file-text (in-file-text d file-text) d) source) (or file-text expr)))
  (displayln (jsexpr->string (ok-value r))))

;; decompile-file : path-string -> void   print the VCL for a ValueSet (or a bare compose) JSON file
(define (decompile-file file)
  (define js (call-with-input-file file read-json))
  (define compose (if (and (hash? js) (hash-has-key? js 'compose)) (hash-ref js 'compose) js))
  (displayln (compose->vcl compose)))

(define (usage [code 2])                             ; --help: stdout, exit 0
  ((if (zero? code) printf eprintf) "usage: raco vcl '<expression>' | <file.vcl>\n       raco vcl --decompile <valueset.json>\n")
  (exit code))

(module+ main
  (define-values (fmt args) (format-flag (vector->list (current-command-line-arguments))))
  (current-format fmt)
  ;; an unreadable input file is a one-line error (exit 2), not a stack trace
  (let ([default (uncaught-exception-handler)])
    (uncaught-exception-handler
     (lambda (e)
       (cond [(exn:fail:filesystem? e)
              (define m (regexp-match #px"path: ([^\n]*)" (exn-message e)))
              (eprintf "vcl: cannot read ~a\n" (if m (cadr m) (exn-message e)))
              (exit 2)]
             [else (default e)]))))
  (cond
    [(ormap (lambda (a) (member a '("-h" "--help"))) args) (usage 0)]
    [(null? args) (usage)]
    [(equal? (car args) "--decompile") (if (= (length args) 2) (decompile-file (cadr args)) (usage))]
    [(regexp-match? #rx"^-" (car args)) (usage)]
    [(or (file-exists? (car args)) (file-like? (car args)))
     ;; a .vcl file: one expression, perhaps after a #lang line and blank lines (text.rkt); a
     ;; file-like argument with no file fails to open: the handler above, exit 2
     (define text (file->string (car args)))
     (compile-expression (file-expression text) (car args) #:file-text text)]
    [else (compile-expression (car args))]))

(module+ test
  (require rackunit)
  ;; a file name, whether or not the file is there
  (check-true (file-like? "nothere.vcl"))
  (check-true (file-like? "sets/hba1c.VCL"))
  (check-true (file-like? "./hba1c"))
  (check-true (file-like? "/tmp/sets/hba1c.txt"))
  ;; expressions, the ones with a `.vcl` or a `/` in them included
  (check-false (file-like? "(http://loinc.org)(4548-4; 17856-6)"))
  (check-false (file-like? "^http://hl7.org/fhir/ValueSet/administrative-gender"))
  (check-false (file-like? "(http://loinc.org)COMPONENT/\".*Dichloroethane.*\""))
  (check-false (file-like? "(http://example.org/cs)panadol.vcl"))        ; the property `vcl` of a code
  (check-false (file-like? "B.codeprop"))
  (check-false (file-like? "a;b"))
  (check-false (file-like? "B")))
