;;; lang/emacs-lisp/autoload.el -*- lexical-binding: t; -*-

;;
;;; Library

;;;###autoload
(defun +emacs-lisp-eval (beg end)
  "Evaluate a region and print it to the echo area (if one line long), otherwise
to a pop up buffer."
  (require 'pp)
  (let ((debug-on-error t)
        (buffer-file-name (buffer-file-name (buffer-base-buffer)))
        (doom--current-module (ignore-errors (doom-module-from-path buffer-file-name)))
        (temp-buffer-show-hook
         (cons (if (fboundp '+word-wrap-mode)
                   '+word-wrap-mode
                 'visual-line-mode)
               temp-buffer-show-hook)))
    (when-let (buffer (get-buffer "*Pp Eval Output*"))
      (kill-buffer buffer))
    (pp-eval-expression
     (read (buffer-substring-no-properties beg end)))))

(defvar +emacs-lisp--face nil)
;;;###autoload
(defun +emacs-lisp-highlight-vars-and-faces (end)
  "Match defined variables and functions.

Functions are differentiated into special forms, built-in functions and
library/userland functions"
  (catch 'matcher
    (while (re-search-forward "\\(?:\\sw\\|\\s_\\)+" end t)
      (let ((ppss (save-excursion (syntax-ppss))))
        (cond ((nth 3 ppss)  ; strings
               (search-forward "\"" end t))
              ((nth 4 ppss)  ; comments
               (forward-line +1))
              ((let ((symbol (intern-soft (match-string-no-properties 0))))
                 (and (cond ((null symbol) nil)
                            ((eq symbol t) nil)
                            ((special-variable-p symbol)
                             (setq +emacs-lisp--face 'font-lock-variable-name-face))
                            ((and (fboundp symbol)
                                  (eq (char-before (match-beginning 0)) ?\()
                                  (not (memq (char-before (1- (match-beginning 0)))
                                             (list ?\' ?\`))))
                             (let ((unaliased (indirect-function symbol)))
                               (unless (or (macrop unaliased)
                                           (special-form-p unaliased))
                                 (let (unadvised)
                                   (while (not (eq (setq unadvised (ad-get-orig-definition unaliased))
                                                   (setq unaliased (indirect-function unadvised)))))
                                   unaliased)
                                 (setq +emacs-lisp--face
                                       (if (subrp unaliased)
                                           'font-lock-constant-face
                                         'font-lock-function-name-face))))))
                      (throw 'matcher t)))))))
    nil))

;; `+emacs-lisp-highlight-vars-and-faces' is a potentially expensive function
;; and should be byte-compiled, no matter what, to ensure it runs as fast as
;; possible:
(unless (byte-code-function-p (symbol-function '+emacs-lisp-highlight-vars-and-faces))
  (with-no-warnings
    (byte-compile #'+emacs-lisp-highlight-vars-and-faces)))

;;;###autoload
(defun +emacs-lisp-lookup-documentation (thing)
  "Lookup THING with `helpful-variable' if it's a variable, `helpful-callable'
if it's callable, `apropos' otherwise."
  (if thing
      (doom/describe-symbol thing)
    (call-interactively #'doom/describe-symbol)))


;;
;;; Commands

;;;###autoload
(defun +emacs-lisp/open-repl ()
  "Open the Emacs Lisp REPL (`ielm')."
  (interactive)
  (pop-to-buffer
   (or (get-buffer "*ielm*")
       (progn (ielm)
              (let ((buf (get-buffer "*ielm*")))
                (bury-buffer buf)
                buf)))))

;;;###autoload
(defun +emacs-lisp/buttercup-run-file ()
  "Run all buttercup tests in the focused buffer."
  (interactive)
  (let ((load-path (append (list (doom-path (dir!) "..")
                                 (or (doom-project-root)
                                     default-directory))
                           load-path)))
    (save-selected-window
      (eval-buffer)
      (buttercup-run))
    (message "File executed successfully")))

;;;###autoload
(defun +emacs-lisp/buttercup-run-project ()
  "Run all buttercup tests in the project."
  (interactive)
  (let* ((default-directory (doom-project-root))
         (load-path (append (list (doom-path "test")
                                  default-directory)
                            load-path)))
    (buttercup-run-discover)))


;;
;;; Hooks

;;;###autoload
(defun +emacs-lisp-extend-imenu-h ()
  "Improve imenu support in `emacs-lisp-mode', including recognition for Doom's API."
  (setq imenu-generic-expression
        `(("Section" "^[ \t]*;;;;*[ \t]+\\([^\n]+\\)" 1)
          ("Evil commands" "^\\s-*(evil-define-\\(?:command\\|operator\\|motion\\) +\\(\\_<[^ ()\n]+\\_>\\)" 1)
          ("Unit tests" "^\\s-*(\\(?:ert-deftest\\|describe\\) +\"\\([^\")]+\\)\"" 1)
          ("Package" "^\\s-*(\\(?:;;;###package\\|package!\\|use-package!?\\|after!\\) +\\(\\_<[^ ()\n]+\\_>\\)" 1)
          ("Major modes" "^\\s-*(define-derived-mode +\\([^ ()\n]+\\)" 1)
          ("Minor modes" "^\\s-*(define-\\(?:global\\(?:ized\\)?-minor\\|generic\\|minor\\)-mode +\\([^ ()\n]+\\)" 1)
          ("Modelines" "^\\s-*(def-modeline! +\\([^ ()\n]+\\)" 1)
          ("Modeline segments" "^\\s-*(def-modeline-segment! +\\([^ ()\n]+\\)" 1)
          ("Advice" "^\\s-*(\\(?:def\\(?:\\(?:ine\\)?-advice\\)\\) +\\([^ )\n]+\\)" 1)
          ("Macros" "^\\s-*(\\(?:cl-\\)?def\\(?:ine-compile-macro\\|macro\\) +\\([^ )\n]+\\)" 1)
          ("Inline functions" "\\s-*(\\(?:cl-\\)?defsubst +\\([^ )\n]+\\)" 1)
          ("Functions" "^\\s-*(\\(?:cl-\\)?def\\(?:un\\|un\\*\\|method\\|generic\\|-memoized!\\) +\\([^ ,)\n]+\\)" 1)
          ("Variables" "^\\s-*(\\(def\\(?:c\\(?:onst\\(?:ant\\)?\\|ustom\\)\\|ine-symbol-macro\\|parameter\\|var\\(?:-local\\)?\\)\\)\\s-+\\(\\(?:\\sw\\|\\s_\\|\\\\.\\)+\\)" 2)
          ("Types" "^\\s-*(\\(cl-def\\(?:struct\\|type\\)\\|def\\(?:class\\|face\\|group\\|ine-\\(?:condition\\|error\\|widget\\)\\|package\\|struct\\|t\\(?:\\(?:hem\\|yp\\)e\\)\\)\\)\\s-+'?\\(\\(?:\\sw\\|\\s_\\|\\\\.\\)+\\)" 2))))

;;;###autoload
(defun +emacs-lisp-reduce-flycheck-errors-in-emacs-config-h ()
  "Remove `emacs-lisp-checkdoc' checker and reduce `emacs-lisp' checker
verbosity when editing a file in `doom-private-dir' or `doom-emacs-dir'."
  (when (and (bound-and-true-p flycheck-mode)
             (eq major-mode 'emacs-lisp-mode)
             (or (not buffer-file-name)
                 (cl-loop for dir in (list doom-emacs-dir doom-private-dir)
                          if (file-in-directory-p buffer-file-name dir)
                          return t)))
    (add-to-list (make-local-variable 'flycheck-disabled-checkers)
                 'emacs-lisp-checkdoc)
    (set (make-local-variable 'flycheck-emacs-lisp-check-form)
         (concat "(progn "
                 (prin1-to-string
                  `(progn
                     (setq doom-modules ',doom-modules
                           doom-disabled-packages ',doom-disabled-packages)
                     (ignore-errors (load ,user-init-file t t))
                     (setq byte-compile-warnings
                           '(obsolete cl-functions
                             interactive-only make-local mapcar
                             suspicious constants))
                     (defmacro map! (&rest _))))
                 " "
                 (default-value 'flycheck-emacs-lisp-check-form)
                 ")"))))

;;;###autoload
(defun +emacs-lisp/edebug-instrument-defun-on ()
  "Toggle on instrumentalisation for the function under `defun'."
  (interactive)
  (eval-defun 'edebugit))

;;;###autoload
(defun +emacs-lisp/edebug-instrument-defun-off ()
  "Toggle off instrumentalisation for the function under `defun'."
  (interactive)
  (eval-defun nil))
