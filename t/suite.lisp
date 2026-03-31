(in-package #:hecl/tests)

(test system-boots
  (let ((sys (sento.actor-system:make-actor-system)))
    (unwind-protect
         (is (not (null sys)))
      (sento.actor-context:shutdown (sento.actor-system:actor-system sys)))))

(test config-target
  (is (typep hecl/config:*target* 'hecl/config::target))
  (is (hecl/config:desktopP)))
