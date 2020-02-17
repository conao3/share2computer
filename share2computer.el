;;; eh-misc.el --- Tumashu's emacs configuation

;; * Header
;; Copyright (c) 2020, Feng Shu

;; Author: Feng Shu <tumashu@163.com>
;; URL: https://github.com/tumashu/share2computer
;; Version: 0.0.1

;; This file is not part of GNU Emacs.

;;; License:

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License
;; as published by the Free Software Foundation; either version 3
;; of the License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:

;; * README                                                  :README:
;; share2computer is a elisp helper of android app: [[https://github.com/jimmod/ShareToComputer][Share to Computer]]
;; When user have shared files with ShareToComputer in android phone,
;; they can run Emacs command `share2computer' in android to download
;; shared files in computer.

;;; Code:

;; * 代码                                                      :code:

;; ** Share to Computer
(require 'url)

(defcustom share2computer-urls nil
  "The possible download urls of Android app: ShareToComputer."
  :group 'share2computer
  :type '(repeat string))

(defcustom share2computer-default-path "~/share2computer/"
  "The default download path of share2computer."
  :group 'org-brain
  :type '(string))

(defvar share2computer-file-number 0
  "The number of downloaded files.")
(defvar share2computer-buffers nil
  "The buffers created by `url-retrieve' when run share2computer.")
(defvar share2computer-timer1 nil
  "The timer used to cancel download.")
(defvar share2computer-timer2 nil
  "The timer used to show second of time when connect url.")

(defun share2computer-write (status url link path n &optional retry-n)
  (let* ((err (plist-get status :error))
         (disposition
          (mail-fetch-field "Content-Disposition"))
         (filename
          (when disposition
            (replace-regexp-in-string
             file-name-invalid-regexp ""
             (replace-regexp-in-string
              ".*filename=\"\\(.*\\)\"$" "\\1"
              (decode-coding-string disposition 'utf-8))))))
    (if (and filename (not err))
        (let ((file (concat (file-name-as-directory path) filename)))
          (delete-region
           (point-min)
           (progn
             (re-search-forward "\n\n" nil 'move)
             (point)))
          (let ((coding-system-for-write 'no-conversion))
            (write-region nil nil file))
          (setq share2computer-file-number
                (+ share2computer-file-number 1))
          (if (= share2computer-file-number n)
              (progn
                (message "share2computer: download finished from %S" url)
                (eh-system-open path))
            (message "share2computer: download %s/%s files to %S ..."
                     share2computer-file-number n path)))
      (share2computer-download-1 (current-buffer) url link path n 1))))

(defun share2computer-kill-all ()
  (interactive)
  (share2computer-kill 'all))

(defun share2computer-kill (url &optional reverse)
  (let ((kill-buffer-query-functions nil)
        buffers result)
    (dolist (x share2computer-buffers)
      (let ((condi (or (equal url (car x))
                       (equal url 'all))))
        (if (if reverse (not condi) condi)
            (dolist (buff (cdr x))
              (when (buffer-live-p buff)
                (push buff buffers)))
          (push x result)))
      (setq share2computer-buffers result)
      ;; 必须先设置 share2computer-buffers 然后再删除 buffer
      (mapcar #'kill-buffer buffers))))

(defun share2computer-register (url buffer)
  (push buffer (alist-get url share2computer-buffers nil t 'equal)))

(defun share2computer-registered-p (url buffer)
  (member buffer (alist-get url share2computer-buffers nil t 'equal)))

(defun share2computer-download (status url path)
  (let ((n (save-excursion
             (goto-char (point-min))
             (re-search-forward "\n\n" nil 'move)
             (ignore-errors
               (cdr (assoc 'total
                           (json-read-from-string
                            (buffer-substring (point) (point-max)))))))))
    (when (and (numberp n) (> n 0))
      (share2computer-kill url t)
      (share2computer-cancel-timer)
      (message "share2computer: start download ...")
      (dotimes (i n)
        (share2computer-download-1
         (current-buffer) url (format "%s%S" url i) path n)))))

(defun share2computer-download-1 (buffer url link path n &optional retry-n)
  (if (and (numberp retry-n)
           (> retry-n 4))
      (message "share2computer: fail after retry download 3 times !!!")
    (share2computer-register
     url
     (url-retrieve
      link
      (lambda (status buffer url link path n)
        (when (share2computer-registered-p url buffer)
          (share2computer-write status url link path n)))
      (list buffer url link path n)
      t t))
    (when (numberp retry-n)
      (message "share2computer: retry(%s) download file from %S ..." retry-n link)
      (setq retry-n (+ retry-n 1)))))

(defun share2computer-active-timer ()
  "Active timers which used to download cancel and progress."
  (let ((sec (string-to-number (format-time-string "%s"))))
    (share2computer-cancel-timer)
    (setq share2computer-timer1
          (run-with-timer
           4 nil
           (lambda ()
             (message "share2computer: cancel download for wait too long time.")
             (share2computer-cancel-timer)
             (share2computer-kill 'all))))
    (setq share2computer-timer2
          (run-with-timer
           nil 1
           `(lambda ()
              (message "share2computer: read info (%ss) ..."
                       (- (string-to-number (format-time-string "%s")) ,sec)))))))

(defun share2computer-cancel-timer ()
  "Cancel timers which used to download cancel and progress."
  (when share2computer-timer1
    (cancel-timer share2computer-timer1))
  (when share2computer-timer2
    (cancel-timer share2computer-timer2)))

(defun share2computer-internal (path)
  "Internal function of share2computer. "
  (setq path (expand-file-name (file-name-as-directory path)))
  (setq share2computer-file-number 0)
  (make-directory path t)
  (while (not (cl-some (lambda (x)
                         (> (length x) 0))
                       share2computer-urls))
    (share2computer-setup))
  (share2computer-kill 'all)
  (share2computer-active-timer)
  (dolist (url share2computer-urls)
    (let ((url (file-name-as-directory url)))
      (share2computer-register
       url (url-retrieve (concat url "info")
                         'share2computer-download
                         (list url path)
                         t t)))))

(defun share2computer ()
  "Download files shared by Android ShareToComputer."
  (interactive)
  (share2computer-internal share2computer-default-path))

(defun share2computer-org ()
  "Download files shared by Android ShareToComputer to org attach dir."
  (interactive)
  (let (c marker)
    (when (eq major-mode 'org-agenda-mode)
      (setq marker (or (get-text-property (point) 'org-hd-marker)
		       (get-text-property (point) 'org-marker)))
      (unless marker
	(error "No task in current line")))
    (save-excursion
      (when marker
	(set-buffer (marker-buffer marker))
	(goto-char marker))
      (org-back-to-heading t)
      (share2computer-internal (org-attach-dir t)))))

(defun share2computer-setup ()
  "Setup share2computer."
  (interactive)
  (let ((status t))
    (while status
      (push (read-from-minibuffer "share2computer url: " "http://192.168.0.X:8080")
            share2computer-urls)
      (when (y-or-n-p "share2computer: adding url finish? ")
        (setq status nil))))
  (setq share2computer-urls
        (delete-dups share2computer-urls))
  (when (y-or-n-p "Save this url for future session? ")
    (customize-save-variable
     'share2computer-urls
     share2computer-urls)))

;; * Footer
(provide 'share2computer)

;;; share2computer.el ends here