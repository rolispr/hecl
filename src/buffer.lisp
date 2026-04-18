(in-package :hecl.buffer)

;;;; buffers
(defclass buffer-state ()
  ((lines :initarg :lines :accessor lines :initform (fset:seq ""))
   (marks :initarg :marks :accessor marks :initform (fset:empty-map))
   (meta  :initarg :meta  :accessor meta  :initform (fset:empty-map))
   (tick  :initarg :tick  :accessor tick  :initform 0)))

(defclass snapshot ()
  ((name       :initarg :name       :accessor name       :initform "")
   (tick       :initarg :tick       :accessor tick       :initform 0)
   (lines      :initarg :lines      :accessor lines      :initform (fset:seq ""))
   (line-count :initarg :line-count :accessor line-count  :initform 1)
   (point-line :initarg :point-line :accessor point-line  :initform 0)
   (point-col  :initarg :point-col  :accessor point-col   :initform 0)
   (highlights :initarg :highlights :accessor highlights  :initform nil)))

(defun make-empty-state (name)
  (let ((s (make-instance 'buffer-state)))
    (setf (meta s) (fset:with (meta s) :name name))
    s))

(defun state->snapshot (state)
  (let ((ls (lines state))
        (ms (marks state)))
    (make-instance 'snapshot
                   :name (or (fset:@ (meta state) :name) "")
                   :tick (tick state)
                   :lines ls
                   :line-count (max 1 (fset:size ls))
                   :point-line (or (fset:@ ms :point-line) 0)
                   :point-col (or (fset:@ ms :point-charpos) 0))))

(defun state->snapshot-with-hl (state hl)
  "Create snapshot including highlights."
  (let ((snap (state->snapshot state)))
    (setf (highlights snap) hl)
    snap))

(defun state->string (state)
  (let ((ls (lines state)))
    (with-output-to-string (s)
                           (loop for i from 0 below (fset:size ls)
                                 do (when (plusp i) (write-char #\Newline s))
                                 (write-string (fset:@ ls i) s)))))

(defun copy-state (state &key (lines nil lines-p) (marks nil marks-p)
                         (meta nil meta-p) (tick nil tick-p))
  (make-instance 'buffer-state
                 :lines (if lines-p lines (lines state))
                 :marks (if marks-p marks (marks state))
                 :meta  (if meta-p meta (meta state))
                 :tick  (if tick-p tick (tick state))))


(defun split-on-newlines (string)
  (loop with start = 0
        for i from 0 below (length string)
        when (char= (char string i) #\Newline)
        collect (subseq string start i) into parts
        and do (setf start (1+ i))
        finally (return (append parts (list (subseq string start))))))

(defgeneric insert-string (state line-idx col string))

(defmethod insert-string ((state buffer-state) line-idx col string)
           (let* ((ls (lines state))
                  (old (if (< line-idx (fset:size ls)) (fset:@ ls line-idx) ""))
                  (c (min col (length old)))
                  (new (concatenate 'string (subseq old 0 c) string (subseq old c))))
             (copy-state state
                         :lines (fset:with ls line-idx new)
                         :marks (let ((m (marks state)))
                                  (fset:with (fset:with m :point-line line-idx)
                                             :point-charpos (+ c (length string))))
                         :tick (1+ (tick state)))))

(defgeneric insert-char (state line-idx col char))

(defmethod insert-char ((state buffer-state) line-idx col char)
           (insert-string state line-idx col (string char)))

(defgeneric insert-newline (state line-idx col))

(defmethod insert-newline ((state buffer-state) line-idx col)
           (let* ((ls (lines state))
                  (old (fset:@ ls line-idx))
                  (c (min col (length old)))
                  (before (subseq old 0 c))
                  (after (subseq old c))
                  (built (fset:empty-seq)))
             (loop for i from 0 below (fset:size ls)
                   do (if (= i line-idx)
                          (progn
                            (setf built (fset:with-last built before))
                            (setf built (fset:with-last built after)))
                        (setf built (fset:with-last built (fset:@ ls i)))))
             (when (zerop (fset:size ls))
               (setf built (fset:with-last (fset:with-last built "") "")))
             (copy-state state
                         :lines built
                         :marks (fset:with (fset:with (marks state)
                                                      :point-line (1+ line-idx))
                                           :point-charpos 0)
                         :tick (1+ (tick state)))))

(defgeneric delete-char (state line-idx col))

(defmethod delete-char ((state buffer-state) line-idx col)
           (let* ((ls (lines state))
                  (line (fset:@ ls line-idx))
                  (len (length line)))
             (cond
              ((< col len)
               (let ((new (concatenate 'string (subseq line 0 col) (subseq line (1+ col)))))
                 (copy-state state
                             :lines (fset:with ls line-idx new)
                             :tick (1+ (tick state)))))
              ((< (1+ line-idx) (fset:size ls))
               (let* ((next (fset:@ ls (1+ line-idx)))
                      (joined (concatenate 'string line next))
                      (built (fset:empty-seq)))
                 (loop for i from 0 below (fset:size ls)
                       do (cond ((= i line-idx) (setf built (fset:with-last built joined)))
                                ((= i (1+ line-idx)) nil)
                                (t (setf built (fset:with-last built (fset:@ ls i))))))
                 (copy-state state :lines built :tick (1+ (tick state)))))
              (t state))))

(defgeneric delete-region (state start-line start-col end-line end-col))

(defmethod delete-region ((state buffer-state) start-line start-col end-line end-col)
           (let* ((ls (lines state))
                  (first-line (fset:@ ls start-line))
                  (last-line (fset:@ ls end-line))
                  (new-line (concatenate 'string
                                         (subseq first-line 0 (min start-col (length first-line)))
                                         (subseq last-line (min end-col (length last-line)))))
                  (built (fset:empty-seq)))
             (loop for i from 0 below (fset:size ls)
                   do (cond
                       ((= i start-line) (setf built (fset:with-last built new-line)))
                       ((and (> i start-line) (<= i end-line)) nil)
                       (t (setf built (fset:with-last built (fset:@ ls i))))))
             (copy-state state
                         :lines built
                         :marks (fset:with (fset:with (marks state) :point-line start-line)
                                           :point-charpos start-col)
                         :tick (1+ (tick state)))))

(defgeneric move-mark (state mark-name line-idx col))

(defmethod move-mark ((state buffer-state) mark-name line-idx col)
           (let ((key-line (intern (format nil "~a-LINE" mark-name) :keyword))
                 (key-col (intern (format nil "~a-CHARPOS" mark-name) :keyword)))
             (copy-state state
                         :marks (fset:with (fset:with (marks state) key-line line-idx) key-col col))))

(defgeneric set-meta (state key value))

(defmethod set-meta ((state buffer-state) key value)
           (copy-state state :meta (fset:with (meta state) key value)))

(defun line-count-of (state)
  (fset:size (lines state)))

(defun line-at (state line-idx)
  (fset:@ (lines state) line-idx))

(defun region-string (state start-line start-col end-line end-col)
  (if (= start-line end-line)
      (let ((line (fset:@ (lines state) start-line)))
        (subseq line (min start-col (length line)) (min end-col (length line))))
    (with-output-to-string (s)
                           (let ((first (fset:@ (lines state) start-line)))
                             (write-string (subseq first (min start-col (length first))) s))
                           (loop for i from (1+ start-line) below end-line
                                 do (write-char #\Newline s)
                                 (write-string (fset:@ (lines state) i) s))
                           (write-char #\Newline s)
                           (let ((last (fset:@ (lines state) end-line)))
                             (write-string (subseq last 0 (min end-col (length last))) s)))))


;;;; UI Node

(defclass node ()
  ((key-of  :initarg :key    :accessor key-of  :initform nil)
   (parent  :initarg :parent :accessor parent  :initform nil)
   (start-line :initform 0 :accessor start-line)
   (start-col  :initform 0 :accessor start-col)
   (end-line   :initform 0 :accessor end-line)
   (end-col    :initform 0 :accessor end-col)))

(defclass text-node (node)
  ((content :initarg :content :accessor content :initform "")
   (face    :initarg :face    :accessor face    :initform nil)))

(defclass separator (node)
  ((sep-char :initarg :char :accessor sep-char :initform #\─)))

(defclass field (node)
  ((content       :initarg :content       :accessor content       :initform "")
   (prefix-length :initarg :prefix-length :accessor prefix-length :initform 0)
   (face          :initarg :face          :accessor face          :initform nil)
   (input-start-line :initform 0 :accessor input-start-line)
   (input-start-col  :initform 0 :accessor input-start-col)
   (input-end-line   :initform 0 :accessor input-end-line)
   (input-end-col    :initform 0 :accessor input-end-col)))

(defclass vstack (node)
  ((children :initarg :children :accessor children :initform nil)
   (spacing  :initarg :spacing  :accessor spacing  :initform 0)))

(defclass hstack (node)
  ((children :initarg :children :accessor children :initform nil)
   (spacing  :initarg :spacing  :accessor spacing  :initform 1)))

(defclass box (node)
  ((child    :initarg :child    :accessor child    :initform nil)
   (width-of :initarg :width    :accessor width-of :initform 0)
   (align    :initarg :align    :accessor align    :initform :left)
   (pad-char :initarg :pad      :accessor pad-char :initform #\space)))

(defclass selectable (node)
  ((child             :initarg :child    :accessor child             :initform nil)
   (data              :initarg :data     :accessor data              :initform nil)
   (selectedp         :initarg :selected :accessor selectedp         :initform nil)
   (prefix-selected   :initarg :prefix-selected   :accessor prefix-selected   :initform "> ")
   (prefix-unselected :initarg :prefix-unselected :accessor prefix-unselected :initform "  ")))

(defclass action (node)
  ((child    :initarg :child    :accessor child    :initform nil)
   (callback :initarg :callback :accessor callback :initform nil)))

(defclass list-node (node)
  ((items       :initarg :items       :accessor items       :initform nil)
   (item-fn     :initarg :item-fn     :accessor item-fn     :initform nil)
   (max-visible :initarg :max-visible :accessor max-visible :initform nil)))

(defclass grid (node)
  ((cells      :initarg :cells      :accessor cells      :initform nil)
   (col-widths :initarg :col-widths :accessor col-widths :initform nil)))


;;;; Scroll helper

(defun scroll-to-selection (sel offset max-vis)
  (when (minusp sel)
    (return-from scroll-to-selection (max 0 offset)))
  (let ((o offset))
    (when (>= sel (+ o max-vis)) (setf o (1+ (- sel max-vis))))
    (when (< sel o)              (setf o sel))
    (max 0 o)))


;;;; Tree container

(defclass ui-tree ()
  ((root        :initarg :root   :accessor root        :initform nil)
   (buffer-name :initarg :buffer :accessor buffer-name :initform nil)
   (state-of    :initarg :state  :accessor state-of    :initform nil)
   (tree-width  :initarg :width  :accessor tree-width  :initform 80)))


;;;; Tree Rendering

(defclass render-ctx ()
  ((ctx-lines :initform nil :accessor ctx-lines)
   (current   :initform ""  :accessor current-line)
   (line-idx  :initform 0   :accessor line-idx)
   (col       :initform 0   :accessor col)))

(defun ctx-emit (ctx text)
  (setf (current-line ctx) (concatenate 'string (current-line ctx) text))
  (incf (col ctx) (length text)))

(defun ctx-emit-char (ctx char)
  (ctx-emit ctx (string char)))

(defun ctx-newline (ctx)
  (push (current-line ctx) (ctx-lines ctx))
  (setf (current-line ctx) "")
  (incf (line-idx ctx))
  (setf (col ctx) 0))

(defun ctx-position (ctx)
  (values (line-idx ctx) (col ctx)))

(defun ctx-finalize (ctx)
  (nreverse (cons (current-line ctx) (ctx-lines ctx))))

(defun render-tree (tree)
  (let ((ctx (make-instance 'render-ctx))
        (w (tree-width tree)))
    (render-node (root tree) ctx w)
    (ctx-finalize ctx)))

(defun render-tree-to-seq (tree)
  (reduce (lambda (seq line) (fset:with-last seq line))
          (render-tree tree)
          :initial-value (fset:empty-seq)))

(defgeneric render-node (node ctx width))

(defmacro with-node-bounds (node ctx &body body)
  `(progn
     (multiple-value-bind (l c) (ctx-position ,ctx)
                          (setf (start-line ,node) l (start-col ,node) c))
     ,@body
     (multiple-value-bind (l c) (ctx-position ,ctx)
                          (setf (end-line ,node) l (end-col ,node) c))))

(defmethod render-node ((n text-node) ctx width)
           (declare (ignore width))
           (with-node-bounds n ctx
                             (when (plusp (length (content n)))
                               (ctx-emit ctx (content n)))))

(defmethod render-node ((n separator) ctx width)
           (with-node-bounds n ctx
                             (ctx-emit ctx (make-string width :initial-element (sep-char n)))))

(defmethod render-node ((n field) ctx width)
           (declare (ignore width))
           (with-node-bounds n ctx
                             (let* ((c (content n))
                                    (plen (prefix-length n)))
                               (when (plusp plen)
                                 (ctx-emit ctx (subseq c 0 (min plen (length c)))))
                               (multiple-value-bind (l col) (ctx-position ctx)
                                                    (setf (input-start-line n) l (input-start-col n) col))
                               (when (< plen (length c))
                                 (ctx-emit ctx (subseq c plen)))
                               (multiple-value-bind (l col) (ctx-position ctx)
                                                    (setf (input-end-line n) l (input-end-col n) col)))))

(defmethod render-node ((n vstack) ctx width)
           (with-node-bounds n ctx
                             (let ((sp (spacing n)))
                               (loop for (ch . rest) on (children n)
                                     do (setf (parent ch) n)
                                     (render-node ch ctx width)
                                     (when rest
                                       (ctx-newline ctx)
                                       (dotimes (_ sp) (ctx-newline ctx)))))))

(defmethod render-node ((n hstack) ctx width)
           (with-node-bounds n ctx
                             (let ((sp (spacing n))
                                   (used 0))
                               (loop for (ch . rest) on (children n)
                                     do (setf (parent ch) n)
                                     (let ((before (col ctx)))
                                       (render-node ch ctx (- width used))
                                       (incf used (- (col ctx) before)))
                                     (when rest
                                       (dotimes (_ sp)
                                         (ctx-emit-char ctx #\space)
                                         (incf used)))))))

(defmethod render-node ((n box) ctx width)
           (declare (ignore width))
           (with-node-bounds n ctx
                             (let* ((bw (width-of n))
                                    (ch (child n))
                                    (al (align n))
                                    (pc (pad-char n)))
                               (if ch
                                   (let* ((str (render-node-to-string ch bw))
                                          (len (length str))
                                          (padded (if (>= len bw)
                                                      (subseq str 0 bw)
                                                    (let ((pt (- bw len)))
                                                      (ecase al
                                                             (:left (concatenate 'string str (make-string pt :initial-element pc)))
                                                             (:right (concatenate 'string (make-string pt :initial-element pc) str))
                                                             (:center (let ((l (floor pt 2)) (r (ceiling pt 2)))
                                                                        (concatenate 'string
                                                                                     (make-string l :initial-element pc) str
                                                                                     (make-string r :initial-element pc)))))))))
                                     (ctx-emit ctx padded))
                                 (ctx-emit ctx (make-string bw :initial-element pc))))))

(defmethod render-node ((n selectable) ctx width)
           (with-node-bounds n ctx
                             (let* ((sel (selectedp n))
                                    (prefix (if sel (prefix-selected n) (prefix-unselected n)))
                                    (ch (child n)))
                               (ctx-emit ctx prefix)
                               (when ch
                                 (setf (parent ch) n)
                                 (render-node ch ctx (- width (length prefix)))))))

(defmethod render-node ((n action) ctx width)
           (with-node-bounds n ctx
                             (when (child n)
                               (setf (parent (child n)) n)
                               (render-node (child n) ctx width))))

(defmethod render-node ((n list-node) ctx width)
           (with-node-bounds n ctx
                             (let* ((is (items n))
                                    (mx (max-visible n))
                                    (fn (item-fn n))
                                    (vis (if mx (subseq is 0 (min mx (length is))) is)))
                               (loop for (item . rest) on vis
                                     for idx from 0
                                     for ch = (funcall fn item idx)
                                     do (setf (parent ch) n)
                                     (render-node ch ctx width)
                                     (when rest (ctx-newline ctx))))))

(defmethod render-node ((n grid) ctx width)
           (declare (ignore width))
           (with-node-bounds n ctx
                             (let ((cw (col-widths n)))
                               (loop for (row . more) on (cells n)
                                     do (loop for cell in row
                                              for w in cw
                                              do (setf (parent cell) n)
                                              (let ((c0 (col ctx)))
                                                (render-node cell ctx w)
                                                (let ((written (- (col ctx) c0)))
                                                  (cond
                                                   ((< written w)
                                                    (ctx-emit ctx (make-string (- w written) :initial-element #\space)))
                                                   ((> written w)
                                                    (let* ((ln (current-line ctx))
                                                           (keep (+ c0 w)))
                                                      (setf (current-line ctx) (subseq ln 0 (min keep (length ln))))
                                                      (setf (col ctx) keep)))))))
                                     (when more (ctx-newline ctx))))))

(defun render-node-to-string (n width)
  (when (and (typep n 'text-node) (null (face n)))
    (let ((s (content n)))
      (return-from render-node-to-string
                   (if (<= (length s) width) s (subseq s 0 width)))))
  (let ((ctx (make-instance 'render-ctx)))
    (render-node n ctx width)
    (current-line ctx)))


;;;; Tree State, Input, Selection

(defvar *buffer-tree-table* (make-hash-table :test #'equal))

(defun install-tree (tree)
  (setf (gethash (buffer-name tree) *buffer-tree-table*) tree))

(defun uninstall-tree (tree)
  (remhash (buffer-name tree) *buffer-tree-table*))

(defun buffer-ui-tree (name)
  (gethash name *buffer-tree-table*))

(defun tree-get (tree key &optional default)
  (getf (state-of tree) key default))

(defun (setf tree-get) (value tree key)
  (setf (getf (state-of tree) key) value)
  value)


;;;; Input string operations

(defun input-string (tree)
  (getf (state-of tree) :input ""))

(defun (setf input-string) (val tree)
  (setf (getf (state-of tree) :input) val))

(defun cursor-offset (tree)
  (let ((input (input-string tree)))
    (min (getf (state-of tree) :cursor-offset (length input))
         (length input))))

(defun (setf cursor-offset) (val tree)
  (setf (getf (state-of tree) :cursor-offset) val))

(defun type-char-at-cursor (tree char)
  (let* ((input (input-string tree))
         (off (cursor-offset tree)))
    (setf (input-string tree)
          (concatenate 'string (subseq input 0 off) (string char) (subseq input off)))
    (setf (cursor-offset tree) (1+ off))))

(defun delete-char-before-cursor (tree)
  (let* ((input (input-string tree))
         (off (cursor-offset tree)))
    (when (plusp off)
      (setf (input-string tree)
            (concatenate 'string (subseq input 0 (1- off)) (subseq input off)))
      (setf (cursor-offset tree) (1- off))
      t)))

(defun kill-input (tree)
  (setf (input-string tree) ""
        (cursor-offset tree) 0))

(defun kill-to-end (tree)
  (let ((off (cursor-offset tree)))
    (setf (input-string tree) (subseq (input-string tree) 0 off))))

(defun find-word-start (input offset &optional (sep #\space))
  (let* ((pos (loop for i from (1- offset) downto 0
                    while (eql (char input i) sep)
                    finally (return (1+ i)))))
    (loop for i from (1- pos) downto 0
          while (not (eql (char input i) sep))
          finally (return (1+ i)))))

(defun kill-word-before-cursor (tree &optional (sep #\space))
  (let* ((input (input-string tree))
         (off (cursor-offset tree))
         (ws (find-word-start input off sep)))
    (setf (input-string tree)
          (concatenate 'string (subseq input 0 ws) (subseq input off)))
    (setf (cursor-offset tree) ws)))

(defun set-input (tree text)
  (setf (input-string tree) (or text "")
        (cursor-offset tree) (length (or text ""))))

(defun move-cursor (tree delta)
  (let* ((input (input-string tree))
         (off (cursor-offset tree))
         (new (max 0 (min (length input) (+ off delta)))))
    (setf (cursor-offset tree) new)))

(defun cursor-to-start (tree)
  (setf (cursor-offset tree) 0))

(defun cursor-to-end (tree)
  (setf (cursor-offset tree) (length (input-string tree))))

(defun confirm-input (tree)
  (let ((sel (getf (state-of tree) :selection -1))
        (filtered (getf (state-of tree) :filtered)))
    (if (and (>= sel 0) (< sel (length filtered)))
        (nth sel filtered)
      (input-string tree))))


;;;; Selection navigation

(defun collect-selectables (n)
  (let ((result nil))
    (labels ((walk (x)
                   (when x
                     (typecase x
                               (selectable (push x result))
                               (vstack (mapc #'walk (children x)))
                               (hstack (mapc #'walk (children x)))
                               (box (walk (child x)))
                               (grid (dolist (row (cells x)) (mapc #'walk row)))
                               (action (walk (child x)))
                               (t nil)))))
            (walk n))
    (nreverse result)))

(defun update-selection (tree index)
  (let* ((sels (collect-selectables (root tree)))
         (n (length sels)))
    (when (zerop n) (return-from update-selection nil))
    (setf index (mod index n))
    (setf (tree-get tree :selection-index) index)
    (loop for s in sels for i from 0
          do (setf (selectedp s) (= i index)))
    (nth index sels)))

(defun selected-node (tree)
  (let ((idx (tree-get tree :selection-index 0)))
    (let ((sels (collect-selectables (root tree))))
      (when sels (nth (mod idx (length sels)) sels)))))

(defun selection-move (tree delta)
  (let ((idx (tree-get tree :selection-index 0)))
    (update-selection tree (+ idx delta))))


;;;; Buffer Actor

(defun load-content (content)
  (let ((state (make-empty-state "tmp")))
    (if (string= content "")
        state
      (let ((ls (split-on-newlines content)))
        (loop with s = state
              for line in ls
              for i from 0
              do (if (zerop i)
                     (when (plusp (length line))
                       (setf s (insert-string s 0 0 line)))
                   (progn
                     (let* ((snap (state->snapshot s))
                            (last (1- (line-count snap)))
                            (last-col (length (fset:@ (lines s) last))))
                       (setf s (insert-newline s last last-col)))
                     (when (plusp (length line))
                       (let* ((snap (state->snapshot s))
                              (last (1- (line-count snap))))
                         (setf s (insert-string s last 0 line))))))
              finally (return s))))))

(defun make-buffer-actor (system name &key (content ""))
  (let ((initial (set-meta (load-content content) :name name)))
    (sento.actor-context:actor-of system
                                  :name (format nil "buffer:~a" name)
                                  :state (list initial nil nil nil)
                                  :receive
                                  (lambda (msg)
                                    (destructuring-bind (state undo-ring subscribers hl-cache) sento.actor:*state*
                                                        (flet ((update (new-state)
                                                                       (setf sento.actor:*state*
                                                                             (list new-state (cons state undo-ring) subscribers hl-cache))
                                                                       (notify-subscribers subscribers new-state hl-cache))
                                                               (set-st (new-state)
                                                                       (setf sento.actor:*state*
                                                                             (list new-state undo-ring subscribers hl-cache))
                                                                       (notify-subscribers subscribers new-state hl-cache)))
                                                              (case (first msg)
                                                                    (:insert
                                                                     (let* ((snap (state->snapshot state))
                                                                            (l (point-line snap)) (c (point-col snap)))
                                                                       (update (insert-string state l c (cadr msg)))))

                                                                    (:newline
                                                                     (let* ((snap (state->snapshot state))
                                                                            (l (point-line snap)) (c (point-col snap)))
                                                                       (update (insert-newline state l c))))

                                                                    (:backspace
                                                                     (let* ((snap (state->snapshot state))
                                                                            (l (point-line snap)) (c (point-col snap)))
                                                                       (cond
                                                                        ((plusp c)
                                                                         (update (move-mark (delete-char state l (1- c))
                                                                                            :point l (1- c))))
                                                                        ((plusp l)
                                                                         (let ((prev-len (length (fset:@ (lines state) (1- l)))))
                                                                           (update (move-mark (delete-char state (1- l) prev-len)
                                                                                              :point (1- l) prev-len)))))))

                                                                    (:move-point
                                                                     (set-st (move-mark state :point (cadr msg) (caddr msg))))

                                                                    (:delete-region
                                                                     (update (delete-region state (cadr msg) (caddr msg)
                                                                                            (cadddr msg) (nth 4 msg))))

                                                                    (:undo
                                                                     (when undo-ring
                                                                       (let ((prev (first undo-ring)))
                                                                         (setf sento.actor:*state*
                                                                               (list prev (cdr undo-ring) subscribers hl-cache))
                                                                         (notify-subscribers subscribers prev hl-cache))))

                                                                    (:subscribe
                                                                     (let ((sub (cadr msg)))
                                                                       (setf sento.actor:*state*
                                                                             (list state undo-ring (cons sub subscribers) hl-cache))
                                                                       (funcall sub (state->snapshot-with-hl state hl-cache))))

                                                                    (:unsubscribe
                                                                     (let ((sub (cadr msg)))
                                                                       (setf sento.actor:*state*
                                                                             (list state undo-ring (remove sub subscribers) hl-cache))))

                                                                    (:highlights
                                                                     (let ((hl (cadr msg)))
                                                                       (setf hl-cache hl
                                                                             sento.actor:*state*
                                                                             (list state undo-ring subscribers hl))
                                                                       (notify-subscribers subscribers state hl)))

                                                                    (:get-text (sento.actor:reply (state->string state)))
                                                                    (:get-state (sento.actor:reply state))
                                                                    (:get-snapshot (sento.actor:reply (state->snapshot state)))

                                                                    (:set-meta
                                                                     (set-st (set-meta state (cadr msg) (caddr msg))))

                                                                    (:replace-content
                                                                     (let ((new (set-meta (load-content (cadr msg))
                                                                                          :name (or (fset:@ (meta state) :name) ""))))
                                                                       (set-st new))))))))))

(defun notify-subscribers (subscribers state &optional hl)
  (let ((snap (state->snapshot-with-hl state hl)))
    (loop for fn in subscribers
          do (handler-case (funcall fn snap)
               (error () nil)))))


;;;; Buffer Registry

(defvar *buffer-registry* nil)
(defvar *current-buffer* nil)

(defun start-buffer-registry ()
  (setf *buffer-registry*
        (sento.actor-context:actor-of hecl.actor:*actor-system*
                                      :name "buffer-registry"
                                      :state (fset:empty-map)
                                      :receive
                                      (lambda (msg)
                                        (case (car msg)
                                              (:register
                                               (let ((name (cadr msg)) (actor (caddr msg)))
                                                 (setf sento.actor:*state* (fset:with sento.actor:*state* name actor))
                                                 (sento.actor:reply actor)))
                                              (:unregister
                                               (setf sento.actor:*state* (fset:less sento.actor:*state* (cadr msg)))
                                               (sento.actor:reply t))
                                              (:lookup
                                               (sento.actor:reply (fset:@ sento.actor:*state* (cadr msg))))
                                              (:list
                                               (let ((names nil))
                                                 (fset:do-map (k v sento.actor:*state*)
                                                              (declare (ignore v))
                                                              (push k names))
                                                 (sento.actor:reply (nreverse names))))
                                              (:count
                                               (sento.actor:reply (fset:size sento.actor:*state*))))))))

(defvar *buffer-table* (make-hash-table :test 'equal)
  "Local name→actor map. No actor round-trip needed for lookups.")

(defun make-buffer (name &key (content ""))
  ;; Return existing buffer if already open
  (let ((existing (gethash name *buffer-table*)))
    (when existing (return-from make-buffer existing)))
  (let ((actor (make-buffer-actor hecl.actor:*actor-system* name :content content)))
    (setf (gethash name *buffer-table*) actor)
    (sento.actor:tell *buffer-registry* (list :register name actor))
    (unless *current-buffer*
      (setf *current-buffer* actor))
    actor))

(defun kill-buffer (name)
  (let ((actor (gethash name *buffer-table*)))
    (when actor
      (when (eq actor *current-buffer*) (setf *current-buffer* nil))
      (remhash name *buffer-table*)
      (sento.actor-context:stop hecl.actor:*actor-system* actor)
      (sento.actor:tell *buffer-registry* (list :unregister name)))))

(defun switch-buffer (name)
  "Like Emacs set-buffer: sets *current-buffer* only."
  (let ((actor (gethash name *buffer-table*)))
    (when actor (setf *current-buffer* actor) actor)))


(defun list-buffers ()
  (loop for k being the hash-keys of *buffer-table* collect k))

(defun buffer-count ()
  (hash-table-count *buffer-table*))

(defun current-buffer-text ()
  (when *current-buffer*
    (sento.actor:ask-s *current-buffer* '(:get-text) :time-out 5)))

(defun current-buffer-snapshot ()
  (when *current-buffer*
    (sento.actor:ask-s *current-buffer* '(:get-snapshot) :time-out 5)))
