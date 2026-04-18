(in-package :hecl.editor)

(defun start-editor ()
  (hecl.buffer:start-buffer-registry)
  (handler-case
      (progn
        (hecl.ts:ensure-ts)
        (format *error-output* "tree-sitter: ~a~%" hecl.ts:*ts-loaded*)
        (force-output *error-output*))
    (error (c)
      (format *error-output* "tree-sitter init error: ~a~%" c)
      (force-output *error-output*)))
  (hecl.render:start-renderer)
  (setup-default-bindings)
  ;; Create scratch buffer and its window
  (let ((buf (hecl.buffer:make-buffer "scratch")))
    (hecl.buffer:make-window buf "scratch"
                             :row 0 :col 0 :width 80 :height 29 :focused t)
    (hecl.render:subscribe-to-buffer buf))
  ;; Layout based on initial frame size
  (hecl.render:relayout))

(defun focused-snap ()
  "Get cached snapshot from focused window — no actor round-trip."
  (let ((w hecl.buffer:*focused-window*))
    (when w (hecl.buffer:snap w))))

(defun move-point-up ()
  (let ((buf hecl.buffer:*current-buffer*))
    (when buf
      (let ((snap (focused-snap)))
        (when (and snap (plusp (hecl.buffer:point-line snap)))
          (let* ((new-line (1- (hecl.buffer:point-line snap)))
                 (new-col (min (hecl.buffer:point-col snap)
                               (length (fset:@ (hecl.buffer:lines snap) new-line)))))
            (sento.actor:tell buf (list :move-point new-line new-col))))))))

(defun move-point-down ()
  (let ((buf hecl.buffer:*current-buffer*))
    (when buf
      (let ((snap (focused-snap)))
        (when (and snap (< (1+ (hecl.buffer:point-line snap))
                           (hecl.buffer:line-count snap)))
          (let* ((new-line (1+ (hecl.buffer:point-line snap)))
                 (new-col (min (hecl.buffer:point-col snap)
                               (length (fset:@ (hecl.buffer:lines snap) new-line)))))
            (sento.actor:tell buf (list :move-point new-line new-col))))))))

(defun move-point-left ()
  (let ((buf hecl.buffer:*current-buffer*))
    (when buf
      (let ((snap (focused-snap)))
        (when snap
          (cond
            ((plusp (hecl.buffer:point-col snap))
             (sento.actor:tell buf (list :move-point
                                         (hecl.buffer:point-line snap)
                                         (1- (hecl.buffer:point-col snap)))))
            ((plusp (hecl.buffer:point-line snap))
             (let* ((new-line (1- (hecl.buffer:point-line snap)))
                    (new-col (length (fset:@ (hecl.buffer:lines snap) new-line))))
               (sento.actor:tell buf (list :move-point new-line new-col))))))))))

(defun move-point-right ()
  (let ((buf hecl.buffer:*current-buffer*))
    (when buf
      (let ((snap (focused-snap)))
        (when snap
          (let ((line-len (length (fset:@ (hecl.buffer:lines snap)
                                          (hecl.buffer:point-line snap)))))
            (cond
              ((< (hecl.buffer:point-col snap) line-len)
               (sento.actor:tell buf (list :move-point
                                           (hecl.buffer:point-line snap)
                                           (1+ (hecl.buffer:point-col snap)))))
              ((< (1+ (hecl.buffer:point-line snap))
                  (hecl.buffer:line-count snap))
               (sento.actor:tell buf (list :move-point
                                           (1+ (hecl.buffer:point-line snap))
                                           0))))))))))

(defun scroll-window (delta)
  "Scroll focused window by DELTA lines. Positive = down, negative = up.
Adjusts point to stay visible."
  (let ((w hecl.buffer:*focused-window*)
        (buf hecl.buffer:*current-buffer*))
    (when (and w buf)
      (let ((snap (hecl.buffer:snap w)))
        (when (and snap (typep snap 'hecl.buffer:snapshot))
          (let* ((max-scroll (max 0 (- (hecl.buffer:line-count snap)
                                       (hecl.buffer:win-height w))))
                 (new-scroll (max 0 (min max-scroll
                                         (+ (hecl.buffer:scroll-top w) delta))))
                 (h (hecl.buffer:win-height w))
                 (pl (hecl.buffer:point-line snap))
                 (pc (hecl.buffer:point-col snap)))
            (setf (hecl.buffer:scroll-top w) new-scroll)
            ;; Keep point visible
            (cond
              ((< pl new-scroll)
               (sento.actor:tell buf (list :move-point new-scroll
                                           (min pc (length (fset:@ (hecl.buffer:lines snap) new-scroll))))))
              ((>= pl (+ new-scroll h))
               (let ((target (+ new-scroll h -1)))
                 (sento.actor:tell buf (list :move-point target
                                             (min pc (length (fset:@ (hecl.buffer:lines snap) target))))))))
            ;; Force re-render
            (sento.actor:tell hecl.render:*renderer* '(:force-render))))))))
