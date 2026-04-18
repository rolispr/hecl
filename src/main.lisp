(in-package :hecl)

(defvar *system* nil)
(defvar *version* "0.2.0")

(defvar *target*
  #+darwin :macos
  #+linux :linux
  #+windows :windows
  #-(or darwin linux windows) :linux)

(defun desktop? ()
  (member *target* '(:linux :macos :windows)))

(defun mobile? ()
  (member *target* '(:android :ios)))

(defun main (&key (workers 4) (remoting-port 0))
  (format t "hecl ~a on ~a ~a [~a]~%"
          *version*
          (lisp-implementation-type)
          (lisp-implementation-version)
          *target*)
  (hecl.actor:start-actor-system :workers workers
                                  :remoting-port remoting-port)
  (hecl.actor:start-agent-registry)
  (hecl.actor:start-local-agent)
  (hecl.event:make-event-bus hecl.actor:*actor-system*)
  (hecl.editor:start-editor)
  (hecl.hooks:run-init-hooks)
  #+lqml (hecl.qml:init-ui)
  (setf *system* hecl.actor:*actor-system*)
  (format t "hecl ready [port ~a]~%"
          (or hecl.actor:*remoting-port* "none"))
  *system*)

(defun stop ()
  (hecl.hooks:run-shutdown-hooks)
  (hecl.actor:stop-actor-system)
  (setf *system* nil))

(defun on-key (key modifiers text)
  (hecl.editor:on-key key modifiers text))

(defun on-minibuffer-accept (text)
  (hecl.editor:on-minibuffer-accept text))
