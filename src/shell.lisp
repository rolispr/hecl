(in-package :hecl.shell)

(defvar *repl-buffer* nil)
(defvar *history* (fset:empty-seq))
(defvar *history-index* -1)

(defun start-repl ()
  (let ((buf (hecl.buffer:make-buffer "*repl*" :content "hecl> ")))
    (setf *repl-buffer* buf)
    (let* ((snap (sento.actor:ask-s buf '(:get-snapshot) :time-out 5))
           (line (hecl.buffer:line-count snap))
           (col (length "hecl> ")))
      (sento.actor:tell buf (list :move-point (1- line) col)))
    buf))

(defun repl-eval (input)
  (setf *history* (fset:with-last *history* input))
  (setf *history-index* -1)
  (cond
    ((and (plusp (length input)) (char= (char input 0) #\!))
     (run-shell-command (subseq input 1)))
    (t (eval-lisp input))))

(defun eval-lisp (input)
  (handler-case
      (let* ((form (read-from-string input))
             (values (multiple-value-list (eval form)))
             (result (format nil "~{~s~^~%~}" values)))
        (append-output result))
    (error (c)
      (append-output (format nil "error: ~a" c)))))

(defun run-shell-command (cmd)
  (handler-case
      (let ((output (uiop:run-program cmd
                                      :output :string
                                      :error-output :string
                                      :ignore-error-status t)))
        (append-output (string-trim '(#\Newline #\Space) output)))
    (error (c)
      (append-output (format nil "shell error: ~a" c)))))

(defun append-output (text)
  (when *repl-buffer*
    (let* ((state (sento.actor:ask-s *repl-buffer* '(:get-state) :time-out 5))
           (last-line (1- (hecl.buffer:line-count-of state)))
           (last-col (length (fset:@ (hecl.buffer:lines state) last-line))))
      (sento.actor:tell *repl-buffer* (list :move-point last-line last-col))
      (sleep 0.01)
      (sento.actor:tell *repl-buffer* '(:newline))
      (sleep 0.01)
      (sento.actor:tell *repl-buffer* (list :insert text))
      (sleep 0.01)
      (sento.actor:tell *repl-buffer* '(:newline))
      (sleep 0.01)
      (sento.actor:tell *repl-buffer* (list :insert "hecl> "))
      (sleep 0.01)
      (let* ((snap2 (sento.actor:ask-s *repl-buffer* '(:get-snapshot) :time-out 5))
             (line2 (1- (hecl.buffer:line-count snap2)))
             (col2 (length "hecl> ")))
        (sento.actor:tell *repl-buffer* (list :move-point line2 col2))))))

(defun repl-submit ()
  (when *repl-buffer*
    (let* ((state (sento.actor:ask-s *repl-buffer* '(:get-state) :time-out 5))
           (last-line (1- (hecl.buffer:line-count-of state)))
           (line-text (fset:@ (hecl.buffer:lines state) last-line))
           (input (if (> (length line-text) 6) (subseq line-text 6) "")))
      (when (plusp (length input))
        (repl-eval input)))))
