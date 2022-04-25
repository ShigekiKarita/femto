#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <setjmp.h>
#include <stdarg.h>
#include <ctype.h>
#include <sys/types.h>

#ifdef __LP64__
typedef u_int64_t value_t;
typedef int64_t number_t;
#else
typedef u_int32_t value_t;
typedef int32_t number_t;
#endif

extern char *stack_bottom;

#define PROCESS_STACK_SIZE (2*1024*1024)

extern u_int32_t SP;

extern jmp_buf toplevel;

extern char *infile;

void lisp_init(void);

value_t load_file(char *fname);

value_t set_symbol(char* name, value_t v);

value_t read_sexpr(FILE *f);

void print(FILE *f, value_t v);

value_t toplevel_eval(value_t expr);

// _Bool eval_line(void);

int main(int argc, char* argv[])
{
    value_t v;

    stack_bottom = ((char*)&v) - PROCESS_STACK_SIZE;
    lisp_init();
    if (setjmp(toplevel)) {
        SP = 0;
        fprintf(stderr, "\n");
        if (infile) {
            fprintf(stderr, "error loading file \"%s\"\n", infile);
            infile = NULL;
        }
        goto repl;
    }
    load_file("system.lsp");
    if (argc > 1) { load_file(argv[1]); return 0; }
    printf("Welcome to femtoLisp ----------------------------------------------------------\n");
 repl:
    // while (eval_line()) {}
    while (1) {
      printf("> ");
      v = read_sexpr(stdin);
      if (feof(stdin)) return 0;

      print(stdout, v=toplevel_eval(v));
      set_symbol("that", v);
      printf("\n\n");
    }
    return 0;
}
