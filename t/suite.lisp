(in-package :hecl/tests)
(in-suite :hecl)

(test actor-system-lifecycle
  (let ((sys (hecl.actor:start-actor-system :workers 2 :remoting-port nil)))
    (unwind-protect
         (progn
           (is (not (null sys)))
           (is (not (null hecl.actor:*actor-system*))))
      (hecl.actor:stop-actor-system))))

(test agent-registry
  (hecl.actor:start-actor-system :workers 2 :remoting-port nil)
  (unwind-protect
       (progn
         (hecl.actor:start-agent-registry)
         (is (not (null hecl.actor:*agent-registry*)))
         (hecl.actor:start-local-agent)
         (is (not (null (hecl.actor:find-agent "local"))))
         (let ((agents (hecl.actor:list-agents)))
           (is (= 1 (length agents)))
           (is (string= "local" (hecl.actor:agent-info-name (first agents))))))
    (hecl.actor:stop-actor-system)))

(test local-agent-eval
  (hecl.actor:start-actor-system :workers 2 :remoting-port nil)
  (unwind-protect
       (progn
         (hecl.actor:start-agent-registry)
         (hecl.actor:start-local-agent)
         (let ((result (hecl.actor:agent-eval "local" "(+ 1 2)" :time-out 5)))
           (is (eq :ok (first result)))
           (is (string= "3" (second result)))))
    (hecl.actor:stop-actor-system)))

(test event-bus
  (hecl.actor:start-actor-system :workers 2 :remoting-port nil)
  (unwind-protect
       (progn
         (hecl.event:make-event-bus hecl.actor:*actor-system*)
         (let ((received nil))
           (hecl.event:subscribe hecl.event:*event-bus* :test
                                 (lambda (payload) (push payload received)))
           (hecl.event:publish hecl.event:*event-bus* :test "hello")
           (hecl.event:publish hecl.event:*event-bus* :test "world")
           (sleep 1)
           (is (= 2 (length received)))))
    (hecl.actor:stop-actor-system)))

(test full-boot
  (let ((sys (hecl:main :workers 2 :remoting-port nil)))
    (unwind-protect
         (progn
           (is (not (null sys)))
           (is (not (null hecl:*system*)))
           (is (not (null (hecl.actor:find-agent "local")))))
      (hecl:stop))))
