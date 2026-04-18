(in-package :hecl.event)

(defvar *event-bus* nil)

(defun make-event-bus (actor-system)
  (setf *event-bus*
        (sento.actor-context:actor-of actor-system
          :name "event-bus"
          :state (make-hash-table :test 'eq)
          :receive
          (lambda (msg)
            (case (car msg)
              (:publish
               (let* ((topic (cadr msg))
                      (payload (caddr msg))
                      (handlers (gethash topic sento.actor:*state*)))
                 (loop for fn in handlers do (funcall fn payload))))
              (:subscribe
               (push (caddr msg) (gethash (cadr msg) sento.actor:*state*))
               (sento.actor:reply t))
              (:unsubscribe
               (setf (gethash (cadr msg) sento.actor:*state*)
                     (remove (caddr msg) (gethash (cadr msg) sento.actor:*state*)))
               (sento.actor:reply t)))))))

(defun publish (bus topic payload)
  (sento.actor:tell bus (list :publish topic payload)))

(defun subscribe (bus topic handler)
  (sento.actor:ask-s bus (list :subscribe topic handler) :time-out 5))

(defun unsubscribe (bus topic handler)
  (sento.actor:ask-s bus (list :unsubscribe topic handler) :time-out 5))
