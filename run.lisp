(in-package :qml-user)

(pushnew :lqml *features*)

(require :asdf)

(let ((here (merge-pathnames "./")))
  (push here asdf:*central-registry*)
  (push (merge-pathnames "vendor/cl-gserver/" here) asdf:*central-registry*))

(asdf:load-system :hecl)

(hecl:main :workers 4 :remoting-port nil)

(defun option (name)
  (find name (ext:command-args) :test 'search))

(when (option "-slime")
  (load "~/slime/lqml-start-swank"))

(when (option "-sly")
  (asdf:load-system :slynk)
  (asdf:load-system :slynk/mrepl)
  (funcall (intern "CREATE-SERVER" :slynk) :port 4005 :dont-close t))

(when (option "-auto")
  (load "lisp/qml-reload/auto-reload"))
