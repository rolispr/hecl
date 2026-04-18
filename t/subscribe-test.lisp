(load (merge-pathnames "../init.lisp" *load-truename*))
(asdf:load-system :hecl)
(hecl:main :workers 2 :remoting-port nil)

(format t "~%=== subscription test ===~%~%")

(defvar *received-snapshots* nil)

(let ((buf hecl.buffer:*current-buffer*))
  (sento.actor:ask-s buf
    (list :subscribe
          (lambda (snap)
            (push (hecl.buffer:tick snap) *received-snapshots*)))
    :time-out 5)

  (sento.actor:tell buf (list :insert "hello"))
  (sento.actor:tell buf (list :insert " world"))
  (sento.actor:tell buf '(:newline))
  (sento.actor:tell buf (list :insert "line two"))
  (sento.actor:tell buf '(:backspace))
  (sleep 0.5)

  (format t "snapshots received: ~a~%" (length *received-snapshots*))
  (format t "ticks: ~a~%" (reverse *received-snapshots*))
  (format t "final text: ~s~%" (hecl.buffer:current-buffer-text)))

(hecl:stop)
(format t "~%DONE~%")
(ext:quit 0)
