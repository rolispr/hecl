(in-package :hecl.editor)

(defvar *commands* (make-hash-table :test 'equal))
(defvar *global-keymap* (make-hash-table :test 'equal))
(defvar *pending-keys* nil)
(defvar *mode* :insert)

(defun key-id (key modifiers)
  (cons (truncate key) (truncate modifiers)))

(defun register-command (name fn)
  (setf (gethash name *commands*) fn))

(defmacro defcommand (name args &body body)
  `(register-command ,name (lambda ,args ,@body)))

(defun bind-key (command-name &rest key-specs)
  (let ((table *global-keymap*))
    (loop for (key mods) on key-specs by #'cddr
          for remaining = (cddr (member key key-specs))
          for id = (key-id key mods)
          do (if (null remaining)
                 (setf (gethash id table) command-name)
                 (let ((next (gethash id table)))
                   (unless (hash-table-p next)
                     (setf next (make-hash-table :test 'equal))
                     (setf (gethash id table) next))
                   (setf table next))))))

(defun bind-key-simple (command-name key &optional (mods 0))
  (setf (gethash (key-id key mods) *global-keymap*) command-name))

(defun bind-key-seq (command-name key1 mods1 key2 mods2)
  (let ((id1 (key-id key1 mods1))
        (id2 (key-id key2 mods2)))
    (let ((sub (gethash id1 *global-keymap*)))
      (unless (hash-table-p sub)
        (setf sub (make-hash-table :test 'equal))
        (setf (gethash id1 *global-keymap*) sub))
      (setf (gethash id2 sub) command-name))))

(defun run-command (name)
  (let ((fn (gethash name *commands*)))
    (when fn
      (handler-case (progn (funcall fn) (setf *last-command* name))
        (error (c)
          #+lqml (hecl.qml:update-status-text (format nil "error: ~a" c)))))))

(defconstant +ctrl+  #x04000000)
(defconstant +meta+  #x10000000)
(defconstant +alt+   #x08000000)
(defconstant +shift+ #x02000000)

(defun dispatch-key (key modifiers text)
  (handler-case
      (let* ((mods (truncate (or modifiers 0)))
             (id (key-id key mods)))
        ;; C-g / Escape always cancels
        (when (or (equal id (key-id 71 +ctrl+))      ; C-g
                  (equal id (key-id 16777216 0)))     ; Escape
          (setf *pending-keys* nil)
          (cancel-prompt)
          (return-from dispatch-key))

        ;; C-n / C-p during completion
        (when (completing-read-active-p)
          (cond
            ((equal id (key-id 78 +ctrl+)) ; C-n
             (completion-next)
             (return-from dispatch-key))
            ((equal id (key-id 80 +ctrl+)) ; C-p
             (completion-prev)
             (return-from dispatch-key))))

        ;; Terminal buffer: forward ALL keys to PTY unless it's a C-x chord
        (let ((term (when hecl.buffer:*current-buffer*
                      (hecl.term:terminal-for-buffer
                       hecl.buffer:*current-buffer*))))
          (when (and term (not *pending-keys*))
            ;; C-x prefix starts a chord even in terminal mode
            (let ((entry (gethash id *global-keymap*)))
              (when (hash-table-p entry)
                (setf *pending-keys* entry)
                #+lqml (hecl.qml:update-status-text "C-x ...")
                (return-from dispatch-key)))
            ;; M-x opens command palette even in terminal
            (let ((entry (gethash id *global-keymap*)))
              (when (and (stringp entry) (string= entry "execute-command"))
                (setf *pending-keys* nil)
                (run-command entry)
                (return-from dispatch-key)))
            ;; Everything else → PTY
            (cond
              ;; Ctrl+letter → control character
              ((and (plusp (logand mods +ctrl+))
                    (>= key 65) (<= key 90))
               (hecl.term:terminal-send-key
                (string (code-char (- key 64)))))
              ;; Printable text
              ((and text (plusp (length text)))
               (hecl.term:terminal-send-key text))
              ;; Special keys (enter, backspace, arrows, etc.)
              (t (hecl.term:terminal-send-special key mods)))
            (return-from dispatch-key)))

        ;; Normal (non-terminal) key dispatch
        (let* ((table (if *pending-keys* *pending-keys* *global-keymap*))
               (entry (gethash id table)))
          (cond
            ((hash-table-p entry)
             (setf *pending-keys* entry)
             #+lqml (hecl.qml:update-status-text "C-x ..."))
            ((stringp entry)
             (setf *pending-keys* nil)
             (run-command entry))
            (t
             (setf *pending-keys* nil)
             (when (and hecl.buffer:*current-buffer*
                        (eq *mode* :insert) text (plusp (length text))
                        (graphic-char-p (char text 0))
                        (zerop (logand mods +ctrl+))
                        (zerop (logand mods +meta+)))
               (sento.actor:tell hecl.buffer:*current-buffer*
                                  (list :insert text)))))))
    (error (c)
      (setf *pending-keys* nil)
      #+lqml (hecl.qml:update-status-text (format nil "error: ~a" c)))))

(defun on-key (key modifiers text)
  (dispatch-key key modifiers text))

(defun setup-default-bindings ()
  ;; Basic editing
  (defcommand "backspace" ()
    (when hecl.buffer:*current-buffer*
      (sento.actor:tell hecl.buffer:*current-buffer* '(:backspace))))

  (defcommand "delete-char" ()
    (when hecl.buffer:*current-buffer*
      (let ((snap (focused-snap)))
        (when snap
          (sento.actor:tell hecl.buffer:*current-buffer*
            (list :delete-region
                  (hecl.buffer:point-line snap)
                  (hecl.buffer:point-col snap)
                  (hecl.buffer:point-line snap)
                  (1+ (hecl.buffer:point-col snap))))))))

  (defcommand "newline" ()
    (when hecl.buffer:*current-buffer*
      (if (and (boundp 'hecl.shell::*repl-buffer*)
               (eq hecl.buffer:*current-buffer* hecl.shell:*repl-buffer*))
          (hecl.shell:repl-submit)
          (sento.actor:tell hecl.buffer:*current-buffer* '(:newline)))))

  (defcommand "undo" ()
    (when hecl.buffer:*current-buffer*
      (sento.actor:tell hecl.buffer:*current-buffer* '(:undo))))

  ;; Movement — arrows
  (defcommand "move-up" () (move-point-up))
  (defcommand "move-down" () (move-point-down))
  (defcommand "move-left" () (move-point-left))
  (defcommand "move-right" () (move-point-right))

  ;; Movement — Emacs keys
  (defcommand "forward-char" () (move-point-right))
  (defcommand "backward-char" () (move-point-left))
  (defcommand "next-line" () (move-point-down))
  (defcommand "previous-line" () (move-point-up))

  (defcommand "beginning-of-line" ()
    (when hecl.buffer:*current-buffer*
      (let ((snap (focused-snap)))
        (when snap
          (sento.actor:tell hecl.buffer:*current-buffer*
            (list :move-point (hecl.buffer:point-line snap) 0))))))

  (defcommand "end-of-line" ()
    (when hecl.buffer:*current-buffer*
      (let ((snap (focused-snap)))
        (when snap
          (let ((len (length (fset:@ (hecl.buffer:lines snap)
                                     (hecl.buffer:point-line snap)))))
            (sento.actor:tell hecl.buffer:*current-buffer*
              (list :move-point (hecl.buffer:point-line snap) len)))))))

  (defcommand "beginning-of-buffer" ()
    (when hecl.buffer:*current-buffer*
      (sento.actor:tell hecl.buffer:*current-buffer*
        (list :move-point 0 0))))

  (defcommand "end-of-buffer" ()
    (when hecl.buffer:*current-buffer*
      (let ((snap (focused-snap)))
        (when snap
          (let* ((last-line (1- (hecl.buffer:line-count snap)))
                 (last-col (length (fset:@ (hecl.buffer:lines snap) last-line))))
            (sento.actor:tell hecl.buffer:*current-buffer*
              (list :move-point last-line last-col)))))))

  ;; Scrolling
  (defcommand "scroll-down" ()
    (let ((w hecl.buffer:*focused-window*))
      (when w (scroll-window (- (hecl.buffer:win-height w) 2)))))

  (defcommand "scroll-up" ()
    (let ((w hecl.buffer:*focused-window*))
      (when w (scroll-window (- 2 (hecl.buffer:win-height w))))))

  (defcommand "scroll-down-line" ()
    (scroll-window 3))

  (defcommand "scroll-up-line" ()
    (scroll-window -3))

  ;; Mark and region
  (defcommand "set-mark" () (set-mark))

  ;; Kill ring
  (defcommand "kill-line" () (kill-line-cmd))
  (defcommand "kill-region" () (kill-region-cmd))
  (defcommand "copy-region" () (copy-region-cmd))
  (defcommand "yank" () (yank-cmd))
  (defcommand "yank-pop" () (yank-pop-cmd))

  ;; File operations
  (defcommand "find-file" ()
    (prompt "Find file: "
      (lambda (path)
        (handler-case (hecl.file:find-file path)
          (error (c)
            #+lqml (hecl.qml:update-status-text (format nil "error: ~a" c)))))))

  (defcommand "save-file" ()
    (handler-case (hecl.file:save-current-buffer)
      (error (c)
        #+lqml (hecl.qml:update-status-text (format nil "error: ~a" c)))))

  ;; Buffer operations
  (defcommand "switch-buffer" ()
    (completing-read "Switch to: "
      (hecl.buffer:list-buffers)
      (lambda (name)
        (let ((buf (hecl.buffer:switch-buffer name)))
          (when buf
            (sento.actor:tell hecl.render:*renderer*
                              (list :switch-buffer buf name))
            (hecl.render:subscribe-to-buffer buf))))))

  (defcommand "list-buffers" ()
    #+lqml (hecl.qml:update-status-text
     (format nil "buffers: ~{~a~^, ~}" (hecl.buffer:list-buffers))))

  (defcommand "execute-command" ()
    (let ((names (sort (loop for k being the hash-keys of *commands* collect k)
                       #'string<)))
      (completing-read "M-x "
        names
        (lambda (name) (run-command name)))))

  (defcommand "eval-expression" ()
    (prompt "Eval: "
      (lambda (text)
        (handler-case
            (let ((result (eval (read-from-string text))))
              #+lqml (hecl.qml:update-status-text (format nil "=> ~s" result)))
          (error (c)
            #+lqml (hecl.qml:update-status-text (format nil "error: ~a" c)))))))

  (defcommand "new-buffer" ()
    (prompt "New buffer: "
      (lambda (name)
        (let ((buf (hecl.buffer:make-buffer name)))
          (hecl.render:subscribe-to-buffer buf)))))

  (defcommand "open-terminal" ()
    (handler-case (hecl.term:open-terminal)
      (error (c)
        #+lqml (hecl.qml:update-status-text (format nil "error: ~a" c)))))

  (defcommand "open-repl" ()
    (handler-case
        (let ((buf (or hecl.shell:*repl-buffer*
                       (hecl.shell:start-repl))))
          (hecl.buffer:switch-buffer "*repl*")
          (hecl.render:subscribe-to-buffer buf)
          (sento.actor:tell hecl.render:*renderer*
                            (list :switch-buffer buf "*repl*")))
      (error (c)
        #+lqml (hecl.qml:update-status-text (format nil "error: ~a" c)))))

  ;; Key bindings — special keys
  (bind-key-simple "backspace" 16777219)
  (bind-key-simple "newline" 16777220)
  (bind-key-simple "move-up" 16777235)
  (bind-key-simple "move-down" 16777237)
  (bind-key-simple "move-left" 16777234)
  (bind-key-simple "move-right" 16777236)

  ;; Emacs movement
  (bind-key-simple "forward-char" 70 +ctrl+)      ; C-f
  (bind-key-simple "backward-char" 66 +ctrl+)     ; C-b
  (bind-key-simple "next-line" 78 +ctrl+)          ; C-n
  (bind-key-simple "previous-line" 80 +ctrl+)      ; C-p
  (bind-key-simple "beginning-of-line" 65 +ctrl+)  ; C-a
  (bind-key-simple "end-of-line" 69 +ctrl+)        ; C-e
  (bind-key-simple "delete-char" 68 +ctrl+)        ; C-d

  ;; M-< / M-> for beginning/end of buffer
  (bind-key-simple "beginning-of-buffer" 60 +meta+)  ; M-<
  (bind-key-simple "end-of-buffer" 62 +meta+)        ; M->

  ;; C-SPC — set mark
  (bind-key-simple "set-mark" 32 +ctrl+)

  ;; C-k — kill line
  (bind-key-simple "kill-line" 75 +ctrl+)

  ;; C-w — kill region
  (bind-key-simple "kill-region" 87 +ctrl+)

  ;; M-w — copy region
  (bind-key-simple "copy-region" 87 +meta+)

  ;; C-y — yank
  (bind-key-simple "yank" 89 +ctrl+)

  ;; M-y — yank-pop
  (bind-key-simple "yank-pop" 89 +meta+)

  ;; Scrolling — C-v / M-v (Emacs page scroll)
  (bind-key-simple "scroll-down" 86 +ctrl+)   ; C-v
  (bind-key-simple "scroll-up" 86 +meta+)     ; M-v
  ;; Page Up / Page Down keys
  (bind-key-simple "scroll-up" 16777238)       ; Qt::Key_PageUp
  (bind-key-simple "scroll-down" 16777239)     ; Qt::Key_PageDown

  ;; C-x chords
  (bind-key-seq "find-file" 88 +ctrl+ 70 +ctrl+)
  (bind-key-seq "save-file" 88 +ctrl+ 83 +ctrl+)
  (bind-key-seq "switch-buffer" 88 +ctrl+ 66 0)
  (bind-key-seq "new-buffer" 88 +ctrl+ 78 0)
  ;; list-buffers available via M-x
  (bind-key-simple "undo" 90 +ctrl+)

  ;; M-x — execute command by name
  (bind-key-simple "execute-command" 88 +meta+)

  ;; C-x r — open repl
  (bind-key-seq "open-repl" 88 +ctrl+ 82 0))
