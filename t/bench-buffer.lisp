(load (merge-pathnames "../init.lisp" *load-truename*))
(asdf:load-system :hecl)
(hecl:main :workers 2 :remoting-port nil)

(format t "~%=== hecl buffer benchmarks on ~a ~a ===~%~%" (lisp-implementation-type) (lisp-implementation-version))

(let ((buf hecl.buffer:*current-buffer*))

  (format t "1. 10000 single-char inserts (tell, async)... ")
  (force-output)
  (let ((t0 (get-internal-real-time)))
    (loop for i from 0 below 10000
          do (sento.actor:tell buf (list :insert "x")))
    (sento.actor:ask-s buf '(:get-text) :time-out 30)
    (let ((elapsed (/ (float (- (get-internal-real-time) t0)) internal-time-units-per-second)))
      (format t "~,4f s (~,0f ops/s)~%" elapsed (/ 10000.0 elapsed))))

  (sento.actor:tell buf '(:undo))
  (sleep 0.1)

  (format t "2. 10000 single-char inserts (ask-s, sync)... ")
  (force-output)
  (hecl.buffer:make-buffer "sync-bench")
  (hecl.buffer:switch-buffer "sync-bench")
  (let ((buf2 hecl.buffer:*current-buffer*)
        (t0 (get-internal-real-time)))
    (loop for i from 0 below 10000
          do (sento.actor:ask-s buf2 (list :insert "y") :time-out 5))
    (let ((elapsed (/ (float (- (get-internal-real-time) t0)) internal-time-units-per-second)))
      (format t "~,4f s (~,0f ops/s)~%" elapsed (/ 10000.0 elapsed))))

  (format t "3. 1000 line inserts (newlines)... ")
  (force-output)
  (hecl.buffer:make-buffer "lines-bench")
  (hecl.buffer:switch-buffer "lines-bench")
  (let ((buf3 hecl.buffer:*current-buffer*)
        (t0 (get-internal-real-time)))
    (loop for i from 0 below 1000
          do (sento.actor:tell buf3 (list :insert (format nil "line ~a content here" i)))
             (sento.actor:tell buf3 '(:newline)))
    (sento.actor:ask-s buf3 '(:get-text) :time-out 30)
    (let ((elapsed (/ (float (- (get-internal-real-time) t0)) internal-time-units-per-second)))
      (format t "~,4f s (~,0f ops/s)~%" elapsed (/ 2000.0 elapsed))))

  (format t "4. 5000 backspace deletes... ")
  (force-output)
  (hecl.buffer:switch-buffer "sync-bench")
  (let ((buf4 hecl.buffer:*current-buffer*)
        (t0 (get-internal-real-time)))
    (loop for i from 0 below 5000
          do (sento.actor:tell buf4 '(:backspace)))
    (sento.actor:ask-s buf4 '(:get-text) :time-out 30)
    (let ((elapsed (/ (float (- (get-internal-real-time) t0)) internal-time-units-per-second)))
      (format t "~,4f s (~,0f ops/s)~%" elapsed (/ 5000.0 elapsed))))

  (format t "5. 1000 undos... ")
  (force-output)
  (hecl.buffer:switch-buffer "sync-bench")
  (let ((buf5 hecl.buffer:*current-buffer*)
        (t0 (get-internal-real-time)))
    (loop for i from 0 below 1000
          do (sento.actor:tell buf5 '(:undo)))
    (sento.actor:ask-s buf5 '(:get-text) :time-out 30)
    (let ((elapsed (/ (float (- (get-internal-real-time) t0)) internal-time-units-per-second)))
      (format t "~,4f s (~,0f ops/s)~%" elapsed (/ 1000.0 elapsed))))

  (format t "6. pure FSet state ops (no actors)... ")
  (force-output)
  (let ((state (hecl.buffer:make-empty-state "raw"))
        (t0 (get-internal-real-time)))
    (loop for i from 0 below 10000
          do (setf state (hecl.buffer:insert-string state 0
                           (length (fset:@ (hecl.buffer:lines state) 0))
                           "x")))
    (let ((elapsed (/ (float (- (get-internal-real-time) t0)) internal-time-units-per-second)))
      (format t "~,4f s (~,0f ops/s)~%" elapsed (/ 10000.0 elapsed)))))

(hecl:stop)
(format t "~%done~%")
(ext:quit 0)
