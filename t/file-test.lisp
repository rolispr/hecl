(load (merge-pathnames "../init.lisp" *load-truename*))
(asdf:load-system :hecl)
(hecl:main :workers 2 :remoting-port nil)

(format t "~%=== file I/O test ===~%~%")

(with-open-file (s "/tmp/hecl-test-file.txt" :direction :output :if-exists :supersede)
  (write-string "line one
line two
line three" s))

(hecl.file:find-file "/tmp/hecl-test-file.txt")
(sleep 0.2)
(format t "opened file, text: ~s~%" (hecl.buffer:current-buffer-text))

(sento.actor:tell hecl.buffer:*current-buffer* (list :insert "EDITED "))
(sleep 0.2)
(format t "after edit: ~s~%" (hecl.buffer:current-buffer-text))

(hecl.file:save-current-buffer)

(let ((saved (hecl.file:read-file "/tmp/hecl-test-file.txt")))
  (format t "saved file content: ~s~%" saved))

(delete-file "/tmp/hecl-test-file.txt")

(hecl:stop)
(format t "~%DONE~%")
(ext:quit 0)
