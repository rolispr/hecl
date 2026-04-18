(require :asdf)
(let ((root (merge-pathnames "../" (make-pathname :directory (pathname-directory *load-truename*)))))
  (load (merge-pathnames "init.lisp" root)))
(asdf:load-system :sento-remoting)
(asdf:load-system :hecl)

(in-package :cl-user)

(format t "~%=== hecl remoting test on ECL ~a ===~%~%" (lisp-implementation-version))

(defvar *sys-a* nil)
(defvar *sys-b* nil)
(defvar *pass* 0)
(defvar *fail* 0)

(defmacro check (name &body body)
  `(progn
     (format t "~a... " ,name)
     (force-output)
     (handler-case
         (if (progn ,@body)
             (progn (incf *pass*) (format t "PASS~%"))
             (progn (incf *fail*) (format t "FAIL~%")))
       (error (c)
         (incf *fail*)
         (format t "ERROR: ~a~%" c)))
     (force-output)))

(unwind-protect
     (progn
       (setf *sys-a* (sento.actor-system:make-actor-system
                       '(:dispatchers (:shared (:workers 2)))))
       (setf *sys-b* (sento.actor-system:make-actor-system
                       '(:dispatchers (:shared (:workers 2)))))

       (sento.remoting:enable-remoting *sys-a* :host "127.0.0.1" :port 0
                                                :hostname "127.0.0.1")
       (sento.remoting:enable-remoting *sys-b* :host "127.0.0.1" :port 0
                                                :hostname "127.0.0.1")

       (let ((port-a (sento.remoting:remoting-port *sys-a*))
             (port-b (sento.remoting:remoting-port *sys-b*)))
         (format t "system A on port ~a, system B on port ~a~%~%" port-a port-b)

         (check "remote tell"
           (let ((received nil))
             (sento.actor-context:actor-of *sys-b*
               :name "sink"
               :receive (lambda (msg) (setf received msg)))
             (let* ((uri (format nil "sento://127.0.0.1:~a/user/sink" port-b))
                    (ref (sento.remoting:make-remote-ref *sys-a* uri)))
               (sento.actor:tell ref "cross-process")
               (sleep 2)
               (equal "cross-process" received))))

         (check "remote ask-s"
           (sento.actor-context:actor-of *sys-b*
             :name "upper"
             :receive (lambda (msg) (string-upcase msg)))
           (let* ((uri (format nil "sento://127.0.0.1:~a/user/upper" port-b))
                  (ref (sento.remoting:make-remote-ref *sys-a* uri)))
             (string= "HELLO" (sento.actor:ask-s ref "hello" :time-out 5))))

         (check "bidirectional (B asks A)"
           (sento.actor-context:actor-of *sys-a*
             :name "adder"
             :receive (lambda (msg) (+ (first msg) (second msg))))
           (let* ((uri (format nil "sento://127.0.0.1:~a/user/adder" port-a))
                  (ref (sento.remoting:make-remote-ref *sys-b* uri)))
             (= 42 (sento.actor:ask-s ref '(17 25) :time-out 5))))

         (check "remote state mutation"
           (sento.actor-context:actor-of *sys-b*
             :name "counter"
             :state 0
             :receive (lambda (msg)
                        (case msg
                          (:inc (incf sento.actor:*state*) :ok)
                          (:get sento.actor:*state*))))
           (let* ((uri (format nil "sento://127.0.0.1:~a/user/counter" port-b))
                  (ref (sento.remoting:make-remote-ref *sys-a* uri)))
             (sento.actor:ask-s ref :inc :time-out 5)
             (sento.actor:ask-s ref :inc :time-out 5)
             (sento.actor:ask-s ref :inc :time-out 5)
             (= 3 (sento.actor:ask-s ref :get :time-out 5))))

         (check "actor registry over remoting"
           (hecl.actor:start-actor-system :workers 2 :remoting-port 0)
           (hecl.actor:start-agent-registry)
           (hecl.actor:start-local-agent)
           (let ((result (hecl.actor:agent-eval "local" "(+ 100 200)" :time-out 5)))
             (prog1 (and (eq :ok (first result))
                         (string= "300" (second result)))
               (hecl.actor:stop-actor-system))))))

  (format t "~%shutting down... ") (force-output)
  (when *sys-a*
    (sento.remoting:disable-remoting *sys-a*)
    (sento.actor-context:shutdown *sys-a* :wait t))
  (when *sys-b*
    (sento.remoting:disable-remoting *sys-b*)
    (sento.actor-context:shutdown *sys-b* :wait t))
  (format t "done~%"))

(format t "~%~a/~a passed~%" *pass* (+ *pass* *fail*))
(ext:quit (if (zerop *fail*) 0 1))
