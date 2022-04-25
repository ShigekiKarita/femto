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

struct cons_t {
    value_t car;
    value_t cdr;
}

struct symbol_t {
  value_t binding;   // global value binding
  value_t constant;  // constant binding (used only for builtins)
  symbol_t* left;
  symbol_t* right;
  char[1] name;      // for an outer string pointer.
}

T* ptr(T)(value_t x) {
  return cast(T*) (x & ~(cast(value_t) 0x3));
}

value_t set(value_t s, value_t v) {
  return ptr!symbol_t(s).binding = v;
}

extern (C) extern __gshared char* stack_bottom;

enum PROCESS_STACK_SIZE = 2 * 1024 * 1024;

extern (C) extern __gshared uint SP;

// error utilities ------------------------------------------------------------

extern (C) extern __gshared jmp_buf toplevel;

// safe cast operators --------------------------------------------------------

// symbol table ---------------------------------------------------------------

extern (C) value_t symbol(const(char)* str);

// initialization -------------------------------------------------------------

extern (C) void lisp_init();

// conses ---------------------------------------------------------------------

// collector ------------------------------------------------------------------

// read -----------------------------------------------------------------------

extern (C) value_t read_sexpr(FILE* f);

// print ----------------------------------------------------------------------

extern (C) void print(FILE* f, value_t v);

// eval -----------------------------------------------------------------------

// repl -----------------------------------------------------------------------

extern (C) extern __gshared char* infile;

extern (C) value_t toplevel_eval(value_t expr);

extern (C) value_t load_file(const(char)* fname);

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
    set(symbol("that"), v);
    printf("\n\n");
  }
  return 0;
}
