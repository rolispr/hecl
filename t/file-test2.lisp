(load (merge-pathnames "../init.lisp" *load-truename*))
(asdf:load-system :hecl)
(hecl:main :workers 2 :remoting-port nil)

(with-open-file (s "/tmp/hecl-test.txt" :direction :output :if-exists :supersede)
  (format s "hello~%world~%foo"))

(hecl.file:find-file "/tmp/hecl-test.txt")
(sleep 0.3)
(let ((text (hecl.buffer:current-buffer-text)))
  (format t "~%lines: ~a~%" (count #\Newline text))
  (format t "text: [~a]~%" text))

(sento.actor:tell hecl.buffer:*current-buffer* (list :insert "EDIT"))
(sleep 0.2)
(hecl.file:save-current-buffer)

(format t "~%disk: [~a]~%" (hecl.file:read-file "/tmp/hecl-test.txt"))
(delete-file "/tmp/hecl-test.txt")
(hecl:stop)
(format t "DONE~%")
(ext:quit 0)
