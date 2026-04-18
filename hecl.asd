(eval-when (:compile-toplevel :load-toplevel :execute)
  (unless (find-package :hecl-system)
    (defpackage #:hecl-system
      (:use #:cl)
      (:export #:*hecl-base-directory*)))
  (setf (symbol-value (intern "*HECL-BASE-DIRECTORY*" :hecl-system))
        (make-pathname :name nil :type nil :version nil
                       :defaults (parse-namestring *load-truename*))))

(asdf:defsystem #:hecl
  :description "hecl — editor on ECL"
  :author "Bret Horne"
  :license "MIT"
  :version "0.2.0"
  :depends-on (#:sento
               #:sento-remoting
               #:fset
               #:alexandria
               #:bordeaux-threads)
  :serial t
  :pathname "src/"
  :components
  ((:file "package")
   (:file "actor")
   (:file "event")
   (:file "hooks")
   (:file "face")
   (:file "buffer")
   (:file "window")
   #+lqml (:file "bridge")
   (:file "ts")
   (:file "render")
   (:file "file")
   (:file "shell")
   (:file "term")
   (:file "keymap")
   (:file "kill-ring")
   (:file "complete")
   (:file "prompt")
   (:file "editor")
   (:file "main"))
  :in-order-to ((test-op (test-op #:hecl/tests))))

(asdf:defsystem #:hecl/tests
  :depends-on (#:hecl #:fiveam)
  :serial t
  :components
  ((:file "t/package")
   (:file "t/suite"))
  :perform (test-op (o c)
             (symbol-call :fiveam :run! :hecl)))
