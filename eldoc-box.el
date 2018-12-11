;;; eldoc-box.el --- Display documentation in childframe      -*- lexical-binding: t; -*-

;; Copyright (C) 2018  Yuan Fu

;; Version: 1.0
;; Author: Yuan Fu <casouri@gmail.com>
;; Not really because I copied code from lsp-ui-doc.el
;; which is written by Sebastien Chapuis <sebastien@chapu.is>
;; And I removed the license so the previous commits with license
;; are not really with license.
;; I hope I don't get in troubles because of this.
;; URL: https://github.com/casouri/eldoc-box
;; Package-Requires: ((emacs "26.1"))

;;; This file is NOT part of GNU Emacs

;;; Commentary:
;;

;;; Code:
;;

(require 'cl-lib)

;;;; Userland
;;;;; Variable

(defface eldoc-box-border '((((background dark)) . (:background "white"))
                            (((background light)) . (:background "black")))
  "The border color used in childframe.")

(defface eldoc-box-body '((t . (:background nil)))
  "Body face used in eglot doc childframe. Only :background is used.")

(defvar eldoc-box-only-multi-line nil
  "If non-nil, only use childframe when there are more than one line.")

(defvar eldoc-box-frame-parameters
  '(
    ;; (left . -1)
    (no-accept-focus . t)
    (no-focus-on-map . t)
    (min-width  . 0)
    ;; (width  . 0)
    (min-height  . 0)
    ;; (height  . 0)
    (internal-border-width . 1)
    (vertical-scroll-bars . nil)
    (horizontal-scroll-bars . nil)
    (right-fringe . 0)
    (menu-bar-lines . 0)
    (tool-bar-lines . 0)
    (line-spacing . 0)
    (unsplittable . t)
    (undecorated . t)
    ;; (top . -1)
    (visibility . nil)
    (mouse-wheel-frame . nil)
    (no-other-frame . t)
    (cursor-type . nil)
    (inhibit-double-buffering . t)
    (drag-internal-border . t)
    (no-special-glyphs . t)
    (desktop-dont-save . t))
  "Frame parameters used to create the frame.")

(defvar eldoc-box-max-pixel-width 800
  "Maximum width of doc childframw in pixel.")
(defvar eldoc-box-max-pixel-height 1400
  "Maximum height of doc childframw in pixel.")

;;;;; Function

(defun eldoc-box-help-at-point ()
  "Display hover info at point in a childframe."
  (interactive)
  (let ((doc (funcall eldoc-documentation-function)))
    (when doc
      (eldoc-box--display doc)
      (eldoc-box--inject-quit-func))))

(defun eldoc-box-quit-frame ()
  "Hide childframe used by eglot doc."
  (interactive)
  ;; TODO
  (when eldoc-box--frame
    (make-frame-invisible eldoc-box--frame t)))

;;;; Backstage
;;;;; Variable

(defvar eldoc-box--frame nil
  "The frame to display doc.")

(defvar eldoc-box--buffer "*eldoc-box*"
  "The buffer used to display eglot doc.")

;;;;; Function

(defun eldoc-box--display (str)
  "Display STR in childframe."
  (let ((doc-buffer (get-buffer-create eldoc-box--buffer)))
    (with-current-buffer doc-buffer
      (setq mode-line-format nil)
      (erase-buffer)
      (insert str)
      (eldoc-box--get-frame doc-buffer))))

(defun eldoc-box-quit-hook ()
  "Quit eglot doc childframe and remove self from hook."
  (eldoc-box-quit-frame)
  (remove-hook 'pre-command-hook #'eldoc-box-quit-hook t))

(defun eldoc-box--inject-quit-func ()
  "Inject quit function into `pre-command-hook' so doing anything will quit eglot doc childframe."
  (add-hook 'pre-command-hook #'eldoc-box-quit-hook t t))

(defun eldoc-box--window-side ()
  "Return 'left if the selected window is on the left,
'right if on the right. Return 'left if there is only one window."
  (let ((left-window(window-at 0 0)))
    (if (eq left-window (selected-window))
        'left
      'right)))

(defun eldoc-box--get-frame (buffer)
  "Return a childframe displaying BUFFER.
Checkout `lsp-ui-doc--make-frame', `lsp-ui-doc--move-frame'."
  (let* ((after-make-frame-functions nil)
         (before-make-frame-hook nil)
         (parameter (append eldoc-box-frame-parameters
                            `((default-minibuffer-frame . ,(selected-frame))
                              (minibuffer . ,(minibuffer-window))
                              (left-fringe . ,(frame-char-width)))))
         (window (or (and eldoc-box--frame (frame-selected-window eldoc-box--frame))
                     (display-buffer-in-child-frame
                      buffer
                      `((child-frame-parameters . ,parameter)))))
         (frame (window-frame window))
         (main-frame (selected-frame)))
    (make-frame-visible frame)
    (set-window-dedicated-p window t)
    (redirect-frame-focus frame (frame-parent frame))
    (set-face-attribute 'internal-border frame :inherit 'eldoc-box-border)
    (set-face-attribute 'default frame :background (face-attribute 'eldoc-box-body :background main-frame))
    ;; set size
    (let* ((size
            (window-text-pixel-size
             window nil nil
             eldoc-box-max-pixel-width
             eldoc-box-max-pixel-height t))
           (width (car size))
           (height (cdr size))
           (width (+ width (frame-char-width frame))) ; add margin
           (frame-resize-pixelwise t))
      (set-frame-size frame width height t)
      ;; move position
      (set-frame-position frame (pcase (eldoc-box--window-side) ; x position + a little padding (16)
                                  ;; display doc on right
                                  ('left (- (frame-outer-width main-frame) width 16))
                                  ;; display doc on left
                                  ('right 16))
                          ;; y position + a little padding (16)
                          16))
    (setq eldoc-box--frame frame)))

;;;;; ElDoc
(defun eldoc-box--eldoc-message-function (str &rest args)
  "Frontend for eldoc. Display STR in childframe and ARGS works like `message'."
  (if (stringp str)
      (let ((doc (apply #'format str args)))
        (if (and eldoc-box-only-multi-line (eq (cl-count ?\n doc) 0))
            (apply #'eldoc-minibuffer-message str args)
          (eldoc-box--display (apply #'format str args))))
    (eldoc-box-quit-frame)))

(define-minor-mode eldoc-box-hover-mode
  "Displays hover documentations in a childframe. This mode is buffer local."
  :lighter " ELDOC-BOX"
  (if eldoc-box-hover-mode
      (setq-local eldoc-message-function #'eldoc-box--eldoc-message-function)
    (setq-local eldoc-message-function #'eldoc-minibuffer-message)))

(provide 'eldoc-box)

;;; eldoc-box.el ends here
