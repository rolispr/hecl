(in-package #:hecl)

(defvar *system* nil)

(defun main ()
  (format t "hecl ~a on ~a ~a [~a]~%"
          (asdf:component-version (asdf:find-system :hecl))
          (lisp-implementation-type)
          (lisp-implementation-version)
          hecl/config:*target*)
  (let ((sys (sento.actor-system:make-actor-system)))
    (setf *system* sys)
    (format t "actor system started~%")
    sys))
