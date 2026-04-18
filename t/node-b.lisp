(load (merge-pathnames "../init.lisp" *load-truename*))
(asdf:load-system :sento-remoting)
(asdf:load-system :hecl)
(hecl.actor:start-actor-system :workers 2 :remoting-port 5556)

(let* ((uri "sento://127.0.0.1:5555/user/pong")
       (ref (sento.remoting:make-remote-ref hecl.actor:*actor-system* uri))
       (result (sento.actor:ask-s ref :ping :time-out 5)))
  (format t "~%B sent :ping, got back: ~a~%" result)
  (force-output))

(hecl.actor:stop-actor-system)
(ext:quit 0)
