(in-package :hecl.file)

(defun read-file (path)
  (with-open-file (s path :direction :input :if-does-not-exist nil)
    (when s
      (with-output-to-string (out)
        (loop for line = (read-line s nil nil)
              while line
              do (write-string line out)
                 (write-char #\Newline out))))))

(defun write-file (path text)
  (with-open-file (s path :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (write-string text s))
  path)

(defun find-file (path)
  (let* ((expanded (merge-pathnames path))
         (exists (probe-file expanded))
         (namestring (namestring expanded))
         (name (file-namestring expanded))
         (content (if exists (or (read-file expanded) "") "")))
    (when (string= name "") (setf name namestring))
    (let ((buf (hecl.buffer:make-buffer name :content content)))
      (sento.actor:tell buf (list :set-meta :pathname namestring))
      (sento.actor:tell buf (list :move-point 0 0))
      (hecl.buffer:switch-buffer name)
      (sento.actor:tell hecl.render:*renderer*
                        (list :switch-buffer buf name))
      (hecl.render:subscribe-to-buffer buf)
      #+lqml (hecl.qml:update-status-text
              (if exists (format nil "~a" namestring)
                  (format nil "(new file) ~a" namestring)))
      buf)))

(defun save-current-buffer ()
  (let ((buf hecl.buffer:*current-buffer*))
    (when buf
      (let* ((state (sento.actor:ask-s buf '(:get-state) :time-out 5))
             (path (fset:@ (hecl.buffer:meta state) :pathname))
             (text (hecl.buffer:state->string state)))
        (if path
            (progn
              (write-file path text)
              #+lqml (hecl.qml:update-status-text (format nil "wrote ~a" path)))
            #+lqml (hecl.qml:update-status-text "no file path for this buffer"))))))
