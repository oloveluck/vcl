#lang racket/base

;;; cli.rkt — `raco vcl`: the command line for the VCL (ValueSet Compose Language) package.
;;;
;;;   raco vcl '<expression>'            compile a VCL expression to its ValueSet (implicit-url form)
;;;   raco vcl <file.vcl>                same, reading the (one-line) expression from a file
;;;   raco vcl --decompile <valueset.json>   print the VCL expression for a ValueSet's compose
;;; Exit codes: 0 ok · 1 VCL error · 2 usage.

(require json
         (only-in racket/file file->string)
         (only-in racket/string string-trim)
         (only-in vcl/compile vcl->valueset)
         (only-in vcl/decompile compose->vcl)
         (only-in fhir/result/result ok? ok-value err-error validation-error-message)
         (only-in fhir/diagnostic diagnostic diagnostic-loc loc attached-diagnostic emit-diagnostics format-flag))

(provide compile-expression decompile-file)

;; compile-expression : string -> void   print the ValueSet JSON for a VCL expression, or exit 1
;; report : diagnostic text -> exit 1   (format from --format)
(define current-format (make-parameter 'text))
(define (report d text)
  (emit-diagnostics (list d) #:format (current-format) #:text-of (lambda (_) text))
  (exit 1))
(define (with-source d source)
  (define l (diagnostic-loc d))
  (struct-copy diagnostic d [loc (if l (struct-copy loc l [source source]) (loc source #f #f #f #f))]))

;; compile-expression : string [source] -> void   print the ValueSet JSON for a VCL expression, or exit 1
(define (compile-expression expr [source "<expression>"])
  (define r (vcl->valueset expr))
  (unless (ok? r)
    (define e (err-error r))
    (report (with-source (or (attached-diagnostic e)
                             (diagnostic 'vcl 'compile 'error (validation-error-message e) #f))
                         source)
            expr))
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
    [(file-exists? (car args))
     ;; a .vcl file: one expression, optional #lang line, trailing newline allowed
     ;; (the #lang line is blanked, not removed, so positions stay true)
     (compile-expression (string-trim (regexp-replace #px"^#lang[^\n]*" (file->string (car args)) "") #px"\\s+$" #:left? #f)
                         (car args))]
    [else (compile-expression (car args))]))
