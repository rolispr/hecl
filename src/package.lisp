(defpackage :hecl.actor
  (:use :cl :ac :act :asys :rem)
  (:export
   #:*actor-system*
   #:*remoting-port*
   #:start-actor-system
   #:stop-actor-system
   #:*agent-registry*
   #:agent-info
   #:agent-info-name #:agent-info-type #:agent-info-actor
   #:agent-info-meta #:agent-info-port
   #:start-agent-registry
   #:register-agent #:unregister-agent #:find-agent #:list-agents
   #:agent-eval #:agent-compile
   #:*local-agent*
   #:start-local-agent
   #:spawn-agent #:kill-agent))

(defpackage :hecl.event
  (:use :cl)
  (:export
   #:*event-bus*
   #:make-event-bus
   #:publish
   #:subscribe
   #:unsubscribe))

(defpackage :hecl.hooks
  (:use :cl)
  (:export
   #:*init-hooks*
   #:*shutdown-hooks*
   #:add-init-hook
   #:add-shutdown-hook
   #:run-init-hooks
   #:run-shutdown-hooks))

(defpackage :hecl.buffer
  (:use :cl)
  (:export
   ;; buffer-state
   #:buffer-state #:lines #:marks #:meta #:tick
   ;; snapshot
   #:snapshot #:name #:line-count #:point-line #:point-col #:highlights
   ;; state ops
   #:make-empty-state #:state->snapshot #:state->string
   #:insert-char #:insert-string #:insert-newline
   #:delete-char #:delete-region
   #:move-mark #:set-meta
   #:line-count-of #:line-at #:region-string
   ;; faces
   #:face #:fg #:bg #:bold #:italic #:underline
   #:defface #:find-face #:face-to-plist #:*faces*
   #:face-run #:run-start #:run-end #:run-face
   #:display-line #:display-text #:display-runs
   #:make-display-line #:display-line-to-plist
   ;; nodes
   #:node #:key-of #:parent #:start-line #:start-col #:end-line #:end-col
   #:text-node #:content #:face
   #:separator #:sep-char
   #:field #:prefix-length
   #:input-start-line #:input-start-col #:input-end-line #:input-end-col
   #:vstack #:children #:spacing
   #:hstack
   #:box #:child #:width-of #:align #:pad-char
   #:selectable #:data #:selectedp #:prefix-selected #:prefix-unselected
   #:action #:callback
   #:list-node #:items #:item-fn #:max-visible
   #:grid #:cells #:col-widths
   ;; tree
   #:ui-tree #:root #:buffer-name #:state-of #:tree-width
   #:render-tree #:render-tree-to-seq #:render-node #:render-node-to-string
   #:*buffer-tree-table*
   #:install-tree #:uninstall-tree #:buffer-ui-tree #:tree-get
   #:input-string #:cursor-offset
   #:type-char-at-cursor #:delete-char-before-cursor
   #:kill-input #:kill-to-end #:kill-word-before-cursor
   #:set-input #:move-cursor #:cursor-to-start #:cursor-to-end
   #:confirm-input
   #:collect-selectables #:update-selection #:selected-node #:selection-move
   #:scroll-to-selection
   ;; windows
   #:window #:buffer-ref #:window-name #:row #:col #:win-width #:win-height
   #:scroll-top #:focusedp #:snap #:win-display
   #:frame #:windows #:frame-cols #:frame-rows #:bg-face
   #:frame-cells #:frame-cell-count #:frame-cursor-row #:frame-cursor-col
   #:frame-scroll-pixel #:frame-dirtyp #:ensure-frame-cells
   #:*frame* #:*windows* #:*focused-window*
   #:make-window #:remove-window #:focus-window
   #:window-display-lines #:ensure-point-visible #:ensure-col-visible
   #:build-frame #:frame-to-plist
   ;; buffer actor
   #:make-buffer-actor #:notify-subscribers #:load-content
   ;; registry
   #:*buffer-registry* #:*current-buffer*
   #:start-buffer-registry
   #:make-buffer #:kill-buffer #:switch-buffer
   #:list-buffers #:buffer-count
   #:current-buffer-text #:current-buffer-snapshot))

(defpackage :hecl.qml
  (:use :cl)
  (:export
   #:*ui-ready*
   #:init-ui
   #:find-item
   #:set-property
   #:push-frame
   #:set-cursor
   #:on-scroll
   #:report-resize
   #:update-status-text
   #:show-status-input
   #:hide-status-input
   #:show-completion-area
   #:hide-completion-area
   #:on-input-changed))

(defpackage :hecl.file
  (:use :cl)
  (:export
   #:read-file
   #:write-file
   #:find-file
   #:save-current-buffer))

(defpackage :hecl.render
  (:use :cl)
  (:export
   #:*renderer*
   #:*render-state*
   #:ts-request-parse
   #:start-renderer
   #:start-render-loop
   #:schedule-render
   #:make-subscriber
   #:subscribe-to-buffer
   #:unsubscribe-from-buffer
   #:relayout))

(defpackage :hecl.shell
  (:use :cl)
  (:export
   #:*repl-buffer*
   #:start-repl
   #:repl-eval
   #:repl-submit))

(defpackage :hecl.ts
  (:use :cl)
  (:export
   #:ensure-ts
   #:compute-highlights
   #:capture-name-to-face
   #:*ts-loaded*))

(defpackage :hecl.term
  (:use :cl)
  (:export
   #:terminal #:term-cols #:term-rows #:term-buffer
   #:*terminals* #:*terminal-map*
   #:terminal-destroy
   #:open-terminal
   #:terminal-for-buffer #:terminal-send-key #:terminal-send-special
   #:resize-active-terminal #:terminal-visible-p
   #:render-terminal-to-frame #:vec-to-list
   #:ensure-pushframe #:push-frame-direct
   #:with-gterm-cells))

(defpackage :hecl.editor
  (:use :cl)
  (:export
   #:start-editor
   #:focused-snap
   #:scroll-window
   #:on-key
   #:on-minibuffer-accept
   #:defcommand
   #:register-command
   #:bind-key
   #:run-command
   #:*commands*
   #:*mode*
   #:*last-command*
   ;; prompt
   #:prompt
   #:cancel-prompt
   ;; kill ring
   #:*kill-ring*
   #:kill-ring-push
   #:kill-ring-top
   #:set-mark
   #:region-bounds
   #:kill-region-cmd
   #:kill-line-cmd
   #:copy-region-cmd
   #:yank-cmd
   #:yank-pop-cmd
   ;; completing-read
   #:completing-read
   #:*completing*
   #:completion-accept
   #:completion-cancel
   #:completion-next
   #:completion-prev
   #:completion-update-input
   #:completing-read-active-p))

(defpackage :hecl
  (:use :cl)
  (:export
   #:main
   #:stop
   #:*system*
   #:*version*
   #:*target*
   #:desktop?
   #:mobile?
   #:on-key
   #:on-minibuffer-accept))
