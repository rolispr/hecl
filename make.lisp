(require :asdf)
(require :cmp)

(defvar *lqml-root* (truename (merge-pathnames "../lqml/" (make-pathname :directory (pathname-directory *load-truename*)))))
(defvar *hecl-root* (truename (make-pathname :directory (pathname-directory *load-truename*))))

(push *hecl-root* asdf:*central-registry*)

(setf *default-pathname-defaults* *lqml-root*)

(defvar *current*
        (let ((name (namestring *hecl-root*)))
          (subseq name (length (namestring (truename (merge-pathnames "../" *hecl-root*)))))))

(dolist (file (list "package" "x" "ecl-ext" "ini" "qml"))
  (load (merge-pathnames file (merge-pathnames "src/lisp/" *lqml-root*))))

(asdf:make-build "hecl"
                 :monolithic t
                 :type :static-library
                 :move-here (merge-pathnames "build/build/tmp/" *hecl-root*)
                 :init-name "ini_app")

(let* ((from (namestring (merge-pathnames "build/build/tmp/hecl--all-systems.a" *hecl-root*)))
       (to   (namestring (merge-pathnames "build/build/tmp/libapp.a" *hecl-root*))))
  (when (probe-file to)
    (delete-file to))
  (rename-file from to))
