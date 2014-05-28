#!/usr/bin/sbcl --script

(declaim (optimize (speed 3)
                   (compilation-speed 0)
                   (safety 0)
                   (debug 0)))

(defstruct fringe
  (minimum 0 :type integer)
  (key #'identity :type function)
  (elements (make-array 1024 :fill-pointer 0 :adjustable t) :type array)
  (hash-elements (make-hash-table)))

(defun fringe-existp (f item)
  (let ((elements (fringe-elements f))
	(hash-elements (fringe-hash-elements f))
        (key (funcall (fringe-key f) item)))
    ;; No need to consider case `key<minimum`
    (unless (<= (fill-pointer elements) key)
      (gethash item hash-elements))))

(defun fringe-remove (f)
  (let ((elements (fringe-elements f))
	(hash-elements (fringe-hash-elements f))
	(minimum (fringe-minimum f)))
    (loop while (null (aref elements minimum)) do
          (incf minimum 1))
    (setf (fringe-minimum f) minimum)
    (pop (aref elements minimum))))

(defun fringe-insert (f items)
  (mapc (lambda (item)
          (let ((elements (fringe-elements f))
		(hash-elements (fringe-hash-elements f))
		(key (funcall (fringe-key f) item)))
            (loop while (<= (fill-pointer elements) key) do
                  (vector-push-extend nil elements))
            (push item (aref elements key))
	    (push t (gethash item hash-elements))))
        items)
  f)

(defstruct node
  (state nil :type vector)
  (parent nil)
  (direction nil :type symbol)
  (path-cost 0 :type integer)
  (depth 0 :type integer))

(defun direction-sequence (node)
  (labels ((direction-sequence-iter (node directions)
             (if (null (node-parent node))
                 directions
               (direction-sequence-iter (node-parent node) (cons (node-direction node) directions)))))
    (direction-sequence-iter node nil)))

(defun A*-search (action heuristic goalp initial-state)
  (labels ((expand (node fringe)
             (remove-if (lambda (new-node)
                          (fringe-existp fringe new-node))
                        (mapcar (lambda (state-direction)
                                  (let* ((state (car state-direction))
                                         (direction (cdr state-direction))
                                         (cost (funcall heuristic state))
                                         (depth (1+ (node-depth node))))
                                    (make-node :state state
                                               :parent node
                                               :direction direction
                                               :path-cost (+ depth cost)
                                               :depth depth)))
                                (funcall action (node-state node) (node-direction node)))))
           (search-iter (fringe)
             (let ((node (fringe-remove fringe)))
               (if (funcall goalp (node-state node))
                   (list (direction-sequence node) (node-depth node))
                 (search-iter (fringe-insert fringe (expand node fringe)))))))
    (search-iter (fringe-insert (make-fringe :key #'node-path-cost)
                                (list (make-node :state initial-state
                                                 :path-cost (funcall heuristic initial-state)))))))

(defun IDA*-search (action heuristic goalp initial-state)
  (let ((max-cost-limit 105)
        (initial-node (make-node :state initial-state)))
    (labels ((expand (node)
               (mapcar (lambda (state-direction)
                         (let ((state (car state-direction))
                               (direction (cdr state-direction))
                               (depth (1+ (node-depth node))))
                           (make-node :state state
                                      :parent node
                                      :direction direction
                                      :depth depth)))
                       (funcall action (node-state node) (node-direction node))))
             (search-iter (fringe cost-limit next-cost-limit)
               (if (null fringe)
                   (search-iter (list initial-node) next-cost-limit max-cost-limit)
                 (let* ((node (car fringe))
                        (rst (cdr fringe))
                        (car-cost (+ (funcall heuristic (node-state node)) (node-depth node))))
                   (cond ((> car-cost cost-limit)
                          (search-iter rst cost-limit (min next-cost-limit car-cost)))
                         ((funcall goalp (node-state node))
                          (list (direction-sequence node) (node-depth node)))
                         (t
                          (search-iter (nconc (expand node) rst) cost-limit next-cost-limit)))))))
      (search-iter (list initial-node) (funcall heuristic initial-state) max-cost-limit))))

(defun manhattan (state)
  (declare (special *target*
                    *width*))
  (loop for square from 1 to (reduce #'max state) summing
        (multiple-value-bind (square-x square-y) (floor (position square state) *width*)
          (multiple-value-bind (*target*-x *target*-y) (floor (position square *target*) *width*)
            (+ (abs (- *target*-x square-x)) (abs (- *target*-y square-y)))))))

(defun misplaced (state)
  (declare (special *target*))
  (loop for i from 0 to (1- (length state)) counting
       (/= (aref state i)
	   (aref *target* i))))

(defun swap (state i j)
  ;; move 0 at i to position j with side-effect.
  (unless (= (aref state j) -1)
    (let ((temp-state (copy-seq state)))
      (rotatef (aref temp-state i) (aref temp-state j))
      temp-state)))

(defun move-blank (state direction)
  (declare (special *width*))
  (cons (case direction
          (UP
           (let ((i (position 0 state))
                 (j (- (position 0 state) *width*)))
             (when (>= j 0)
               (swap state i j))))
          (DOWN
           (let ((i (position 0 state))
                 (j (+ (position 0 state) *width*)))
             (when (< j (length state))
               (swap state i j))))
          (LEFT
           (let ((i (position 0 state))
                 (j (1- (position 0 state))))
             (unless (zerop (mod i *width*))
               (swap state i j))))
          (RIGHT
           (let ((i (position 0 state))
                 (j (1+ (position 0 state))))
             (unless (zerop (mod (1+ i) *width*))
               (swap state i j)))))
        direction))

(defparameter *width* 3)

(defparameter *target* (vector 0 1 2
                               3 4 5
                               6 7 8))

(defparameter *start* (vector 5 1 8
                              7 2 3
                              0 6 4))

(defun goalp (node)
  (equalp node *target*))

(defun action (old-state old-direction)
  ;; return a dotted list (state . direction)
  (remove nil
          (mapcar (lambda (direction)
                    (move-blank old-state direction))
                  (remove (case old-direction
                            (UP 'DOWN)
                            (DOWN 'UP)
                            (RIGHT 'LEFT)
                            (LEFT 'RIGHT))
                          '(UP DOWN RIGHT LEFT)))
          :key #'car))


(defun n-puzzle (search heuristic initial-state)
  (funcall search #'action heuristic #'goalp initial-state))

(format t "IDA*-search~%")
(time (format t "~A~%" (n-puzzle #'IDA*-search
                                 #'manhattan
                                 *start*)))

(format t "A*-search~%")
(time (format t "~A~%" (n-puzzle #'A*-search
                                 #'manhattan
                                 *start*)))
