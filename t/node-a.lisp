(load (merge-pathnames "../init.lisp" *load-truename*))
(asdf:load-system :sento-remoting)
(asdf:load-system :hecl)
(hecl.actor:start-actor-system :workers 2 :remoting-port 5555)

(sento.actor-context:actor-of hecl.actor:*actor-system*
  :name "pong"
  :receive (lambda (msg)
             (format t "A received: ~a~%" msg)
             (force-output)
             (sento.actor:reply :pong)))

(format t "~%Node A listening on 5555~%")
(force-output)
(loop (sleep 1))
