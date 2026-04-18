(load (merge-pathnames "../init.lisp" *load-truename*))
(asdf:load-system :hecl)
(hecl:main :workers 2 :remoting-port nil)

(format t "~%buffers: ~a~%" (hecl.buffer:list-buffers))
(format t "current text: ~s~%" (hecl.buffer:current-buffer-text))

(sento.actor:tell hecl.buffer:*current-buffer* (list :insert "hello hecl"))
(sleep 0.1)
(format t "after insert: ~s~%" (hecl.buffer:current-buffer-text))

(hecl.buffer:make-buffer "test")
(format t "buffers now: ~a~%" (hecl.buffer:list-buffers))

(hecl.buffer:switch-buffer "test")
(sento.actor:tell hecl.buffer:*current-buffer* (list :insert "test buffer content"))
(sleep 0.1)
(format t "test text: ~s~%" (hecl.buffer:current-buffer-text))

(hecl.buffer:switch-buffer "scratch")
(format t "back to scratch: ~s~%" (hecl.buffer:current-buffer-text))

(sento.actor:tell hecl.buffer:*current-buffer* '(:undo))
(sleep 0.1)
(format t "after undo: ~s~%" (hecl.buffer:current-buffer-text))

(hecl.buffer:kill-buffer "test")
(format t "after kill: ~a~%" (hecl.buffer:list-buffers))

(hecl:stop)
(format t "~%DONE~%")
(ext:quit 0)
