#lang racket/base

;;; workspace.rkt — what VCL offers a workspace (fhir/lang/workspace): each .vcl file defines a
;;; ValueSet (canonical `<workspace canonical>/ValueSet/<file stem>`), a run expands it, and an
;;; explanation says which part of the expression admits or excludes a code.
;;;
;;; Expansion is the terminology service's `$expand` (fhir-tx, loaded when installed — it depends on
;;; vcl, so not statically): it sees the packages in context and the value sets and code systems the
;;; workspace defines. Without it, a run lists the codes the expression enumerates and says the rest
;;; could not be expanded.
;;; A Row is {system, code, display}.

(require racket/contract racket/list racket/string racket/file racket/runtime-path json
         fhir/lang/workspace
         (only-in fhir/diagnostic diagnostic loc attached-diagnostic exn:fail:diagnostic exn:fail:diagnostic? exn:fail:diagnostic-diagnostic
                  diagnostic-loc diagnostic-message loc-source loc-line loc-column)
         (only-in fhir/operation apply-operation exn:fail:operation? exn:fail:operation-outcome)
         (only-in fhir/result/result ok? ok-value err-error validation-error-message)
         (only-in "compile.rkt" vcl->compose vcl->valueset)
         (only-in "decompile.rkt" compose->vcl))

(provide (contract-out [workspace-support ws-support?]
                       ;; guide : the language guide (guide.md) a hub serves to agents (learn://vcl)
                       [guide string?]))

(define-runtime-path guide-file "guide.md")
(define guide (file->string guide-file))

(define (path-string p) (if (path? p) (path->string p) p))
(define (expression text) (string-trim (regexp-replace #px"^#lang[^\n]*" text "")))

;; valueset : workspace path|#f text -> ValueSet   raises the positioned diagnostic
(define (valueset ws path text)
  (define stem (and path (file-stem path)))
  (define r (vcl->valueset (expression text)
                           #:url (and path (file-canonical ws "ValueSet" path))
                           #:name (and stem (name-of stem))))
  (cond [(ok? r) (if stem (hash-set* (ok-value r) 'id (id-of stem) 'title stem) (ok-value r))]
        [else (define e (err-error r))
              (define d (in-file (or (attached-diagnostic e) (diagnostic 'vcl 'compile 'error (validation-error-message e) #f))
                                 (and path (path-string path))))
              (raise (exn:fail:diagnostic (validation-error-message e) (current-continuation-marks) d))]))
;; in-file : diagnostic string|#f -> diagnostic   a problem that names no file names this one (a
;; parse error, or a term a compose cannot hold, is positioned in the expression: the hub finds a
;; file's problems by their source)
(define (in-file d source)
  (define l (diagnostic-loc d))
  (cond [(or (not source) (and l (loc-source l))) d]
        [else (struct-copy diagnostic d [loc (if l (struct-copy loc l [source source]) (loc source #f #f #f #f))])]))
(define (id-of stem) (regexp-replace* #rx"[^A-Za-z0-9.-]" stem "-"))
(define (name-of stem)
  (define parts (regexp-split #rx"[^A-Za-z0-9]+" stem))
  (define n (apply string-append (for/list ([p (in-list parts)] #:unless (string=? p ""))
                                   (string-append (string-upcase (substring p 0 1)) (substring p 1)))))
  (if (regexp-match? #rx"^[A-Z]" n) n (string-append "VS" n)))

(define (artifacts ws files)
  (for/fold ([rs '()] [ds '()] #:result (values (reverse rs) ds)) ([f (in-list files)])
    (with-handlers ([exn:fail:diagnostic? (lambda (e) (values rs (append ds (list (exn:fail:diagnostic-diagnostic e)))))])
      (values (cons (valueset ws (car f) (cdr f)) rs) ds))))
(define (exn:fail:diagnostic-diagnostic e) ((dynamic-require 'fhir/diagnostic 'exn:fail:diagnostic-diagnostic) e))

;; expand : ValueSet -> (values expansion-contains expanded?)
(define (expand vs)
  (define tx? (with-handlers ([exn:fail? (lambda (_) #f)]) (dynamic-require 'fhir/terminology/operations #f) #t))
  (cond
    [tx?
     (define out (with-handlers ([exn:fail:operation? (lambda (e) (error 'vcl (format "the value set does not expand: ~a" (outcome-text (exn:fail:operation-outcome e)))))])
                   (apply-operation "$expand" vs)))
     (values (flatten-contains (hash-ref (hash-ref out 'expansion (hasheq)) 'contains '())) #t)]
    [else
     (values (for*/list ([i (in-list (hash-ref (hash-ref vs 'compose (hasheq)) 'include '()))]
                         [c (in-list (hash-ref i 'concept '()))])
               (hasheq 'system (hash-ref i 'system "") 'code (hash-ref c 'code "")))
             #f)]))
(define (flatten-contains cs)
  (append* (for/list ([c (in-list cs)]) (cons c (flatten-contains (hash-ref c 'contains '()))))))
(define (outcome-text oo)
  (string-join (for/list ([i (in-list (hash-ref oo 'issue '()))])
                 (or (hash-ref i 'diagnostics #f) (let ([d (hash-ref i 'details #f)]) (and (hash? d) (hash-ref d 'text #f))) (hash-ref i 'code "")))
               "; "))

(define (run ws path text opts)
  (define-values (contains expanded?) (expand (valueset ws path text)))
  (define rows (for/list ([c (in-list contains)] #:when (hash-ref c 'code #f))
                 (hasheq 'system (hash-ref c 'system "") 'code (hash-ref c 'code) 'display (hash-ref c 'display 'null))))
  (run-result "expansion" '("system" "code" "display") rows
              (let ([s (hasheq 'total (length rows)
                               'systems (for/hasheq ([g (in-list (group-by (lambda (r) (hash-ref r 'system)) rows))])
                                          (values (string->symbol (hash-ref (car g) 'system)) (length g))))])
                (if expanded? s (hash-set s 'note "the terminology service (fhir-tx) is not installed: only the enumerated codes are listed")))))

;; explain : the parts of the expression (each include and exclude of its compose, as VCL) and
;; whether each holds the code; a member is in some include and in no exclude
(define (explain ws path text subject opts)
  (define vs (valueset ws path text))
  (define-values (system code) (let ([m (regexp-match #px"^(.*)[|#](.+)$" subject)]) (if m (values (cadr m) (caddr m)) (values #f subject))))
  (define compose (hash-ref vs 'compose))
  (define (holds? part)
    (define-values (cs _x) (expand (hasheq 'resourceType "ValueSet" 'status "active" 'compose (hasheq 'include (list part)))))
    (for/or ([c (in-list cs)]) (and (equal? (hash-ref c 'code #f) code) (or (not system) (equal? (hash-ref c 'system #f) system)))))
  (define (parts kind) (for/list ([p (in-list (hash-ref compose kind '()))])
                         (hasheq 'part (symbol->string kind) 'vcl (compose->vcl (hasheq 'include (list p))) 'holds (holds? p))))
  (define incs (parts 'include))
  (define excs (parts 'exclude))
  (hasheq 'code code 'system (or system 'null)
          'member (and (ormap (lambda (p) (hash-ref p 'holds)) incs) (not (ormap (lambda (p) (hash-ref p 'holds)) excs)))
          'parts (append incs excs)))

(define workspace-support (ws-support "vcl" artifacts run explain))

(module+ test
  (require rackunit racket/file)
  (define dir (make-temporary-directory "vcl-ws-~a"))
  (define-values (ws _) (open-workspace dir))
  (define-values (rs ds) (artifacts ws (list (cons (build-path dir "hba1c-tests.vcl") "(http://loinc.org)(4548-4; 17856-6)")
                                             (cons (build-path dir "bad.vcl") "(http://loinc.org"))))
  (check-equal? (length rs) 1)
  (check-equal? (hash-ref (car rs) 'url) "http://example.org/workspace/ValueSet/hba1c-tests")
  (check-equal? (hash-ref (car rs) 'name) "Hba1cTests")
  (check-equal? (length ds) 1)
  ;; a problem names its file: a parse error, and a term a compose cannot hold (codes of no system)
  (define-values (_rs ds2) (artifacts ws (list (cons (build-path dir "bad.vcl") "(http://loinc.org")
                                               (cons (build-path dir "nosystem.vcl") "(http://loinc.org)4548-4; 17856-6"))))
  (check-equal? (for/list ([d (in-list ds2)])
                  (define l (diagnostic-loc d))
                  (list (let-values ([(base name dir?) (split-path (loc-source l))]) (path->string name))
                        (loc-line l) (loc-column l) (diagnostic-message d)))
                '(("bad.vcl" 1 2 "the expression ends after `http://loinc.org`")
                  ("nosystem.vcl" 1 27 "a code requires a (system) prefix to be compose-expressible: 17856-6")))
  (define r (run ws (build-path dir "hba1c-tests.vcl") "(http://loinc.org)(4548-4; 17856-6)" (hasheq)))
  (check-equal? (map (lambda (row) (hash-ref row 'code)) (run-result-rows r)) '("4548-4" "17856-6"))
  (check-equal? (hash-ref (run-result-summary r) 'total) 2)
  (define e (explain ws #f "(http://loinc.org)(4548-4; 17856-6) - (http://loinc.org)17856-6" "http://loinc.org|17856-6" (hasheq)))
  (check-false (hash-ref e 'member))
  (check-equal? (map (lambda (p) (hash-ref p 'holds)) (hash-ref e 'parts)) '(#t #t))
  (check-true (hash-ref (explain ws #f "(http://loinc.org)(4548-4; 17856-6)" "4548-4" (hasheq)) 'member))
  (delete-directory/files dir))
