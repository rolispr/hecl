(in-package #:hecl/config)

(deftype target ()
         '(member :linux :macos :windows :android :ios))

(defvar *target*
  #+darwin :macos
  #+linux :linux
  #+windows :windows
  #-(or darwin linux windows) :linux)

(defun target-features (target)
  (case target
        ((:linux :macos :windows) '(:desktop :gui :native-compiler))
        ((:android :ios) '(:mobile :gui :touch))
        (otherwise '(:desktop))))

(defun desktop? ()
  (member :desktop (target-features *target*)))

(defun mobile? ()
  (member :mobile (target-features *target*)))
