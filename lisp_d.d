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

enum Tag {
  num = 0x0,
  builtin = 0x1,
  sym = 0x2,
  cons = 0x3,
}

value_t tagptr(symbol_t* p, Tag t) {
  return (cast(value_t) p) | t;
}

T* ptr(T)(value_t x) {
  return cast(T*) (x & ~(cast(value_t) 0x3));
}

value_t builtin(int n) {
  return tagptr(cast(symbol_t*) (n << 2), Tag.builtin);
}

value_t set(value_t s, value_t v) {
  return ptr!symbol_t(s).binding = v;
}

value_t setc(value_t s, value_t v) {
  return ptr!symbol_t(s).constant = v;
}


enum {
    // special forms
    F_QUOTE=0, F_COND, F_IF, F_AND, F_OR, F_WHILE, F_LAMBDA, F_MACRO, F_LABEL,
    F_PROGN,
    // functions
    F_EQ, F_ATOM, F_CONS, F_CAR, F_CDR, F_READ, F_EVAL, F_PRINT, F_SET, F_NOT,
    F_LOAD, F_SYMBOLP, F_NUMBERP, F_ADD, F_SUB, F_MUL, F_DIV, F_LT, F_PROG1,
    F_APPLY, F_RPLACA, F_RPLACD, F_BOUNDP, N_BUILTINS
}

static string[] builtin_names =
    [ "quote", "cond", "if", "and", "or", "while", "lambda", "macro", "label",
      "progn", "eq", "atom", "cons", "car", "cdr", "read", "eval", "print",
      "set", "not", "load", "symbolp", "numberp", "+", "-", "*", "/", "<",
      "prog1", "apply", "rplaca", "rplacd", "boundp" ];

extern (C) extern __gshared char* stack_bottom;

enum PROCESS_STACK_SIZE = 2 * 1024 * 1024;

extern (C) extern __gshared uint SP;

extern (C) extern __gshared value_t NIL, T, LAMBDA, MACRO, LABEL, QUOTE;

// error utilities ------------------------------------------------------------

extern (C) extern __gshared jmp_buf toplevel;

// safe cast operators --------------------------------------------------------

// symbol table ---------------------------------------------------------------

// TODO(karita): Remove extern when gc() is implemented.
extern (C) extern __gshared symbol_t* symtab;

symbol_t* mk_symbol(const(char)* str) {
  // TODO(karita): Use str.length instead of strlen.
  size_t len = strlen(str);
  auto sym = cast(symbol_t*) malloc(symbol_t.sizeof + len);
  // strcpy(sym.name.ptr, str);
  memcpy(sym.name.ptr, str, len + 1);
  return sym;
}

symbol_t** symtab_lookup(symbol_t** ptree, const(char)* str) {
  while (*ptree !is null) {
    int x = strcmp(str, (*ptree).name.ptr);
    if (x == 0) return ptree;
    if (x < 0) ptree = &(*ptree).left;
    else ptree = &(*ptree).right;
  }
  return ptree;
}

value_t symbol(const(char)* str) {
  symbol_t** pnode = symtab_lookup(&symtab, str);
  if (*pnode is null) *pnode = mk_symbol(str);
  return tagptr(*pnode, Tag.sym);
}

// initialization -------------------------------------------------------------

extern (C) extern __gshared ubyte* fromspace;
extern (C) extern __gshared ubyte* tospace;
extern (C) extern __gshared ubyte* curheap;
extern (C) extern __gshared ubyte* lim;
extern (C) extern __gshared uint heapsize;

void lisp_init() {
  fromspace = cast(ubyte*) malloc(heapsize);
  tospace   = cast(ubyte*) malloc(heapsize);
  curheap = fromspace;
  lim = curheap+heapsize-cons_t.sizeof;

  NIL = symbol("nil"); setc(NIL, NIL);
  T   = symbol("t");   setc(T,   T);
  LAMBDA = symbol("lambda");
  MACRO = symbol("macro");
  LABEL = symbol("label");
  QUOTE = symbol("quote");
  foreach (i; 0 .. N_BUILTINS) {
    setc(symbol(builtin_names[i].ptr), builtin(i));
  }
  setc(symbol("princ"), builtin(F_PRINT));
}

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
