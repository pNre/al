## A Lisp in x86-64 asm

Still missing a lot.

### Compiling and running
	make

### Examples
	> (car (quote (* r r)))
	*
	
	> (cdr (quote (* r r)))
	(r r)
	
	> (def pi 3.1415)
	pi
	
	> (def c-area (lambda (r) (* pi (* r r))))
	c-area
	
	> (c-area 2)
	12.566000

	