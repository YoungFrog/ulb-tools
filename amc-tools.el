;;; amc-tools.el --- Set of commands to organize my workflow with amc  -*- lexical-binding: t; -*-

;; Copyright (C) 2015  Nicolas Richard

;; Author: Nicolas Richard <theonewiththeevillook@yahoo.fr>
;; Keywords: 

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Given a list of files (jpg scans), and an AMC database which
;; associates some of them with students, we make pdf files ready to
;; be sent back to the students.

;;; Code:

(require 'dash)

(defvar amc-tools-current-project nil)
;  "~/Projets-QCM/MathF112-2014-15-janvier-aprem/"
(defvar amc-tools--scan-files nil "elts are relative to `scans' subdir")
(defvar amc-tools--corrected-files nil "elts are relatives to `cr/corrections/pdf' subdir")
(defvar amc-tools--capture-data nil "elts are relative to `scans' subdir")
(defvar amc-tools--association-data nil)

(defun amc-tools-call-process-to-string (program &optional infile &rest args)
  (with-temp-buffer
    (apply 'call-process program infile t nil args)
    (buffer-string)))
(defun amc-tools-update-current-project (newproject)
  (interactive "D")
  (setq amc-tools-current-project newproject)
  (amc-tools-update-current-project--data)
  (message "Use M-x amc-tools-make-files to make the files."))
(defun amc-tools-update-current-project--data ()
  (let ((data-dir (expand-file-name "data" amc-tools-current-project))))
  (setq amc-tools--scan-files (directory-files (expand-file-name "scans" amc-tools-current-project)
                                               nil "jpg$")
        amc-tools--capture-data (amc-tools-fichier-student-alist)
        amc-tools--association-data (amc-tools-student-copy-alist)
        amc-tools--corrected-files (directory-files (expand-file-name "cr/corrections/pdf"
                                                                   amc-tools-current-project)
                                                 nil "pdf$"))
  ;; change amc-tools--association-data into a hash table extended with the scans.
  (setq amc-tools--association-data (amc-tools--map-files-to-students))
  ;; replace known  (identified) scans by their AMC-corrected counterpart
  (amc-tools--replace-known-with-corrected-files amc-tools--association-data))

(defun yf/MATHF112-file-to-number (scanfile)
  "Take a scanfile a turn it into a sequence number."
  (let ((file  (file-name-nondirectory scanfile)))
    (cl-assert (string-match "\\([0-9]\\{4\\}}\\)\\.jpg" file))
    (string-to-number (match-string 1 file))))

(defun amc-tools-fichier-student-alist ()
  "Extrait une association `(fichier . student)' du fichier FILE.
student est un objet qui sert de uuid pour une personne dans AMC.
Actuellement, student est un vecteur composé de :
- un numéro d'étudiant NUMBER au sens de AMC
- un numéro de copie, COPY, lorsqu'un même numéro d'étudiant a
  été attribué plusieurs fois (photocopie des sujets)."
  (with-temp-buffer
    (call-process "sqlite3"
                  nil t nil
                  (expand-file-name "data/capture.sqlite" amc-tools-current-project)
                  "SELECT src, student,copy FROM capture_page")
    (goto-char (point-min))
    (mapcar
     (lambda (line)
       (destructuring-bind (scanfile student copy)
           (split-string line "|")
         (unless (string-empty-p scanfile)
           (cons (file-name-nondirectory scanfile)
                 (vector student copy)))))
     (split-string (buffer-string) "\n" t))))

(defun amc-tools-xor (a b)
  (or (and (not a) b)
      (and (not b) a)))

(defun amc-tools-student-copy-alist ()
  "Extrait une association student-matricule de la BDD."
  (with-temp-buffer
    (call-process "sqlite3"
                  nil t nil
                  (expand-file-name "data/association.sqlite" amc-tools-current-project)
                  "SELECT student,copy,manual,auto FROM association_association")
    (goto-char (point-min))
    (mapcar
     (lambda (line)
       (destructuring-bind (student copy manual auto)
           (split-string line "|")
         (cons (vector student copy)
               (amc-tools-xor (yf/any-to-number-safe manual)
                              (yf/any-to-number-safe auto)))))
     (split-string (buffer-string) "\n" t))))

(defun amc-tools--map-files-to-students ()
  "Associate a STUDENT to each scan file.
Return an hash table mapping STUDENT to a cons (KNOWN . GUESS) where
- KNOWN is list of files we know belong to STUDENT, and
- GUESS is a list of files we are unsure about,
  because there is no identification for them"
  (let ((result (make-hash-table :test 'equal))
        (files amc-tools--scan-files)
        current-student
        file
        (fichier-student-alist amc-tools--capture-data))
    (cl-assert (assoc (car files) ;; first file must be from a known a student !
                      fichier-student-alist))
    (while files
      (setq file (pop files))
      (--if-let (assoc file fichier-student-alist) ; known student
          (progn
            (setq current-student (cdr it))
            (unless (gethash current-student result)
              ; first time seen
              (puthash current-student (cons nil nil) result))
            (push file (car (gethash current-student result))))
        (push file (cdr (gethash current-student result)))))
    result))

;; (yf/MATHF112-map-files-to-students (cl-loop for i from 5 to 20 collect (format "MATH%s.jpg" i)))

;; => (("MATH5.jpg" . 261) ("MATH6.jpg" . 261) ("MATH7.jpg" . 261) ("MATH8.jpg" . 21) ("MATH9.jpg" . 21))

(defun amc-tools--replace-known-with-corrected-files (hash)
  ;; Replace things by side effect in the hash table.
  ;; Also put the files in the correct order.
  (cl-assert amc-tools--corrected-files)
  (maphash
   (lambda (student files)
     (let ((exportfiles (-select
                         (lambda (fn)
                           (string-match-p
                            (destructuring-bind
                                (amc-student copy)
                                (mapcar #'string-to-number student)
                              ;; alternative between null copy and
                              ;; non-null copy (i.e. exist photocopied
                              ;; sheets).
                              (format "\\`%04d:%04d-\\|\\`%04d-"
                                      amc-student copy amc-student))
                            fn))
                         amc-tools--corrected-files)))
       (if (and exportfiles (null (cdr exportfiles)))
           ;; replaces list of known files by the corrected pdf.
           (setcar files (car exportfiles)) 
         ;; shouldn't happen
         (if exportfiles
             (error "These corrected files all correspond to given student (%s): %s"
                    student
                    exportfiles)
           (error "No corrected files for given student, were they produced yet ? Student: %s"
                  student)))
       (callf nreverse (cdr files))))
   hash))


;; créer un fichier                                    

;; I'm using GNU parallel for doing the conversions.
;; @article{Tange2011a,
;;  title = {GNU Parallel - The Command-Line Power Tool},
;;  author = {O. Tange},
;;  address = {Frederiksberg, Denmark},
;;  journal = {;login: The USENIX Magazine},
;;  month = {Feb},
;;  number = {1},
;;  volume = {36},
;;  url = {http://www.gnu.org/s/parallel},
;;  year = {2011},
;;  pages = {42-47}
;; }



(defun amc-tools-make-files (hash)
  "Make a PDF for each element in ALIST.
ALIST is a mapping (STUDENT . FILES) where FILES ought to be a list of files.

Read the comments in the .el file to see what you have to do with the result."
  (interactive (list amc-tools--association-data))
  (when (y-or-n-p "Did you run the conversion tool to extract images from pdf ? If not, say `n' and do it!")
    (let ((default-directory (expand-file-name amc-tools-current-project))
          (file (make-temp-file "amc")))
      (make-directory (expand-file-name "cr/corrections/pdf-with-scans")
                      t)
      (with-temp-file file
        (insert "#!/bin/bash\n")
        (insert "cd " (shell-quote-argument default-directory) "\n")
        (maphash
         (lambda (student files)
           (insert (concat "sem "
                           (shell-quote-argument
                            (concat "convert"
                                    " "
                                    ;; Warning: doing "convert foo.pdf foo.jpg bar.pdf" results in a bloated bar.pdf.
                                    ;; my workaround : do a pdf->jpg conversion first. I used:
                                    ;;  for j in ~/Projets-QCM/MathF112-2014-15-janvier-{matin,aprem,pharma}/cr/corrections/pdf/; do cd $j; for i in *.pdf; do sem -j3 'convert -geometry 1000x1414 -density 300 "'$i'" "'${i%.pdf}'-%d.jpg"'; done; done

                                    ;; I was previously using pdfimages but this extracts the scan without the annotations.
                                    ;; There probably is a way to actually reuse the scan and flatten the annotation onto it but... how ?

                                    (let ((pdffile (concat "cr/corrections/pdf/" (car files))))
                                      (replace-regexp-in-string "\\.pdf" "-*.jpg" pdffile)
                                      ;; the replace here accounts for the above remark. Using a shell glob is easy but might have unwanted results.
                                      )
                                    " "
                                    (mapconcat (lambda (fn) (shell-quote-argument (concat "scans/" fn))) (cdr files) " ")
                                    " "
                                    (shell-quote-argument
                                     (expand-file-name
                                      (format "%s-with-scans.pdf" (file-name-sans-extension (car files)))
                                      "cr/corrections/pdf-with-scans")))))
                   "\n"))
         hash))
      (find-file file)
      (message "Reste à exécuter le présent fichier..."))))

;; the above function will open a buffer to run through sh.
;; - make sure that the quoting is right (look out for brackets and file with spaces)
;; - run the file with a shell
;; - copy everything to remote web server.
;; I use:  for j in ~/Projets-QCM/MathF112-2014-15-janvier-{matin,aprem,pharma}/cr/corrections/pdf-with-scans/; do cd $j; \cp -f * /home/youngfrog/sources/Math-F-112/2014-2015/public_html/ScanJanvier2015/; done
;; followed by: "make update" because I have a makefile in that rep.

;; - prepare the mails (function below)
;; - check that they are good (url is working, no obvious glitches, etc.)
;; - send them



(defun amc-tools-prepare-mails (who where template url-template)
  "Create eml files to be sent."
  (interactive "DWhere to put the eml files: \nfTemplate file: \nsURL template")
  ;; example values for template:
  ;; "~/Projets-QCM/MathF112-2014-15-Novembre-final/cr/corrections/pdf/Sendmails/template.mail"
  ;; "~/mesnotes/CoursEtTPs/data/ad/c8cad6-0a0d-4120-9ea8-967be8dd3a38/resultats/janvier/template.mail"

  ;; for url-template
  ;; "http://homepages.ulb.ac.be/~nrichard/Math-F-112/ScanJanvier2015/%s"
  (when (stringp who) (setq who (list who)))
  (setq template (with-temp-buffer (insert-file-contents template) (buffer-string)))
  (make-directory where t)
  (let ((list-of-files-to-send
         (cl-mapcan
          (lambda (dir)
            (directory-files
             dir
             t "@" t))
          who)))
    (mapc (lambda (file)
            "Make an .eml, attaching FILE to it. The %%TO%% field
            will be deduced from the filename."
            (let ((email (replace-regexp-in-string "\\`[0-9]\\{4\\}\\(?::[0-9]\\{4\\}\\)?-"
                                                   ""
                                                   (file-name-nondirectory
                                                    (string-remove-suffix "-with-scans.pdf"
                                                                          file))
                                                   t t))
                  (url (format url-template (file-name-nondirectory file))))
              (with-temp-file (expand-file-name (format "%s.eml" email)
                                                where)
                (insert template)
                (goto-char (point-min))
                (search-forward "%%TO%%")
                (replace-match email t t)
                (search-forward "%%URL%%")
                (replace-match url t t))))
          list-of-files-to-send)))

; (dolist (proj '("~/Projets-QCM/MathF112-2014-15-janvier-matin/")) (amc-tools-update-current-project proj) (call-interactively 'amc-tools-make-files))


;; (amc-tools-prepare-mails
;;  (list
;;   "~/Projets-QCM/MathF112-2014-15-janvier-aprem/cr/corrections/pdf-with-scans/"
;;   "~/Projets-QCM/MathF112-2014-15-janvier-matin/cr/corrections/pdf-with-scans/")
;;  "/home/youngfrog/sources/Math-F-112/2014-2015/mails-janvier/non-pharma"
;;  "~/mesnotes/CoursEtTPs/data/ad/c8cad6-0a0d-4120-9ea8-967be8dd3a38/resultats/janvier/template-non-pharma.mail"
;;  "http://homepages.ulb.ac.be/~nrichard/Math-F-112/ScanJanvier2015/%s")

;; (amc-tools-prepare-mails
;;  (list
;;   "~/Projets-QCM/MathF112-2014-15-janvier-pharma/cr/corrections/pdf-with-scans/")
;;  "/home/youngfrog/sources/Math-F-112/2014-2015/mails-janvier/pharma"
;;  "~/mesnotes/CoursEtTPs/data/ad/c8cad6-0a0d-4120-9ea8-967be8dd3a38/resultats/janvier/template-pharma.mail"
;;  "http://homepages.ulb.ac.be/~nrichard/Math-F-112/ScanJanvier2015/%s")



;;; fixme: certaines copies ne sont pas annotées!!!!

(provide 'amc-tools)

;;; amc-tools.el ends here
