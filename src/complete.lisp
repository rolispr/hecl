(in-package :hecl.editor)

(defvar *completing* nil)
(defvar *completion-candidates* nil)
(defvar *completion-filtered* nil)
(defvar *completion-index* -1)
(defvar *completion-input* "")
(defvar *completion-callback* nil)

(defun substring-match-p (input candidate)
  (search (string-downcase input) (string-downcase candidate)))

(defun filter-candidates (input candidates)
  (if (string= input "")
      candidates
      (remove-if-not (lambda (c) (substring-match-p input c)) candidates)))

(defun completing-read (prompt-text candidates callback)
  (setf *completing* t
        *completion-candidates* candidates
        *completion-input* ""
        *completion-index* (if candidates 0 -1)
        *completion-callback* callback
        *completion-filtered* (filter-candidates "" candidates))
  (show-completions)
  #+lqml (hecl.qml:show-status-input prompt-text))

(defun completion-accept ()
  (let ((result (if (and (>= *completion-index* 0)
                         (< *completion-index* (length *completion-filtered*)))
                    (nth *completion-index* *completion-filtered*)
                    *completion-input*))
        (cb *completion-callback*))
    (completion-cleanup)
    (when cb
      (handler-case (funcall cb result)
        (error (c)
          #+lqml (hecl.qml:update-status-text (format nil "error: ~a" c)))))))

(defun completion-cancel ()
  (completion-cleanup)
  #+lqml (hecl.qml:update-status-text "cancelled"))

(defun completion-cleanup ()
  (setf *completing* nil
        *completion-candidates* nil
        *completion-filtered* nil
        *completion-index* -1
        *completion-input* ""
        *completion-callback* nil)
  #+lqml (hecl.qml:hide-completion-area)
  #+lqml (hecl.qml:hide-status-input))

(defun completion-next ()
  (when *completion-filtered*
    (setf *completion-index*
          (min (1+ *completion-index*) (1- (length *completion-filtered*))))
    (show-completions)))

(defun completion-prev ()
  (when *completion-filtered*
    (setf *completion-index* (max 0 (1- *completion-index*)))
    (show-completions)))

(defun completion-update-input (text)
  (setf *completion-input* text
        *completion-filtered* (filter-candidates text *completion-candidates*)
        *completion-index* (if *completion-filtered* 0 -1))
  (show-completions))

(defun show-completions ()
  #+lqml
  (let* ((max-visible 12)
         (filtered *completion-filtered*)
         (n (length filtered))
         (idx *completion-index*)
         (visible (subseq filtered 0 (min max-visible n)))
         (lines (loop for c in visible
                      for i from 0
                      collect (if (= i idx)
                                  (format nil "> ~a" c)
                                  (format nil "  ~a" c)))))
    (if lines
        (hecl.qml:show-completion-area
         (format nil "~{~a~^~%~}" lines))
        (hecl.qml:show-completion-area "(no matches)"))))

(defun completing-read-active-p ()
  *completing*)
