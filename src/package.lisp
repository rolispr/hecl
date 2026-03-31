(defpackage #:hecl
            (:use #:cl)
            (:export #:main
                     #:*system*))

(defpackage #:hecl/config
            (:use #:cl)
            (:export #:*target*
                     #:target-features
                     #:desktop?
                     #:mobile?))
