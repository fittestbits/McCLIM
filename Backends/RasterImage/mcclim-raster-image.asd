
(defsystem #:mcclim-raster-image
    :depends-on (#:mcclim-render
                 #-mezzano #:mcclim-render/clx
		 #:mcclim-single-mirrored-standard)
    :serial t
    :components
    ((:file "package")
     (:file "graft")
     (:file "medium")
     (:file "top-level-pane")
     (:file "port")
     (:file "stream")
     (:file "output-to-png")
     (:file "rgb-port")
     ))
