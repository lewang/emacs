;;; cus-test.el --- functions for testing custom variable definitions

;; Copyright (C) 1998, 2000, 2002 Free Software Foundation, Inc.

;; Author: Markus Rost <markus.rost@mathematik.uni-regensburg.de>
;; Maintainer: Markus Rost <rost@math.ohio-state.edu>
;; Created: 13 Sep 1998
;; Keywords: maint

;; This file is part of GNU Emacs.

;; GNU Emacs is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:

;; Some user options in GNU Emacs have been defined with incorrect
;; customization types.  As a result the customization of these
;; options is disabled.  This file provides functions to detect such
;; options.
;;
;; Usage: Load this file.  Then
;;
;;    M-x cus-test-apropos REGEXP RET
;;
;; checks the options matching REGEXP.	In particular
;;
;;    M-x cus-test-apropos RET
;;
;; checks all options.  The detected options are stored in the
;; variable `cus-test-errors'.
;;
;; Only those options are checked which have been already loaded.
;; Therefore `cus-test-apropos' is more efficient after loading many
;; libraries.
;;
;;    M-x cus-test-library LIB RET
;;
;; loads library LIB and checks the options matching LIB.
;;
;;    M-x cus-test-load-custom-loads RET
;;
;; loads all (!) custom dependencies.
;;
;;    M-x cus-test-load-libs RET
;;
;; loads all (!) libraries with autoloads.  This function is useful to
;; detect load problems of libraries.
;;
;; For a maximal test of custom options invoke
;;
;;    M-x cus-test-all
;;
;; This function is suitable for batch mode.
;;
;; To make cus-test work one has usually to work-around some existing
;; bugs/problems.  Therefore this file contains a "Workaround"
;; section, to be edited once in a while.
;;
;; There is an additional experimental option
;; `cus-test-include-changed-variables'.
;;
;; Options with a custom-get property, usually defined by a :get
;; declararation, are stored in the variable
;; `cus-test-variables-with-custom-get', just in case one wants to
;; investigate them further.

;;; Code:

;;; User variables:

(defvar cus-test-strange-variables nil
  "*List of variables to disregard by `cus-test-apropos'.")

(defvar cus-test-strange-libs nil
  "*List of libraries to avoid by `cus-test-load-libs'.")

(defvar cus-test-after-load-libraries-hook nil
  "*Hook to repair the worst side effects of loading buggy libraries.
It is run after `cus-test-load-custom-loads' and `cus-test-load-libs'")

(defvar cus-test-include-changed-variables nil
  "*If non-nil, consider variables with state 'changed as buggy.")

;;; Workarounds:

;; avoid error when loading speedbar.el
;; bug in speedbar.el in 20.3:
;; (define-key speedbar-key-map "Q" 'delete c-frame)
;; (setq speedbar-key-map (make-keymap))

;; avoid binding of M-x to `save-buffers-exit-emacs' after loading
;; crisp.el (in 20.3):
;; (setq crisp-override-meta-x nil)

;; Work around bugs in 21.0:

;; (defvar msb-after-load-hooks)

;; The file eudc-export.el loads libraries "bbdb" and "bbdb-com" which
;; are not part of GNU Emacs.
(provide 'bbdb)
(provide 'bbdb-com)
;; (locate-library "bbdb")

;; Work around bugs in 21.3.50:

;; ada load problems are fixed now.
;; (add-to-list 'cus-test-strange-libs "ada-xref")

;; Loading filesets.el currently disables mini-buffer echoes.
;; (add-to-list 'cus-test-strange-libs "filesets")
(add-hook
 'cus-test-after-load-libraries-hook
 (lambda nil
   (remove-hook 'menu-bar-update-hook 'filesets-build-menu-maybe)
   (remove-hook 'kill-emacs-hook 'filesets-exit)
   (remove-hook 'kill-buffer-hook 'filesets-remove-from-ubl)
   (remove-hook 'first-change-hook 'filesets-reset-filename-on-change)
   ))
;; (setq cus-test-after-load-libraries-hook nil)

;; After loading many libraries there appears an error:
;; Loading filesets...
;; tpu-current-line: Args out of range: 44, 84185

;; vc-cvs-registered in loaddefs.el runs a loop if vc-cvs.el is
;; already loaded.
(eval-after-load "loaddefs" '(load-library "vc-cvs"))

;; reftex must be loaded before reftex-vars.
(require 'reftex)

;;; Current result (Oct 6, 2002) of cus-test-all:

;; Cus Test tested 4514 variables.
;; The following variables might have problems:
;; (ps-mule-font-info-database-default)

;;; Silencing:

;; Don't create a file filesets-menu-cache-file.
(setq filesets-menu-cache-file "")

;; Don't create a file save-place-file.
(eval-after-load "saveplace"
  '(remove-hook 'kill-emacs-hook 'save-place-kill-emacs-hook))

;; Don't create a file abbrev-file-name.
(setq save-abbrevs nil)

;; Avoid compile logs from adviced functions.
(eval-after-load "bytecomp"
  '(setq ad-default-compilation-action 'never))

;; We want to log all messages.
(setq message-log-max t)


;;; Main Code:

(defvar cus-test-tested-variables nil
  "Options tested by last call of `cus-test-apropos'.")

(defvar cus-test-errors nil
  "List of problematic variables found by `cus-test-apropos'.")

;; I haven't understood this :get stuff.  However, there are only very
;; few variables with a custom-get property.  Such Symbols are stored
;; in `cus-test-variables-with-custom-get'.
(defvar cus-test-variables-with-custom-get nil
  "Set by `cus-test-apropos' to a list of options with :get property.")

;; This loads cus-loads.el, too.
(require 'cus-edit)

(defun cus-test-apropos (regexp)
  "Check the options matching REGEXP.
The detected problematic options are stored in `cus-test-errors'."
  (interactive "sVariable regexp: ")
  (setq cus-test-errors nil)
  (setq cus-test-tested-variables nil)
  (mapcar
   (lambda (symbol)
     (push symbol cus-test-tested-variables)
     (unless noninteractive
       (message "Cus Test Running...[%s]"
		(length cus-test-tested-variables)))
     (condition-case alpha
	 (let* ((type (custom-variable-type symbol))
		(conv (widget-convert type))
		;; I haven't understood this :get stuff.
		(get (or (get symbol 'custom-get) 'default-value))
		values
		mismatch)
	   (when (default-boundp symbol)
	     (add-to-list 'values
			  (funcall get symbol))
	     (add-to-list 'values
			  (eval (car (get symbol 'standard-value)))))
	   (if (boundp symbol)
	       (add-to-list 'values (symbol-value symbol)))
	   ;; That does not work.
	   ;; (add-to-list 'values (widget-get conv :value))

	   ;; Check the values
	   (mapcar (lambda (value)
		     (unless (widget-apply conv :match value)
		       (setq mismatch 'mismatch)))
		   values)

	   ;; Changed outside the customize buffer?
	   (when cus-test-include-changed-variables
	     (let ((c-value
		    (or (get symbol 'customized-value)
			(get symbol 'saved-value)
			(get symbol 'standard-value))))
	       (if c-value
		   (unless (equal (eval (car c-value))
				  (symbol-value symbol))
		     (setq mismatch 'changed)))))

	   ;; Store symbols with a custom-get property.
	   (when (get symbol 'custom-get)
	     (add-to-list 'cus-test-variables-with-custom-get symbol)
	     ;; No need anymore to ignore them.
	     ;; (setq mismatch nil)
	     )

	   (if mismatch
	       (add-to-list 'cus-test-errors symbol)))

       (error
	(add-to-list 'cus-test-errors symbol)
	(if (y-or-n-p
	     (format "Error for %s: %s\nContinue? "
		     symbol alpha))
	    (message "Error for %s: %s" symbol alpha)
	  (error "Error for %s: %s" symbol alpha)))))
   (cus-test-get-options regexp))
  (message "Cus Test tested %s variables."
	   (length cus-test-tested-variables))
  ;; (describe-variable 'cus-test-errors)
  (cus-test-errors-display)
  ;; (describe-variable 'cus-test-variables-with-custom-get)
  )

(defun cus-test-get-options (regexp)
  "Return a list of custom options matching REGEXP."
  (let (found)
    (mapatoms
     (lambda (symbol)
       (and
	(or
	 ;; (user-variable-p symbol)
	 (get symbol 'standard-value)
	 ;; (get symbol 'saved-value)
	 (get symbol 'custom-type))
	(string-match regexp (symbol-name symbol))
	(not (member symbol cus-test-strange-variables))
	(push symbol found))))
    found))

(defun cus-test-errors-display ()
  "Report about the errors found by cus-test."
  (with-output-to-temp-buffer "*cus-test-errors*"
    (set-buffer standard-output)
    (insert (format "Cus Test tested %s variables.\
  See `cus-test-tested-variables'.\n\n"
		    (length cus-test-tested-variables)))
    (if cus-test-errors
	(let ((L cus-test-errors))
	  (insert "The following variables seem to have errors:\n\n")
	  (while L (insert (symbol-name (car L))) (insert "\n")
		 (setq L (cdr L))))
      (insert "No errors found by cus-test."))))

(defun cus-test-library (lib)
  "Load library LIB and call `cus-test-apropos' on LIB."
  (interactive "sTest variables in library: ")
  (load-library lib)
  (cus-test-apropos lib))

(defun cus-test-load-custom-loads nil
  "Call `custom-load-symbol' on all atoms."
  (interactive)
  (mapatoms 'custom-load-symbol)
  (run-hooks 'cus-test-after-load-libraries-hook))

(defun cus-test-load-libs ()
  "Load the libraries with autoloads in loaddefs.el.
Don't load libraries in `cus-test-strange-libs'.

This function is useful to detect load problems of libraries."
  (interactive)
  (set-buffer (find-file-noselect (locate-library "loaddefs")))
  (goto-char (point-min))
  (let (file)
    (while
	(search-forward "\n;;; Generated autoloads from " nil t)
      (goto-char (match-end 0))
      (setq file (buffer-substring (point)
				   (progn (end-of-line) (point))))
      ;; If it is, load that library.
      (when file
	(setq file (file-name-nondirectory file))
	(when (string-match "\\.el\\'" file)
	  (setq file (substring file 0 (match-beginning 0)))))
      (condition-case alpha
	  (unless (member file cus-test-strange-libs)
	    (load-library file))
	(error (or
		(y-or-n-p
		 (format "Load Error for %s: %s\nContinue Loading? "
			 file alpha))
		(error "Load Error for %s: %s" file alpha))))
      ))
  (run-hooks 'cus-test-after-load-libraries-hook))

(defun cus-test-all nil
  "Run a maximal test by cus-test.
This function is suitable for batch mode, e.g., invoke

emacs -batch -l cus-test.el -f cus-test-all"
  (interactive)
  ;; This does not seem to increase the number of tested options.
  ;;  (message "Running %s" 'cus-test-load-libs)
  ;;  (cus-test-load-libs)
  (message "Running %s" 'cus-test-load-custom-loads)
  (cus-test-load-custom-loads)
  ;; A second call increases the number of tested options.
  (message "Running %s again" 'cus-test-load-custom-loads)
  (cus-test-load-custom-loads)
  (message "Running %s" 'cus-test-apropos)
  (cus-test-apropos "")
  (if cus-test-errors
      (message "The following variables might have problems:\n%s"
	       cus-test-errors)
    (message "No problems found by Cus Test")))

(provide 'cus-test)

;;; cus-test.el ends here
