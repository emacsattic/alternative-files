;;; alternative-files.el -- Go to alternative file

;; Copyright (C) 2011 Ian Yang

;; Author: Ian Yang <doit dot ian (at) gmail dot com>
;; Keywords: navigation
;; Filename: alternative-files.el
;; Description: Go to alternative file
;; Created: 2011-06-11 22:39:00
;; Version: 1.0
;; Last-Updated: 2011-06-11 22:39:00
;; URL: http://www.emacswiki.org/emacs/download/alternative-files.el
;; Compatibility: GNU Emacs 23.1.1

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:

;; TODO

;;; Helper Functions:

(eval-when-compile (require 'cl))

(defun alternative-files--singularize-string (str)
  "Use `singularize-string' in `inflections.el' or just remove trailing s."
  (if (fboundp 'singularize-string)
      (singularize-string str)
    (substring str 0 (1- (length str)))))

(defun alternative-files--pluralize-string (str)
  "Use `pluralize-string' in `inflections.el' or just append trailing s."
  (if (fboundp 'pluralize-string)
      (pluralize-string str)
    (concat str "s")))

(defun alternative-files--detect-file-name ()
  (cond ((and (boundp 'org-src-mode) org-src-mode
              (boundp 'org-edit-src-beg-marker) org-edit-src-beg-marker)
         (buffer-file-name (marker-buffer org-edit-src-beg-marker)))
        ((memq major-mode '(magit-mode term-mode)) (expand-file-name default-directory))
        (t (or (buffer-file-name) (and (eq major-mode 'dired-mode)
                                       (expand-file-name (if (consp dired-directory)
                                                             (car dired-directory)
                                                           dired-directory)))))))

(defun alternative-files--relative-name (filename &optional dir)
  (let ((dir (or dir default-directory))
        (n (length dir)))
    (if (string-equal dir (substring filename 0 n))
        (substring filename n)
      filename)))

;;; Customizations

(defgroup alternative-files nil "Find alternative files")

(defcustom alternative-files-functions
  '(alternative-files-ffap-finder
    alternative-files-rails-finder)
  "functions used to find alternative-files"
  :type 'hook
  :options '(alternative-files-ffap-finder
             alternative-files-rails-finder)
  :group 'alternative-files)

(defcustom alternative-files-completing-read
  'ido-completing-read
  "function used to read string with completion"
  :type 'function
  :options '(ido-completing-read completing-read)
  :group 'alternative-files)

(defcustom alternative-files-root-dir-function
  'eproject-root
  "function used to get root directory"
  :type 'function
  :group 'alternative-files)

;;; Code

(defun alternative-files-ffap-finder ()
  (ffap-guesser))

(defun alternative-files-rails-finder (&optional file)
  (let ((file (or file (alternative-files--detect-file-name))))
    (cond
     ((string-match "^\\(.*\\)/app/\\(models\\|controllers\\|helpers\\)/\\(.+/\\)*\\([^/]+\\)\\.rb$" file)
      (let ((root (match-string 1 file))
            (type (match-string 2 file))
            (dir (match-string 3 file))
            (name (match-string 4 file)))
        (cond
         ((string-equal type "models")
          (let ((plural-name (alternative-files--pluralize-string name)))
            (list
             (concat root "/app/controllers/" dir plural-name "_controller.rb")
             (concat root "/app/controllers/" dir name "_controller.rb")
             (concat root "/app/helpers/" dir plural-name "_helper.rb")
             (concat root "/app/helpers/" dir name "_helper.rb")
             (concat root "/app/views/" dir plural-name "/")
             (concat root "/app/views/" dir name "/"))))

         ((string-equal type "controllers")
          (when (string-match "^\\(.*\\)_controller$" name)
            (setq name (match-string 1 name))
            (list
             (concat root "/app/models/" dir (alternative-files--singularize-string name) ".rb")
             (concat root "/app/models/" dir name ".rb")
             (concat root "/app/helpers/" dir name "_helper.rb")
             (concat root "/app/views/" dir name "/"))))

         ((string-equal type "helpers")
          (when (string-match "^\\(.*\\)_helper$" name)
            (setq name (match-string 1 name))
            (list
             (concat root "/app/models/" dir (alternative-files--singularize-string name) ".rb")
             (concat root "/app/models/" dir name ".rb")
             (concat root "/app/controllers/" dir name "_controller.rb")
             (concat root "/app/views/" dir name "/")))))))

     ((string-match "^\\(.*\\)/app/views/\\(.+\\)*\\([^/]+\\)/[^/]+$" file)
      (let ((root (match-string 1 file))
            (dir (match-string 2 file))
            (name (match-string 3 file)))
        (list
         (concat root "/app/models/" dir (alternative-files--singularize-string name) ".rb")
         (concat root "/app/models/" dir name ".rb")
         (concat root "/app/controllers/" dir name "_controller.rb")
         (concat root "/app/helpers/" dir name "_helper.rb"))))
     )))

(defvar alternative-files nil
  "cache for alternative files")
(defvar alternative-files-executed nil
  "cache for alternative files execution flag")
(make-variable-buffer-local 'alternative-files)
(put 'alternative-files 'permanent-local t)
(make-variable-buffer-local 'alternative-files-executed)
(put 'alternative-files-executed 'permanent-local t)

(defun alternative-files (&optional force)
  "Find alternative files"
  (interactive "P")
  (when (or force (not alternative-files-executed))
    (setq alternative-files-executed t)
    (setq alternative-files (delete-dups
                             (apply
                              'append
                              (mapcar (lambda (f) (ignore-errors (funcall f))) alternative-files-functions)))))
  alternative-files)

;;;###autoload
(defun alternative-files-find-file (&optional force)
  "Find alternative files"
  (interactive "P")
  (let* ((root (ignore-errors (funcall alternative-files-root-dir-function)))
         (default-directory (or root default-directory))
         (files (apply
                 'append
                 (mapcar
                  (lambda (f)
                    (when (file-exists-p f)
                      (if (file-directory-p f)
                          (file-expand-wildcards (concat f "*") t)
                        (list f))))
                  (alternative-files force))))
         (file-names (if root
                         (mapcar (lambda (f) (alternative-files--relative-name f root)) files)
                       files)))
    (find-file (ido-completing-read "Alternative: " file-names))))

;;;###autoload
(defun alternative-files-create-file (&optional force)
  "Find alternative files"
  (interactive "P")
  (let* ((root (ignore-errors (funcall alternative-files-root-dir-function)))
         (default-directory (or root default-directory))
         (files (delete-if-not 'file-exists-p (alternative-files force)))
         (file-names (if root
                         (mapcar (lambda (f) (alternative-files--relative-name f root)) files)
                       files))
         (choise (ido-completing-read "Create: " file-names)))
    (when (equal (file-name-directory choise) choise)
      (ignore-errors (make-directory choise)))
    (find-file choise)))

(provide 'alternative-files)