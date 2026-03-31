(asdf:defsystem #:hecl
  :description "Hemlock on ECL — a portable, distributed CL editor"
  :author "Bret Horne"
  :license "MIT"
  :version "0.1.0"
  :depends-on (#:sento)
  :serial t
  :components ((:file "src/package")
               (:file "src/config")
               (:file "src/main"))
  :in-order-to ((test-op (test-op #:hecl/tests))))

(asdf:defsystem #:hecl/tests
  :depends-on (#:hecl #:fiveam)
  :serial t
  :components ((:file "t/package")
               (:file "t/suite"))
  :perform (test-op (o c)
             (symbol-call :fiveam :run! :hecl)))
