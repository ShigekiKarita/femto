(+ 1 2)

(defun f (x) (+ x 1))

(f 2)

(defun assert (b)
  (if b t (error '|fail|)))

(assert (eq (+ 1 2) 3))
