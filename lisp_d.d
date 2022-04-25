// dfmt off
import core.stdc.stdlib;
import core.stdc.stdio;
import core.stdc.string;
import core.stdc.stdarg;
import core.stdc.ctype;
import core.sys.posix.setjmp;

version (D_LP64) {
  alias value_t = ulong;
  alias number_t = long;
}
else {
  alias value_t = uint;
  alias number_t = int;
}

extern (C) extern __gshared char* stack_bottom;

enum PROCESS_STACK_SIZE = 2 * 1024 * 1024;

extern (C) extern __gshared uint SP;

extern (C) extern __gshared jmp_buf toplevel;

extern (C) extern __gshared char* infile;

extern (C) void lisp_init();

extern (C) value_t load_file(const(char)* fname);

extern (C) value_t set_symbol(const(char)* sym_name, value_t v);

extern (C) value_t read_sexpr(FILE* f);

extern (C) void print(FILE* f, value_t v);

extern (C) value_t toplevel_eval(value_t expr);

// extern (C) bool eval_line();

extern (C) int main(int argc, char** argv) {
  value_t v;

  stack_bottom = (cast(char*)&v) - PROCESS_STACK_SIZE;
  lisp_init();
  if (setjmp(toplevel)) {
    SP = 0;
    fprintf(stderr, "\n");
    if (infile) {
      fprintf(stderr, "error loading file \"%s\"\n", infile);
      infile = null;
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
