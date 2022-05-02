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

enum UNBOUND = Tag.sym;  // an invalid symbol pointer.

Tag tag(value_t x) { return cast(Tag) (x & 0x3); }

value_t tagptr(void* p, Tag t) {
  return (cast(value_t) p) | t;
}

T* ptr(T)(value_t x) {
  return cast(T*) (x & ~Tag.cons);
}

value_t builtin(int n) {
  return tagptr(cast(symbol_t*) (n << 2), Tag.builtin);
}

bool iscons(value_t x) { return tag(x) == Tag.cons; }

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
enum N_STACK = 49_152;
extern (C) extern __gshared value_t[N_STACK] Stack;

extern (C) extern __gshared uint SP;

ref value_t PUSH(value_t v) { return Stack[SP++] = v; }
ref value_t POP() { return Stack[--SP]; }
ref uint POPN(int n) { return SP -= n; }

extern (C) extern __gshared value_t NIL, T, LAMBDA, MACRO, LABEL, QUOTE;

// error utilities ------------------------------------------------------------

jmp_buf toplevel;

void lerror(Args ...)(const(char)* fmt, Args args) {
  fprintf(stderr, fmt, args);
  longjmp(toplevel, 1);
}

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

value_t mk_cons() {
  if (curheap > lim) gc();
  curheap += cons_t.sizeof;
  return tagptr(cast(cons_t*)curheap, Tag.cons);
}

// functions ending in _ are unsafe, faster versions
ref value_t car_(value_t v) { return ptr!cons_t(v).car; }
ref value_t cdr_(value_t v) { return ptr!cons_t(v).cdr; }

value_t cons_(value_t* pcar, value_t* pcdr) {
    value_t c = mk_cons();
    car_(c) = *pcar;
    cdr_(c) = *pcdr;
    return c;
}

value_t* cons(value_t* pcar, value_t* pcdr) {
  value_t c = mk_cons();
  car_(c) = *pcar; cdr_(c) = *pcdr;
  PUSH(c);
  return &Stack[SP-1];
}

// collector ------------------------------------------------------------------

value_t relocate(value_t v) {
  if (!iscons(v)) return v;
  if (car_(v) == UNBOUND) return cdr_(v);
  value_t nc = mk_cons();
  value_t a = car_(v);
  value_t d = cdr_(v);
  car_(v) = UNBOUND;
  cdr_(v) = nc;
  car_(nc) = relocate(a);
  cdr_(nc) = relocate(d);
  return nc;
}

void trace_globals(symbol_t* root) {
  while (root !is null) {
    root.binding = relocate(root.binding);
    trace_globals(root.left);
    root = root.right;
  }
}

void gc() {
  static int grew = 0;

  curheap = tospace;
  lim = curheap + heapsize- cons_t.sizeof;

  foreach (i; 0..SP) Stack[i] = relocate(Stack[i]);
  trace_globals(symtab);
  debug {
    fprintf(stderr, "[VERBOSE] gc found %ld/%d live conses\n",
            (curheap-tospace)/8, heapsize/8);
  }

  ubyte* temp = tospace;
  tospace = fromspace;
  fromspace = temp;

  // if we're using > 80% of the space, resize tospace so we have
  // more space to fill next time. if we grew tospace last time,
  // grow the other half of the heap this time to catch up.
  if (grew || ((lim-curheap) < cast(int)(heapsize/5))) {
    temp = cast(ubyte*) realloc(tospace, grew ? heapsize : heapsize*2);
    if (temp is null)
      lerror("out of memory\n");
    tospace = temp;
    if (!grew)
      heapsize*=2;
    grew = !grew;
  }
  if (curheap > lim)  // all data was live
    gc();
}

// read -----------------------------------------------------------------------

enum Token {
  TOK_NONE, TOK_OPEN, TOK_CLOSE, TOK_DOT, TOK_QUOTE, TOK_SYM, TOK_NUM
}

extern (C) extern __gshared Token toktype;
extern (C) extern __gshared value_t tokval;

extern (C) Token peek(FILE *f);

void take() { toktype = Token.TOK_NONE; }

// build a list of conses. this is complicated by the fact that all conses
// can move whenever a new cons is allocated. we have to refer to every cons
// through a handle to a relocatable pointer (i.e. a pointer on the stack).
extern (C) void read_list(FILE* f, value_t* pval);

// FIXME
void _read_list(FILE* f, value_t* pval) {
  value_t c;
  value_t *pc;
  uint t;

  PUSH(NIL);
  pc = &Stack[SP-1];  // to keep track of current cons cell
  t = peek(f);
  while (t != Token.TOK_CLOSE) {
    if (feof(f))
      lerror("read: error: unexpected end of input\n");
    c = mk_cons(); car_(c) = cdr_(c) = NIL;
    if (iscons(*pc))
      cdr_(*pc) = c;
    else
      *pval = c;
    *pc = c;
    c = read_sexpr(f);  // must be on separate lines due to undefined
    car_(*pc) = c;      // evaluation order

    t = peek(f);
    if (t == Token.TOK_DOT) {
      take();
      c = read_sexpr(f);
      cdr_(*pc) = c;
      t = peek(f);
      if (feof(f))
        lerror("read: error: unexpected end of input\n");
      if (t != Token.TOK_CLOSE)
        lerror("read: error: expected ')'\n");
    }
  }
  take();
  POP();
}

value_t read_sexpr(FILE* f) {
  final switch (peek(f)) with (Token) {
    case TOK_NONE:
      return NIL;
    case TOK_CLOSE:
      take();
      lerror("read: error: unexpected ')'\n");
      assert(false, "read: error: unexpected ')'\n");
    case TOK_DOT:
      take();
      lerror("read: error: unexpected '.'\n");
      assert(false, "read: error: unexpected '.'\n");
    case TOK_SYM:
    case TOK_NUM:
      take();
      return tokval;
    case TOK_QUOTE:
      take();
      PUSH(read_sexpr(f));
      value_t v = cons_(&QUOTE, cons(&Stack[SP-1], &NIL));
      POPN(2);
      return v;
    case TOK_OPEN:
      take();
      PUSH(NIL);
      read_list(f, &Stack[SP-1]);
      return POP();
  }
}

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
