#!/usr/bin/env sbcl --script

(declaim (optimize (speed 3)
                   (compilation-speed 0)
                   (safety 0)
                   (debug 0)))

(defstruct fringe
  (state #'identity :type function :read-only t)
  (key #'identity :type function :read-only t)
  ;; Shadow slots, only can be modified by #'fringe-*.
  (extends (vector nil nil nil) :type (simple-array list (3)))
  (minimum 0 :type integer)
  (searched (make-hash-table) :type hash-table))

(defun fringe-exist-state-p (f state)
  (let ((searched (fringe-searched f)))
    (gethash state searched)))

(defun fringe-remove (f)
  (let ((extends (fringe-extends f)))
    (if (null (aref extends 0))
	(progn
	  (incf (fringe-minimum f))
	  (setf (aref extends 0) (aref extends 1))
	  (setf (aref extends 1) (aref extends 2))
	  (setf (aref extends 2) nil)
	  (fringe-remove f))
	(pop (aref extends 0)))))

(defun fringe-start (f item)
  (let ((extends (fringe-extends f))
	(searched (fringe-searched f))
	(key (funcall (fringe-key f) item))
	(state (funcall (fringe-state f) item)))
    (setf (fringe-minimum f) key)
    (push item (aref extends 0))
    (push t (gethash state searched))
    f))

(defun fringe-insert (f items)
  (mapc (lambda (item)
          (let ((extends (fringe-extends f))
		(minimum (fringe-minimum f))
		(searched (fringe-searched f))
		(key (funcall (fringe-key f) item))
                (state (funcall (fringe-state f) item)))
            (push item (aref extends (- key minimum)))
	    (push t (gethash state searched))))
        items)
  f)

(defstruct node
  (state nil :type (simple-array fixnum))
  (parent nil :type t)
  (direction nil :type symbol)
  (path-cost 0 :type integer)
  (depth 0 :type integer)
  (pos-0 0 :type integer))

(defun direction-sequence (node)
  (labels ((direction-sequence-iter (node directions)
             (if (null (node-parent node))
                 directions
               (direction-sequence-iter (node-parent node) (cons (node-direction node) directions)))))
    (direction-sequence-iter node nil)))

(defun A*-search (action heuristic goalp initial-state)
  (labels ((expand (node fringe)
             (mapcar (lambda (triple)
                       (let* ((state (aref triple 0))
                              (direction (aref triple 1))
                              (cost (funcall heuristic state))
                              (depth (1+ (node-depth node)))
                              (pos-0 (aref triple 2)))
                         (make-node :state state
                                    :parent node
                                    :direction direction
                                    :path-cost (+ depth cost)
                                    :depth depth
                                    :pos-0 pos-0)))
                     (remove-if (lambda (triple)
                                  (let ((state (aref triple 0)))
                                    (fringe-exist-state-p fringe state)))
                                (funcall action node))))
           (search-iter (fringe)
             (let ((node (fringe-remove fringe)))
               (if (funcall goalp (node-state node))
                   (list (direction-sequence node) (node-depth node))
                 (search-iter (fringe-insert fringe (expand node fringe)))))))
    (search-iter (fringe-start (make-fringe :state #'node-state
					    :key #'node-path-cost)
			       (make-node :state initial-state
					  :path-cost (funcall heuristic initial-state)
					  :pos-0 (position 0 initial-state))))))

(defun IDA*-search (action heuristic goalp initial-state)
  (let ((max-cost-limit 105)
        (initial-node (make-node :state initial-state
                                 :pos-0 (position 0 initial-state))))
    (labels ((expand (node)
               (mapcar (lambda (triple)
                         (let ((state (aref triple 0))
                               (direction (aref triple 1))
                               (depth (1+ (node-depth node)))
                               (pos-0 (aref triple 2)))
                           (make-node :state state
                                      :parent node
                                      :direction direction
                                      :depth depth
                                      :pos-0 pos-0)))
                       (funcall action node)))
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
                          (search-iter (append (expand node) rst) cost-limit next-cost-limit)))))))
      (search-iter (list initial-node) (funcall heuristic initial-state) max-cost-limit))))

(defun manhattan-generator (target width)
  (let ((state-length (length target))
        (target-pos
         (coerce (cons 0
                       (loop for i from 1 to (reduce #'max target) collecting
                             (multiple-value-call #'cons (floor (position i target) width))))
                 'vector)))
    (lambda (state)
      (loop for i from 0 to (1- state-length)
            for state-i across state
            when (plusp state-i)
                sum (multiple-value-bind (square-x square-y) (floor i width)
                      (let* ((target (aref target-pos state-i))
                             (target-x (car target))
                             (target-y (cdr target)))
                        (+ (abs (- target-x square-x)) (abs (- target-y square-y)))))))))

(defun misplaced (state)
  (declare (special *target*))
  (loop for i from 0 to (1- (length state))
        for state-i across state
        unless (zerop state-i)
        count (/= state-i
                  (aref *target* i))))

(defun swap (state i j)
  ;; move 0 at i to position j with side-effect.
  (unless (= (aref state j) -1)
    (let ((temp-state (copy-seq state)))
      (rotatef (aref temp-state i) (aref temp-state j))
      temp-state)))

(defun move-blank (state direction pos-0)
  (declare (special *width*))
  (case direction
    (UP
     (let ((new-pos-0 (- pos-0 *width*)))
       (when (>= new-pos-0 0)
         (vector (swap state pos-0 new-pos-0) direction new-pos-0))))
    (DOWN
     (let ((new-pos-0 (+ pos-0 *width*)))
       (when (< new-pos-0 (length state))
         (vector (swap state pos-0 new-pos-0) direction new-pos-0))))
    (LEFT
     (let ((new-pos-0 (1- pos-0)))
       (unless (zerop (mod pos-0 *width*))
         (vector (swap state pos-0 new-pos-0) direction new-pos-0))))
    (RIGHT
     (let ((new-pos-0 (1+ pos-0)))
       (unless (zerop (mod (1+ pos-0) *width*))
         (vector (swap state pos-0 new-pos-0) direction new-pos-0))))))

(declaim (type integer *width*)
         (type vector *target* *start*))

(defparameter *width* 3)

(defparameter *target* (vector 0 1 2
                               3 4 5
                               6 7 8))

(defparameter *start* (vector 5 1 0
                              7 2 8
                              6 4 3))

(defun goalp (state)
  (equalp state *target*))

(defun action (node)
  ;; return a list of '(state direction pos-0)
  (let ((old-state (node-state node))
        (old-direction (node-direction node))
        (old-pos-0 (node-pos-0 node)))
  (remove nil
          (mapcar (lambda (direction)
                    (move-blank old-state direction old-pos-0))
                  (remove (case old-direction
                            (UP 'DOWN)
                            (DOWN 'UP)
                            (RIGHT 'LEFT)
                            (LEFT 'RIGHT))
                          '(UP DOWN RIGHT LEFT))))))

(defun n-puzzle (search heuristic initial-state)
  (funcall search #'action heuristic #'goalp initial-state))

(format t "IDA*-search~%")
(time (format t "~A~%" (n-puzzle #'IDA*-search
                                 (manhattan-generator *target* *width*)
                                 *start*)))

(format t "A*-search~%")
(time (format t "~A~%" (n-puzzle #'A*-search
                                 (manhattan-generator *target* *width*)
                                 *start*)))
