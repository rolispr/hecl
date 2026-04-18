(in-package :hecl.render)

(defvar *renderer* nil)
(defvar *ts-actor* nil)
(defvar *render-scheduled* nil)

;;; Single shared render state — fset:map, immutable, safe to read from any thread.
;;; Only the renderer actor writes it (via setf of the reference).
(defvar *render-state*
  (fset:map (:dirty nil)))

(defun rs@ (key)
  (fset:@ *render-state* key))

(defun rs-update (&rest pairs)
  "Functionally update *render-state* with key-value pairs."
  (let ((rs *render-state*))
    (loop for (k v) on pairs by #'cddr
          do (setf rs (fset:with rs k v)))
    (setf *render-state* rs)))


;;;; Text conversion for tree-sitter FFI

(defun lines-to-string (ls)
  (let* ((n (fset:size ls))
         (total (loop for i from 0 below n
                      sum (length (fset:@ ls i))
                      sum (if (plusp i) 1 0)))
         (result (make-array total :element-type 'base-char))
         (pos 0))
    (dotimes (i n)
      (when (plusp i)
        (setf (aref result pos) #\Newline)
        (incf pos))
      (let ((line (fset:@ ls i)))
        (dotimes (j (length line))
          (let* ((ch (char line j))
                 (code (char-code ch)))
            (setf (aref result pos) (if (<= code 255) (code-char code) #\?))
            (incf pos)))))
    result))


;;;; Tree-sitter parse dispatch

(defun ts-request-parse (buffer-actor snap)
  "Send a tree-sitter parse request for SNAP. Results go back to BUFFER-ACTOR."
  (when (and *ts-actor* snap (typep snap 'hecl.buffer:snapshot))
    (let ((text (lines-to-string (hecl.buffer:lines snap))))
      (sento.actor:tell *ts-actor*
                        (list :parse text buffer-actor)))))


;;;; Renderer actor

(defun start-renderer ()
  ;; Tree-sitter actor
  (when hecl.ts:*ts-loaded*
    (setf *ts-actor*
          (sento.actor-context:actor-of hecl.actor:*actor-system*
            :name "ts-parser"
            :receive
            (lambda (msg)
              (case (car msg)
                (:parse
                 (let* ((text (cadr msg))
                        (buf-actor (caddr msg))
                        (hl (handler-case (hecl.ts:compute-highlights text)
                              (error () nil))))
                   (when buf-actor
                     (sento.actor:tell buf-actor (list :highlights hl))))))))))

  ;; Renderer actor
  (setf *renderer*
        (sento.actor-context:actor-of hecl.actor:*actor-system*
          :name "renderer"
          :state nil
          :receive
          (lambda (msg)
            (handler-case
                (case (car msg)
                  (:snapshot
                   (let* ((snap (cadr msg))
                          (w hecl.buffer:*focused-window*))
                     (apply-snapshot snap)
                     (when w
                       (let ((buf (find-buffer-for-snap snap)))
                         (when buf (ts-request-parse buf snap))))
                     (rs-update :dirty t)
                     (schedule-render-async)))

                  (:resize
                   (let ((cols (cadr msg)) (rows (caddr msg)))
                     (setf (hecl.buffer:frame-cols hecl.buffer:*frame*) cols
                           (hecl.buffer:frame-rows hecl.buffer:*frame*) rows)
                     (relayout)
                     (hecl.buffer:ensure-frame-cells hecl.buffer:*frame*)
                     (hecl.term:resize-active-terminal cols rows)
                     (rs-update :dirty t)
                     (schedule-render-async)))

                  (:switch-buffer
                   (switch-window-buffer (cadr msg) (caddr msg)))

                  (:force-render
                   (rs-update :dirty t)
                   (schedule-render-async)))
              (error () nil)))))

  #+lqml (start-render-loop))

(defun schedule-render-async ()
  "Non-blocking schedule from actor thread."
  #+lqml (qml:qrun #'schedule-render nil))


;;;; Subscriber

(defun make-subscriber ()
  (lambda (snapshot)
    (sento.actor:tell *renderer* (list :snapshot snapshot))))


;;;; Window management (called from renderer actor)

(defun find-buffer-for-snap (snap)
  (when (typep snap 'hecl.buffer:snapshot)
    (let ((snap-name (hecl.buffer:name snap)))
      (dolist (w hecl.buffer:*windows*)
        (when (string= (hecl.buffer:window-name w) snap-name)
          (return (hecl.buffer:buffer-ref w)))))))

(defun apply-snapshot (snap)
  (when (typep snap 'hecl.buffer:snapshot)
    (let ((snap-name (hecl.buffer:name snap)))
      (dolist (w hecl.buffer:*windows*)
        (when (string= (hecl.buffer:window-name w) snap-name)
          (setf (hecl.buffer:snap w) snap))))))

(defun switch-window-buffer (buf name)
  (let ((w hecl.buffer:*focused-window*))
    (when w
      (setf (hecl.buffer:buffer-ref w) buf
            (hecl.buffer:window-name w) name
            (hecl.buffer:scroll-top w) 0
            (hecl.buffer:col w) 0
            (hecl.buffer:snap w) nil
            (hecl.buffer:win-display w) nil)))
  (rs-update :dirty t)
  (schedule-render-async))

(defun relayout ()
  (let* ((cols (hecl.buffer:frame-cols hecl.buffer:*frame*))
         (rows (hecl.buffer:frame-rows hecl.buffer:*frame*)))
    (dolist (w hecl.buffer:*windows*)
      (setf (hecl.buffer:row w) 0
            (hecl.buffer:col w) 0
            (hecl.buffer:win-width w) cols
            (hecl.buffer:win-height w) rows))))


;;;; Cell emission

(defun parse-hex-color (hex)
  (if (and hex (> (length hex) 6) (char= (char hex 0) #\#))
      (list (parse-integer hex :start 1 :end 3 :radix 16)
            (parse-integer hex :start 3 :end 5 :radix 16)
            (parse-integer hex :start 5 :end 7 :radix 16))
      (list 205 214 244)))

(defun face-rgb (face-name)
  (let ((f (when face-name (hecl.buffer:find-face face-name))))
    (if (and f (hecl.buffer:fg f))
        (parse-hex-color (hecl.buffer:fg f))
        (list 205 214 244))))

(defun build-highlight-table (highlights scroll-top visible-rows)
  (let ((table (make-hash-table)))
    (dolist (h highlights)
      (let ((line (first h)) (sc (second h)) (ec (third h)) (face (fourth h)))
        (when (and (>= line scroll-top) (< line (+ scroll-top visible-rows)))
          (push (list sc ec face) (gethash (- line scroll-top) table)))))
    (maphash (lambda (k v)
               (setf (gethash k table) (nreverse v)))
             table)
    table))

(defun face-priority (face)
  (case face
    (:keyword        10)
    (:function-name   8)
    (:builtin         7)
    (:constant        6)
    (:escape          6)
    (:string          5)
    (:comment         5)
    (:type            4)
    (:variable-param  3)
    (:variable        1)
    (t                0)))

(defun build-face-slots (line-hl line-length)
  (let ((slots (make-array line-length :initial-element nil))
        (prios (make-array line-length :initial-element -1)))
    (dolist (h line-hl)
      (let* ((sc (first h))
             (ec (min (second h) line-length))
             (face (third h))
             (p (face-priority face)))
        (when face
          (loop for c from (max 0 sc) below ec
                when (> p (aref prios c))
                do (setf (aref slots c) face
                         (aref prios c) p)))))
    slots))

(defun render-buffer-to-frame (w)
  "Render buffer cells into frame."
  (let ((f hecl.buffer:*frame*))
    (hecl.buffer:ensure-frame-cells f)
    (let* ((s (hecl.buffer:snap w))
           (dl (hecl.buffer:win-display w))
           (wid (hecl.buffer:win-width w))
           (cells (hecl.buffer:frame-cells f))
           (left (hecl.buffer:col w))
           (hl (hecl.buffer:highlights s))
           (hl-table (when hl
                       (build-highlight-table hl (hecl.buffer:scroll-top w) (length dl))))
           (off 0))
      (loop for d in dl
            for display-row from 0
            for row = (+ (hecl.buffer:row w) display-row)
            for text = (hecl.buffer:display-text d)
            for buf-line-idx = (+ display-row (hecl.buffer:scroll-top w))
            do (let* ((line-hl (when hl-table (gethash display-row hl-table)))
                      (buf-line-len (if (< buf-line-idx (hecl.buffer:line-count s))
                                        (length (fset:@ (hecl.buffer:lines s) buf-line-idx))
                                        0))
                      (face-slots (when line-hl
                                    (build-face-slots line-hl buf-line-len))))
                 (loop for i from 0 below (min (length text) wid)
                       for ch = (char-code (char text i))
                       for col = i
                       for buf-col = (+ i left)
                       for face = (when (and face-slots (< buf-col (length face-slots)))
                                    (aref face-slots buf-col))
                       for rgb = (face-rgb face)
                       do (setf (svref cells (+ off 0)) row
                                (svref cells (+ off 1)) col
                                (svref cells (+ off 2)) ch
                                (svref cells (+ off 3)) (first rgb)
                                (svref cells (+ off 4)) (second rgb)
                                (svref cells (+ off 5)) (third rgb)
                                (svref cells (+ off 6)) -1
                                (svref cells (+ off 7)) -1
                                (svref cells (+ off 8)) -1
                                (svref cells (+ off 9)) nil)
                          (incf off 10))))
      (setf (hecl.buffer:frame-cell-count f) off
            (hecl.buffer:frame-cursor-row f)
            (max 0 (min (- (hecl.buffer:point-line s) (hecl.buffer:scroll-top w))
                        (1- (hecl.buffer:win-height w))))
            (hecl.buffer:frame-cursor-col f)
            (- (hecl.buffer:point-col s) (hecl.buffer:col w))
            (hecl.buffer:frame-scroll-pixel f)
            (coerce (hecl.buffer:scroll-top w) 'double-float)
            (hecl.buffer:frame-dirtyp f) t))))


;;;; Render loop (Qt thread)

(defun start-render-loop ()
  #+lqml (schedule-render))

(defun schedule-render ()
  #+lqml
  (unless *render-scheduled*
    (setf *render-scheduled* t)
    (qml:qsingle-shot 16 #'render-tick)))

(defun render-tick ()
  #+lqml
  (progn
    (setf *render-scheduled* nil)
    (handler-case
        (let ((rs *render-state*)  ;; grab immutable snapshot
              (w hecl.buffer:*focused-window*))
          (when (and w (fset:@ rs :dirty))
            (let ((term (hecl.term:terminal-for-buffer
                         (hecl.buffer:buffer-ref w))))
              (cond
                ;; Terminal
                ((and term (hecl.term:terminal-visible-p))
                 (rs-update :dirty nil)
                 (hecl.term:render-terminal-to-frame)
                 (hecl.qml:push-frame)
                 (hecl.qml:update-status-text
                  (format nil "*terminal*  |  L~a:C~a"
                          (1+ (hecl.buffer:frame-cursor-row hecl.buffer:*frame*))
                          (1+ (hecl.buffer:frame-cursor-col hecl.buffer:*frame*)))))
                ;; Buffer
                (t
                 (let ((s (hecl.buffer:snap w)))
                   (if s
                       (progn
                         (rs-update :dirty nil)
                         (hecl.buffer:ensure-point-visible w)
                         (hecl.buffer:ensure-col-visible w)
                         (setf (hecl.buffer:win-display w)
                               (hecl.buffer:window-display-lines w))
                         (render-buffer-to-frame w)
                         (hecl.qml:push-frame)
                         (hecl.qml:update-status-text
                          (format nil "~a  |  L~a:C~a"
                                  (hecl.buffer:window-name w)
                                  (1+ (hecl.buffer:point-line s))
                                  (1+ (hecl.buffer:point-col s)))))
                       ;; Snap not yet arrived — keep dirty, retry
                       (schedule-render))))))))
      (error () nil))))


;;;; Subscription

(defun subscribe-to-buffer (buffer-actor)
  (when buffer-actor
    (sento.actor:tell buffer-actor
                      (list :subscribe (make-subscriber)))))

(defun unsubscribe-from-buffer (buffer-actor)
  (sento.actor:tell buffer-actor
                    (list :unsubscribe (make-subscriber))))
