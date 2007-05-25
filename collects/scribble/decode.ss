
(module decode mzscheme
  (require "struct.ss"
           (lib "contract.ss")
           (lib "class.ss"))

  (provide decode
           decode-part
           decode-flow
           decode-paragraph
           decode-content
           decode-string
           whitespace?)

  (provide-structs
   [title-decl ([tag any/c]
                [style any/c]
                [content list?])]
   [part-start ([depth integer?]
                [tag (or/c false/c string?)]
                [title list?])]
   [splice ([run list?])])

  (define (decode-string s)
    (let loop ([l '((#rx"---" mdash)
                    (#rx"--" ndash)
                    (#rx"``" ldquo)
                    (#rx"''" rdquo)
                    (#rx"'" rsquo))])
      (cond
       [(null? l) (list s)]
       [(regexp-match-positions (caar l) s)
	=> (lambda (m)
	     (append (decode-string (substring s 0 (caar m)))
		     (cdar l)
		     (decode-string (substring s (cdar m)))))]
       [else (loop (cdr l))])))

  (define (line-break? v)
    (and (string? v)
         (equal? v "\n")))

  (define (whitespace? v)
    (and (string? v)
         (regexp-match #px"^[\\s]*$" v)))

  (define (decode-accum-para accum)
    (if (andmap whitespace? accum)
        null
        (list (decode-paragraph (reverse (skip-whitespace accum))))))

  (define (decode-flow* l tag style title part-depth)
    (let loop ([l l][next? #f][accum null][title title][tag tag][style style])
      (cond
       [(null? l) (make-styled-part tag
                                    title 
                                    #f
                                    (make-flow (decode-accum-para accum))
                                    null
                                    style)]
       [(title-decl? (car l))
        (unless part-depth
          (error 'decode
                 "misplaced title: ~e"
                 (car l)))
        (when title
          (error 'decode
                 "found extra title: ~v"
                 (car l)))
        (loop (cdr l) next? accum 
              (title-decl-content (car l))
              (title-decl-tag (car l))
              (title-decl-style (car l)))]
       [(or (paragraph? (car l))
            (table? (car l))
            (itemization? (car l))
            (delayed-flow-element? (car l)))
        (let ([para (decode-accum-para accum)]
              [part (decode-flow* (cdr l) tag style title part-depth)])
          (make-styled-part (part-tag part)
                            (part-title-content part)
                            (part-collected-info part)
                            (make-flow (append para
                                               (list (car l)) 
                                               (flow-paragraphs (part-flow part))))
                            (part-parts part)
                            (styled-part-style part)))]
       [(part? (car l))
        (let ([para (decode-accum-para accum)]
              [part (decode-flow* (cdr l) tag style title part-depth)])
          (make-styled-part (part-tag part)
                            (part-title-content part)
                            (part-collected-info part)
                            (make-flow (append para
                                               (flow-paragraphs
                                                (part-flow part))))
                            (cons (car l) (part-parts part))
                            (styled-part-style part)))]
       [(and (part-start? (car l))
             (or (not part-depth)
                 ((part-start-depth (car l)) . <= . part-depth)))
        (unless part-depth
          (error 'decode
                 "misplaced part: ~e"
                 (car l)))
        (let ([s (car l)])
          (let loop ([l (cdr l)]
                     [s-accum null])
            (if (or (null? l)
                    (or (and (part-start? (car l))
                             ((part-start-depth (car l)) . <= . part-depth))
                        (part? (car l))))
                (let ([para (decode-accum-para accum)]
                      [s (decode-part (reverse s-accum)
                                      (part-start-tag s)
                                      (part-start-title s)
                                      (add1 part-depth))]
                      [part (decode-part l tag title part-depth)])
                  (make-styled-part (part-tag part)
                                    (part-title-content part)
                                    (part-collected-info part)
                                    (make-flow para)
                                    (cons s (part-parts part))
                                    (styled-part-style part)))
                (loop (cdr l) (cons (car l) s-accum)))))]
       [(splice? (car l))
	(loop (append (splice-run (car l)) (cdr l)) next? accum title tag style)]
       [(null? (cdr l)) (loop null #f (cons (car l) accum) title tag style)]
       [(and (pair? (cdr l))
	     (splice? (cadr l)))
	(loop (cons (car l) (append (splice-run (cadr l)) (cddr l))) next? accum title tag style)]
       [(line-break? (car l))
	(if next?
	    (loop (cdr l) #t accum title tag style)
	    (let ([m (match-newline-whitespace (cdr l))])
              (if m
                  (let ([part (loop m #t null title tag style)])
                    (make-styled-part (part-tag part)
                                      (part-title-content part)
                                      (part-collected-info part)
                                      (make-flow (append (decode-accum-para accum)
                                                         (flow-paragraphs (part-flow part))))
                                      (part-parts part)
                                      (styled-part-style part)))
                  (loop (cdr l) #f (cons (car l) accum) title tag style))))]
       [else (loop (cdr l) #f (cons (car l) accum) title tag style)])))

  (define (decode-part l tag title depth)
    (decode-flow* l tag #f title depth))

  (define (decode-flow l)
    (part-flow (decode-flow* l #f #f #f #f)))

  (define (match-newline-whitespace l)
    (cond
     [(null? l) #f]
     [(line-break? (car l))
      (skip-whitespace l)]
     [(splice? (car l))
      (match-newline-whitespace (append (splice-run (car l))
                                        (cdr l)))]
     [(whitespace? (car l))
      (match-newline-whitespace (cdr l))]
     [else #f]))

  (define (skip-whitespace l)
    (let loop ([l l])
      (if (or (null? l)
              (not (whitespace? (car l))))
          l
          (loop (cdr l)))))

  (define (decode l)
    (decode-part l #f #f 0))

  (define (decode-paragraph l)
    (make-paragraph 
     (decode-content l)))

  (define (decode-content l)
    (apply append
           (map (lambda (s)
                  (cond
                   [(string? s)
                    (decode-string s)]
                   [else (list s)]))
                (skip-whitespace l)))))