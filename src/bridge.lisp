(in-package :hecl.qml)

(defvar *ui-ready* nil)

(defun init-ui ()
  (qml:qsingle-shot 100
    (lambda ()
      (setf *ui-ready* t)
      (let ((root (qml:find-quick-item "root")))
        (when root
          (qml:qml-set root "lispReady" t))))))

(defun find-item (name)
  (qml:find-quick-item name))

(defun set-property (item property value)
  (qml:qml-set item property value))


;;;; Frame push

(defun push-frame ()
  (let* ((f hecl.buffer:*frame*)
         (count (hecl.buffer:frame-cell-count f)))
    (when (hecl.buffer:frame-dirtyp f)
      (setf (hecl.buffer:frame-dirtyp f) nil)
      (hecl.term:ensure-pushframe)
      (let ((display (find-item "display")))
        (when display
          (let ((ptr (qml::qt-object-address display)))
            (qml:qrun
             (lambda ()
               (hecl.term:push-frame-direct
                (hecl.buffer:frame-cells f) count
                ptr
                (hecl.buffer:frame-cursor-row f)
                (hecl.buffer:frame-cursor-col f)
                (hecl.buffer:frame-scroll-pixel f)))
             nil)))))))


(defun set-cursor (row col)
  "Set cursor position on Canvas."
  (qml:qrun
   (lambda ()
     (let ((display (find-item "display")))
       (when display
         (set-property display "cursorRow" row)
         (set-property display "cursorCol" col))))
   nil))


;;;; Scroll

(defun on-scroll (lines)
  (hecl.editor:scroll-window (truncate lines)))


;;;; Resize

(defun report-resize (cols rows)
  (when (and (boundp 'hecl.render::*renderer*) hecl.render:*renderer*)
    (sento.actor:tell hecl.render:*renderer* (list :resize cols rows))))


;;;; Status bar

(defun update-status-text (text)
  (qml:qrun
   (lambda ()
     (let ((item (find-item "statusText")))
       (when item (set-property item "text" text))))
   nil))

(defun show-status-input (prompt-text)
  (declare (ignore prompt-text))
  (qml:qrun*
   (let ((input (find-item "statusInput"))
         (status (find-item "statusText")))
     (when (and input status)
       (set-property status "visible" nil)
       (set-property input "visible" t)
       (set-property input "focus" t)))))

(defun hide-status-input ()
  (qml:qrun*
   (let ((input (find-item "statusInput"))
         (status (find-item "statusText")))
     (when (and input status)
       (set-property input "visible" nil)
       (set-property input "text" "")
       (set-property status "visible" t))))
  (qml:qrun*
   (let ((root (find-item "root")))
     (when root (set-property root "focus" t)))))


;;;; Completion area

(defun show-completion-area (text)
  (qml:qrun*
   (let ((area (find-item "completionArea"))
         (ct (find-item "completionText")))
     (when (and area ct)
       (set-property ct "text" text)
       (set-property area "visible" t)))))

(defun hide-completion-area ()
  (qml:qrun*
   (let ((area (find-item "completionArea")))
     (when area (set-property area "visible" nil)))))


;;;; Live input callback

(defun on-input-changed (text)
  (when (hecl.editor:completing-read-active-p)
    (hecl.editor:completion-update-input text)))
