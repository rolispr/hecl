#-ocicl
(when (probe-file #P"/Users/bret.horne/.local/share/ocicl/ocicl-runtime.lisp")
  (load #P"/Users/bret.horne/.local/share/ocicl/ocicl-runtime.lisp"))

(let* ((here (make-pathname :directory (pathname-directory *load-truename*)))
       (vendor-sento (merge-pathnames "vendor/cl-gserver/" here)))
  (push here asdf:*central-registry*)
  (push vendor-sento asdf:*central-registry*))
