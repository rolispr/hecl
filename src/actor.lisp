(in-package :hecl.actor)

(defvar *actor-system* nil)
(defvar *remoting-port* nil)

(defun start-actor-system (&key (workers 4) (remoting-port 0))
  (when *actor-system*
    (error "Actor system already running."))
  (setf *actor-system*
        (asys:make-actor-system
         `(:dispatchers
           (:shared (:workers ,workers :strategy :random))
           :timeout-timer (:resolution 50 :max-size 500)
           :scheduler (:enabled :true :resolution 100 :max-size 500))))
  (when remoting-port
    (rem:enable-remoting *actor-system*
                         :host "127.0.0.1"
                         :port remoting-port)
    (setf *remoting-port* (rem:remoting-port *actor-system*)))
  *actor-system*)

(defun stop-actor-system ()
  (when *actor-system*
    (when (rem:remoting-enabled-p *actor-system*)
      (rem:disable-remoting *actor-system*))
    (ac:shutdown *actor-system* :wait t)
    (setf *actor-system* nil
          *remoting-port* nil)))


;;;; Agent registry

(defvar *agent-registry* nil)

(defstruct agent-info
  name type actor meta port)

(defun start-agent-registry ()
  (setf *agent-registry*
        (ac:actor-of *actor-system*
          :name "agent-registry"
          :state (make-hash-table :test 'equal)
          :receive
          (lambda (msg)
            (case (car msg)
              (:register
               (let* ((info (cadr msg))
                      (name (agent-info-name info)))
                 (setf (gethash name act:*state*) info)
                 (reply info)))
              (:register-remote
               (let* ((name (cadr msg))
                      (host (caddr msg))
                      (port (cadddr msg))
                      (uri (format nil "sento://~a:~d/user/agent" host port))
                      (ref #-lqml (rem:make-remote-ref *actor-system* uri)
                           #+lqml nil)
                      (info (make-agent-info :name name :type :process
                                             :actor ref :port port)))
                 (setf (gethash name act:*state*) info)
                 (reply info)))
              (:unregister
               (remhash (cadr msg) act:*state*)
               (reply t))
              (:lookup
               (reply (gethash (cadr msg) act:*state*)))
              (:list
               (let ((agents nil))
                 (maphash (lambda (k v) (declare (ignore k)) (push v agents))
                          act:*state*)
                 (reply (nreverse agents))))
              (t (reply (list :error :unknown msg))))))))

(defun register-agent (name type actor &key meta port)
  (act:ask-s *agent-registry*
             (list :register (make-agent-info :name name :type type
                                              :actor actor :meta meta :port port))
             :time-out 5))

(defun unregister-agent (name)
  (act:ask-s *agent-registry* (list :unregister name) :time-out 5))

(defun find-agent (name)
  (act:ask-s *agent-registry* (list :lookup name) :time-out 5))

(defun list-agents ()
  (act:ask-s *agent-registry* '(:list) :time-out 5))

(defun agent-eval (agent-or-name form-string &key (time-out 30))
  (let ((actor (etypecase agent-or-name
                 (agent-info (agent-info-actor agent-or-name))
                 (string (let ((info (find-agent agent-or-name)))
                           (unless info (error "No agent named ~s" agent-or-name))
                           (agent-info-actor info)))
                 (t agent-or-name))))
    (act:ask-s actor (list :eval form-string) :time-out time-out)))

(defun agent-compile (agent-or-name text &key package (time-out 60))
  (let ((actor (etypecase agent-or-name
                 (agent-info (agent-info-actor agent-or-name))
                 (string (agent-info-actor (find-agent agent-or-name)))
                 (t agent-or-name))))
    (act:ask-s actor (list :compile text package) :time-out time-out)))


;;;; Local agent

(defvar *local-agent* nil)

(defun start-local-agent ()
  (setf *local-agent*
        (ac:actor-of *actor-system*
          :name "local-agent"
          :receive
          (lambda (msg)
            (case (car msg)
              (:eval
               (handler-case
                   (let* ((form (read-from-string (cadr msg)))
                          (values (multiple-value-list (eval form)))
                          (result (format nil "~{~s~^~%~}" values)))
                     (reply (list :ok result)))
                 (error (c) (reply (list :error (princ-to-string c))))))
              (:compile
               (handler-case
                   (let ((*package* (or (and (caddr msg) (find-package (caddr msg)))
                                       *package*)))
                     (eval (read-from-string (cadr msg)))
                     (reply (list :ok "compiled")))
                 (error (c) (reply (list :error (princ-to-string c))))))
              (:set-package
               (let ((pkg (find-package (cadr msg))))
                 (if pkg
                     (progn (setf *package* pkg)
                            (reply (list :ok (package-name pkg))))
                     (reply (list :error (format nil "No package ~s" (cadr msg)))))))
              (:ping (reply :pong))
              (:shutdown (reply :ok))
              (t (reply (list :error :unknown-message (car msg))))))))
  (register-agent "local" :local *local-agent*))


;;;; Spawn

(defun spawn-agent (name &key (master-port *remoting-port*))
  (unless master-port
    (error "Cannot spawn agent: remoting not enabled."))
  (let* ((script (format nil
                         "(require :asdf)~%(asdf:load-system :hecl-agent)~%(hecl.agent:connect :name ~s :master-port ~d)~%"
                         name master-port))
         (tmp (merge-pathnames (format nil "hecl-agent-~a.lisp" name)
                               (uiop:temporary-directory))))
    (with-open-file (s tmp :direction :output :if-exists :supersede)
      (write-string script s))
    (uiop:launch-program
     (list "ecl" "-q" "--load"
           (namestring (merge-pathnames "init.lisp"
                                        (asdf:system-source-directory :hecl)))
           "--load" (namestring tmp)))
    (loop for i from 0 below 150
          for info = (find-agent name)
          when info return info
          do (sleep 0.1)
          finally (error "Agent ~s did not connect within 15 seconds." name))))

(defun kill-agent (name)
  (let ((info (find-agent name)))
    (when info
      (handler-case
          (act:ask-s (agent-info-actor info) '(:shutdown) :time-out 5)
        (error () nil))
      (unregister-agent name))))
