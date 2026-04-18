(in-package :hecl.editor)

(defvar *kill-ring* nil)
(defvar *kill-ring-max* 60)
(defvar *last-command* nil)

(defun kill-ring-push (text)
  "Push TEXT onto the kill ring. Consecutive kills concatenate."
  (when (and text (plusp (length text)))
    (if (and (member *last-command* '("kill-line" "kill-region" "kill-word"
                                      "backward-kill-word"))
             *kill-ring*)
        ;; Append to last kill
        (setf (car *kill-ring*)
              (concatenate 'string (car *kill-ring*) text))
        ;; New entry
        (progn
          (push text *kill-ring*)
          (when (> (length *kill-ring*) *kill-ring-max*)
            (setf *kill-ring* (subseq *kill-ring* 0 *kill-ring-max*)))))))

(defun kill-ring-top ()
  (car *kill-ring*))


;;;; Mark and region

(defun set-mark ()
  "Set mark at point in the current buffer."
  (let ((buf hecl.buffer:*current-buffer*))
    (when buf
      (let ((snap (hecl.buffer:current-buffer-snapshot)))
        (when snap
          (sento.actor:tell buf
            (list :set-meta :mark-line (hecl.buffer:point-line snap)))
          (sento.actor:tell buf
            (list :set-meta :mark-col (hecl.buffer:point-col snap)))
          #+lqml (hecl.qml:update-status-text "mark set"))))))

(defun region-bounds (state)
  "Return (values start-line start-col end-line end-col) or NIL if no mark."
  (let* ((m (hecl.buffer:meta state))
         (ml (fset:@ m :mark-line))
         (mc (fset:@ m :mark-col))
         (snap (hecl.buffer:state->snapshot state))
         (pl (hecl.buffer:point-line snap))
         (pc (hecl.buffer:point-col snap)))
    (when (and ml mc)
      (if (or (< ml pl) (and (= ml pl) (<= mc pc)))
          (values ml mc pl pc)
          (values pl pc ml mc)))))


;;;; Kill commands

(defun kill-region-cmd ()
  "Kill text between mark and point."
  (let ((buf hecl.buffer:*current-buffer*))
    (when buf
      (let ((state (sento.actor:ask-s buf '(:get-state) :time-out 5)))
        (multiple-value-bind (sl sc el ec) (region-bounds state)
          (when sl
            (let ((text (hecl.buffer:region-string state sl sc el ec)))
              (kill-ring-push text)
              (sento.actor:tell buf (list :delete-region sl sc el ec)))))))))

(defun kill-line-cmd ()
  "Kill from point to end of line. If at end, kill the newline."
  (let ((buf hecl.buffer:*current-buffer*))
    (when buf
      (let* ((snap (hecl.buffer:current-buffer-snapshot))
             (pl (hecl.buffer:point-line snap))
             (pc (hecl.buffer:point-col snap))
             (line (fset:@ (hecl.buffer:lines snap) pl))
             (len (length line)))
        (if (< pc len)
            ;; Kill to end of line
            (let ((text (subseq line pc)))
              (kill-ring-push text)
              (sento.actor:tell buf (list :delete-region pl pc pl len)))
            ;; At end of line: kill the newline (join with next line)
            (when (< (1+ pl) (hecl.buffer:line-count snap))
              (kill-ring-push (string #\Newline))
              (sento.actor:tell buf (list :delete-region pl pc (1+ pl) 0))))))))

(defun yank-cmd ()
  "Insert the top of the kill ring at point."
  (let ((text (kill-ring-top)))
    (when (and text hecl.buffer:*current-buffer*)
      (sento.actor:tell hecl.buffer:*current-buffer* (list :insert text)))))

(defun yank-pop-cmd ()
  "Replace the last yank with the next kill ring entry."
  (when (and (string= *last-command* "yank") (cdr *kill-ring*))
    ;; Rotate the ring
    (let ((top (pop *kill-ring*)))
      (setf *kill-ring* (append *kill-ring* (list top)))
      ;; TODO: need to track yank region to replace it
      ;; For now, just yank the new top
      (let ((text (kill-ring-top)))
        (when (and text hecl.buffer:*current-buffer*)
          (sento.actor:tell hecl.buffer:*current-buffer* (list :insert text)))))))

(defun copy-region-cmd ()
  "Copy text between mark and point to kill ring (don't delete)."
  (let ((buf hecl.buffer:*current-buffer*))
    (when buf
      (let ((state (sento.actor:ask-s buf '(:get-state) :time-out 5)))
        (multiple-value-bind (sl sc el ec) (region-bounds state)
          (when sl
            (let ((text (hecl.buffer:region-string state sl sc el ec)))
              (kill-ring-push text)
              #+lqml (hecl.qml:update-status-text "copied"))))))))
