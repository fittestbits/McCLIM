;;; -*- Mode: Lisp; -*-

;;;  (c) copyright 2006 David Lichteblau (david@lichteblau.com)

;;;  Permission is hereby granted, free of charge, to any person obtaining
;;;  a copy of this software and associated documentation files (the
;;;  "Software"), to deal in the Software without restriction, including
;;;  without limitation the rights to use, copy, modify, merge, publish,
;;;  distribute, sublicense, and/or sell copies of the Software, and to
;;;  permit persons to whom the Software is furnished to do so, subject to
;;;  the following conditions:
;;; 
;;;  The above copyright notice and this permission notice shall be
;;;  included in all copies or substantial portions of the Software.
;;; 
;;;  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
;;;  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
;;;  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. 
;;;  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
;;;  CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
;;;  TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
;;;  SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

(in-package :clim-gtkairo)


;;; these shouldn't be here:

(defclass metrik-medium (gtkairo-medium) ())

(defmacro with-cairo-medium ((medium) &body body)
  `(invoke-with-cairo-medium (lambda () ,@body) ,medium))


;;;; Helper macros.

(defmacro with-pango-cairo ((layout-var cr &key text-style text) &body body)
  `(invoke-with-pango-cairo (lambda (,layout-var) ,@body)
			    ,cr
			    :text-style ,text-style
			    :text ,text))

(defmacro with-text-style-font-description ((var text-style) &body body)
  `(invoke-with-text-style-font-description
			   (lambda (,var) ,@body)
			   ,text-style))

(defmacro with-font-description ((var description) &body body)
  `(invoke-with-font-description (lambda (,var) ,@body) ,description))

(defmacro with-font-metrics ((var context desc) &body body)
  `(invoke-with-font-metrics (lambda (,var) ,@body) ,context ,desc))

(defmacro with-pango-context ((var medium) &body body)
  `(invoke-with-pango-context (lambda (,var) ,@body) ,medium))

(defun invoke-with-pango-cairo (fn cr &key text-style text)
  (let ((layout (pango_cairo_create_layout cr)))
    (unwind-protect
	(progn
	  (when text-style
	    (with-text-style-font-description
		(desc
		 (etypecase text-style
		   (text-style
		     text-style)
		   (medium
		     (merge-text-styles
		      (medium-text-style text-style)
		      (medium-default-text-style text-style)))))
	      (pango_layout_set_font_description layout desc)))
	  (when text
	    (pango_layout_set_text layout text -1))
	  (funcall fn layout))
      (g_object_unref layout))))

(defun invoke-with-font-description (fn desc)
  (unwind-protect
      (funcall fn desc)
    (pango_font_description_free desc)))

(defun invoke-with-text-style-font-description (fn text-style)
  (with-font-description (desc (make-font-description text-style))
    (funcall fn desc)))

(defun invoke-with-font-metrics (fn context desc)
  (let ((metrics (pango_context_get_metrics context desc (cffi:null-pointer))))
    (unwind-protect
	(funcall fn metrics)
      (pango_font_metrics_unref metrics))))

(defun invoke-with-pango-context (fn medium)
  (declare (ignore medium))		;fixme!
  (let ((context (gdk_pango_context_get)))
    (unwind-protect
	(funcall fn context)
      (g_object_unref context))))


;;;; Pango text drawing and metric functions.

(defvar *default-font-families*
    ;; Finding a good monospace font isn't easy:
    ;;   - "Free Mono" is totally broken.
    ;;   - "Courier", "Nimbus Mono L", "Andale Mono" have weird "Bold" face
    ;;     metrics.
    ;;   - "Courier New" and "Bitstream Vera Sans Mono" work well.
    ;; (Test case is Climacs.)
    '(:fix         "Courier New"
      :serif       "serif"
      :sans-serif  "sans")
  "A plist mapping the standard font family keywords :fix, :serif, and
:sans-serif to Pango font names.  Example:
  (setf (getf *default-font-families* :fix) \"Bitstream Vera Sans Mono\")")

(defun make-font-description (text-style)
  (multiple-value-bind (family face size)
      (text-style-components
       (merge-text-styles text-style *default-text-style*))
    (when (listp face)
      ;; Ein Pfusch ist das!
      (setf face (intern (format nil "~A-~A"
				 (symbol-name (first face))
				 (symbol-name (second face)))
			 :keyword)))
    (let ((desc (pango_font_description_new))
	  (family (or (getf *default-font-families*
			    (if (eq family :fixed) :fix family))
		      (error "unknown font family: ~A" family)))
	  (weight (ecase face
		    ((:roman :italic :oblique)
		      :PANGO_WEIGHT_NORMAL)
		    ((:bold :bold-italic :italic-bold :bold-oblique
			    :oblique-bold)
		      :PANGO_WEIGHT_BOLD)))
	  (style (ecase face
		   ((:roman :bold)
		     :PANGO_STYLE_NORMAL)
		   ((:italic :bold-italic :italic-bold)
		     :PANGO_STYLE_ITALIC)
		   ((:oblique :bold-oblique :oblique-bold) 
		     :PANGO_STYLE_OBLIQUE)))
	  (size (case size
		  (:normal 12)
		  (:tiny 6)
		  (:small 10)
		  (:very-small 8)
		  (:large 14)
		  (:very-large 16)
		  (:huge 24)
		  (otherwise (truncate size)))))
      (pango_font_description_set_family desc family)
      (pango_font_description_set_weight desc weight)
      (pango_font_description_set_style desc style)
      (pango_font_description_set_size desc (* size PANGO_SCALE))
      desc)))

(defun pango-layout-get-pixel-size (layout)
;;;  (cffi:with-foreign-object (rect 'pangorectangle)
;;;    (pango_layout_get_pixel_extents
;;;     layout
;;;     (cffi:null-pointer)
;;;     rect)
;;;    (cffi:with-foreign-slots ((x y width height) rect pangorectangle)
;;;      (tr x y width height)
;;;      (values width (- height y))))
  (cffi:with-foreign-object (&w :int)
    (cffi:with-foreign-object (&h :int)
      (pango_layout_get_pixel_size layout &w &h)
      (values
       (cffi:mem-aref &w :int)
       (cffi:mem-aref &h :int)))))

(defun pango-layout-line-get-pixel-extents (layout line-index)
  (when (minusp line-index)
    (incf line-index (pango_layout_get_line_count layout)))
  (cffi:with-foreign-object (rect 'pangorectangle)
    (pango_layout_line_get_pixel_extents
     (pango_layout_get_line layout line-index)
     (cffi:null-pointer)
     rect)
    (cffi:with-foreign-slots ((x y width height) rect pangorectangle)
      (values x y width height))))

(defun pango-layout-get-ink-rectangle (layout)
  (cffi:with-foreign-object (rect 'pangorectangle)
    (pango_layout_get_pixel_extents layout rect (cffi:null-pointer))
    (cffi:with-foreign-slots ((x y width height) rect pangorectangle)
      (values x y width height))))

(defmethod text-size
    ((medium metrik-medium) string &key text-style (start 0) end)
  (with-cairo-medium (medium)
    ;; -> width height final-x final-y baseline
    (when (characterp string) (setf string (string string)))
    (setf text-style (or text-style (make-text-style nil nil nil)))
    (setf text-style
	  (merge-text-styles text-style (medium-default-text-style medium)))
    (with-slots (cr) medium
      (cairo_identity_matrix cr)
      (with-pango-cairo (layout cr
				:text-style text-style
				:text (unless (eql start end)
					(subseq string start end)))
	(multiple-value-bind (width height)
	    (pango-layout-get-pixel-size layout)
	  (multiple-value-bind (first-x first-y first-width first-height)
	      (pango-layout-line-get-pixel-extents layout 0)
	    (declare (ignorable first-x first-y first-width first-height))
	    (multiple-value-bind (final-x final-y final-width final-height)
		(pango-layout-line-get-pixel-extents layout -1)
	      (declare (ignorable final-x final-y final-width final-height))
	      (values width
		      height
		      final-width
		      (- height final-height)
		      (abs first-y)))))))))

(defmethod climi::text-bounding-rectangle*
    ((medium metrik-medium) string &key text-style (start 0) end)
  (with-cairo-medium (medium)
    ;; -> left ascent right descent
    (when (characterp string) (setf string (string string)))
    (setf text-style (or text-style (make-text-style nil nil nil)))
    (setf text-style
	  (merge-text-styles text-style (medium-default-text-style medium)))
    (with-slots (cr) medium
      (cairo_identity_matrix cr)
      (with-pango-cairo (layout cr
				:text-style text-style
				:text (unless (eql start end)
					(subseq string start end)))
	(multiple-value-bind (x y width height)
	    (pango-layout-get-ink-rectangle layout)
	  (let* ((first-y
		  (nth-value 1 (pango-layout-line-get-pixel-extents layout 0)))
		 (ascent (- (abs first-y) y)))
	    (values x
		    (ceiling (- ascent))
		    (ceiling (+ width (max 0 x)))
		    (ceiling (- height ascent)))))))))

;; (pango_layout_get_context layout)

(defun pango-context-list-families (context)
  (cffi:with-foreign-object (&families :pointer)
    (cffi:with-foreign-object (&n :int)
      (pango_context_list_families context &families &n)
      (let ((families (cffi:mem-aref &families :pointer)))
	(prog1
	    (loop
		for i from 0 below (cffi:mem-aref &n :int)
		collect (cffi:mem-aref families :pointer i))
	  (g_free families))))))

(defun resolve-font-description (context desc)
  (pango_font_describe (pango_context_load_font context desc)))

(defun font-description-to-font-family (context desc)
  (with-font-description (desc* (resolve-font-description context desc))
    (find (pango_font_description_get_family desc*)
	  (pango-context-list-families context)
	  :key #'pango_font_family_get_name
	  :test #'equal)))

(defmethod text-style-fixed-width-p (text-style (medium metrik-medium))
  (with-gtk ()
    (with-pango-context (context medium)
      (with-text-style-font-description (desc text-style)
	(let ((family (font-description-to-font-family context desc)))
	  (assert family)
	  (not (zerop (pango_font_family_is_monospace family))))))))

(defmethod text-style-ascent (text-style (medium metrik-medium))
  (with-gtk ()
    (with-pango-context (context medium)
      (with-text-style-font-description (desc text-style)
	(with-font-metrics (metrics context desc)
	  (ceiling (pango_font_metrics_get_ascent metrics) PANGO_SCALE)))))
  ;; here's a dummy implementation guaranteing ascent+descent=height:
  ;; we don't seem to need it though.
;;;  (multiple-value-bind (width height final-x final-y baseline)
;;;      (text-size medium "foo" :text-style text-style)
;;;    (declare (ignore width height final-x final-y))
;;;    baseline)
  )

(defmethod text-style-descent (text-style (medium metrik-medium))
  (with-gtk ()
    (with-pango-context (context medium)
      (with-text-style-font-description (desc text-style)
	(with-font-metrics (metrics context desc)
	  (ceiling (pango_font_metrics_get_descent metrics) PANGO_SCALE)))))
  ;; here's a dummy implementation guaranteing ascent+descent=height:
  ;; we don't seem to need it though.
;;;  (multiple-value-bind (width height final-x final-y baseline)
;;;      (text-size medium "foo" :text-style text-style)
;;;    (declare (ignore width final-x final-y))
;;;    (- height baseline))
  )

(defmethod text-style-height (text-style (medium metrik-medium))
  (nth-value 1 (text-size medium "foo" :text-style text-style))
  ;; here's a dummy implementation guaranteing ascent+descent=height,
  ;; leading to less inter-line space.
;;;  (+ (text-style-ascent text-style medium)
;;;     (text-style-descent text-style medium))
  )

(defmethod text-style-width (text-style (medium metrik-medium))
  (with-gtk ()
    (with-pango-context (context medium)
      (with-text-style-font-description (desc text-style)
	(with-font-metrics (metrics context desc)
	  (ceiling (pango_font_metrics_get_approximate_char_width metrics)
		   PANGO_SCALE))))))