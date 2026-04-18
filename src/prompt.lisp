(in-package :hecl.editor)

(defvar *prompt-callback* nil)
(defvar *prompt-active* nil)

(defun prompt (prompt-text callback)
  (setf *prompt-callback* callback
        *prompt-active* t)
  #+lqml (hecl.qml:update-status-text prompt-text)
  #+lqml (hecl.qml:show-status-input prompt-text))

(defun cancel-prompt ()
  (cond
    (*completing*
     (completion-cancel))
    (*prompt-active*
     (setf *prompt-active* nil
           *prompt-callback* nil)
     #+lqml (hecl.qml:hide-status-input)
     #+lqml (hecl.qml:update-status-text "cancelled"))))

(defun on-minibuffer-accept (text)
  (cond
    (*completing*
     (completion-update-input text)
     (completion-accept))
    (*prompt-active*
     (let ((cb *prompt-callback*))
       (setf *prompt-active* nil
             *prompt-callback* nil)
       #+lqml (hecl.qml:hide-status-input)
       (when cb
         (handler-case (funcall cb text)
           (error (c)
             #+lqml (hecl.qml:update-status-text
                     (format nil "error: ~a" c)))))))
    (t
     (handler-case
         (let ((result (eval (read-from-string text))))
           #+lqml (hecl.qml:hide-status-input)
           #+lqml (hecl.qml:update-status-text (format nil "=> ~s" result)))
       (error (c)
         #+lqml (hecl.qml:hide-status-input)
         #+lqml (hecl.qml:update-status-text (format nil "error: ~a" c)))))))
