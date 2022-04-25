FLAGS = -Wall -Wextra

DEBUGFLAGS = -g -DDEBUG $(FLAGS)
SHIPFLAGS = -O3 -fomit-frame-pointer $(FLAGS)

default: lisp_d

lisp.o: lisp.c
	$(CC) -fPIC $(DEBUGFLAGS) -c lisp.c

lisp_d: lisp_d.d lisp.o
	$(DC) --d-debug -betterC lisp_d.d lisp.o

lisp_c: lisp.c
	$(CC) $(DEBUGFLAGS) -DUSE_C_MAIN $< -o $@
