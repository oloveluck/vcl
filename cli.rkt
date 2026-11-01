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
         (only-in fhir/result/result ok? ok-value err-error validation-error-message))

(provide compile-expression decompile-file)

;; compile-expression : string -> void   print the ValueSet JSON for a VCL expression, or exit 1
(define (compile-expression expr)
  (define r (vcl->valueset expr))
  (unless (ok? r) (eprintf "vcl: ~a\n" (validation-error-message (err-error r))) (exit 1))
  (displayln (jsexpr->string (ok-value r))))

;; decompile-file : path-string -> void   print the VCL for a ValueSet (or a bare compose) JSON file
(define (decompile-file file)
  (define js (call-with-input-file file read-json))
  (define compose (if (and (hash? js) (hash-has-key? js 'compose)) (hash-ref js 'compose) js))
  (displayln (compose->vcl compose)))

(define (usage)
  (eprintf "usage: raco vcl '<expression>' | <file.vcl>\n       raco vcl --decompile <valueset.json>\n")
  (exit 2))

(module+ main
  (define args (vector->list (current-command-line-arguments)))
  (cond
    [(null? args) (usage)]
    [(equal? (car args) "--decompile") (if (= (length args) 2) (decompile-file (cadr args)) (usage))]
    [(regexp-match? #rx"^-" (car args)) (usage)]
    [(file-exists? (car args))
     ;; a .vcl file: one expression, optional #lang line, trailing newline allowed
     (compile-expression (string-trim (regexp-replace #px"^#lang[^\n]*\n" (file->string (car args)) "")))]
    [else (compile-expression (car args))]))
