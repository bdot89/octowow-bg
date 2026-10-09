param([Parameter(Mandatory=$true)][string[]]$Files, [switch]$Globals)
# Lua 5.0 syntax checker (recursive descent over the 5.0 grammar).
# Reports: syntax errors, 5.1-only syntax (#, %, ... as an expression),
# functions with more than 32 upvalues, more than 200 active locals,
# and statements after return/break.

$src = @"
using System;
using System.Collections.Generic;
using System.Text;

public class LuaCheck {
  enum K { Name, Number, String, Op, Kw, Eof }
  class Tok { public K k; public string v; public int line; }
  List<Tok> toks = new List<Tok>();
  int p = 0;
  public List<string> errors = new List<string>();
  string file;
  static HashSet<string> KW = new HashSet<string>(new string[] {
    "and","break","do","else","elseif","end","false","for","function","if","in",
    "local","nil","not","or","repeat","return","then","true","until","while" });

  class Func { public Func parent; public List<List<string>> blocks = new List<List<string>>();
               public HashSet<string> upvals = new HashSet<string>(); public int line; public int active; public int maxActive; public string name; }
  Func fn;

  public LuaCheck(string f, string text) { file = f; Lex(text); }

  void Err(int line, string msg) { errors.Add(file + ":" + line + ": " + msg); }

  void Lex(string s) {
    int i = 0, line = 1, n = s.Length;
    while (i < n) {
      char c = s[i];
      if (c == '\n') { line++; i++; continue; }
      if (char.IsWhiteSpace(c)) { i++; continue; }
      if (c == '-' && i + 1 < n && s[i+1] == '-') {
        if (i + 3 < n && s[i+2] == '[' && s[i+3] == '[') {
          int e = s.IndexOf("]]", i + 4);
          if (e < 0) { Err(line, "unfinished long comment"); return; }
          for (int k = i; k < e; k++) if (s[k] == '\n') line++;
          i = e + 2; continue;
        }
        while (i < n && s[i] != '\n') i++;
        continue;
      }
      if (c == '[' && i + 1 < n && s[i+1] == '[') {
        int e = s.IndexOf("]]", i + 2);
        if (e < 0) { Err(line, "unfinished long string"); return; }
        int l0 = line;
        for (int k = i; k < e; k++) if (s[k] == '\n') line++;
        Add(K.String, s.Substring(i, e + 2 - i), l0); i = e + 2; continue;
      }
      if (c == '"' || c == '\'') {
        int j = i + 1; StringBuilder sb = new StringBuilder();
        while (j < n && s[j] != c) {
          if (s[j] == '\\') { j += 2; continue; }
          if (s[j] == '\n') { Err(line, "unfinished string"); break; }
          j++;
        }
        Add(K.String, s.Substring(i, Math.Min(j + 1, n) - i), line); i = j + 1; continue;
      }
      if (char.IsDigit(c) || (c == '.' && i + 1 < n && char.IsDigit(s[i+1]))) {
        int j = i;
        if (c == '0' && i + 1 < n && (s[i+1] == 'x' || s[i+1] == 'X')) { j += 2; while (j < n && Uri.IsHexDigit(s[j])) j++; }
        else {
          while (j < n && (char.IsDigit(s[j]) || s[j] == '.')) j++;
          if (j < n && (s[j] == 'e' || s[j] == 'E')) { j++; if (j < n && (s[j] == '+' || s[j] == '-')) j++; while (j < n && char.IsDigit(s[j])) j++; }
        }
        Add(K.Number, s.Substring(i, j - i), line); i = j; continue;
      }
      if (char.IsLetter(c) || c == '_') {
        int j = i; while (j < n && (char.IsLetterOrDigit(s[j]) || s[j] == '_')) j++;
        string w = s.Substring(i, j - i);
        Add(KW.Contains(w) ? K.Kw : K.Name, w, line); i = j; continue;
      }
      string[] ops = { "...", "..", "==", "~=", "<=", ">=", "+", "-", "*", "/", "^", "<", ">", "=", "(", ")", "{", "}", "[", "]", ";", ":", ",", ".", "#", "%" };
      bool found = false;
      foreach (string o in ops) {
        if (string.CompareOrdinal(s, i, o, 0, o.Length) == 0) {
          if (o == "#" || o == "%") Err(line, "'" + o + "' is not a Lua 5.0 operator (use table.getn / math.mod)");
          Add(K.Op, o, line); i += o.Length; found = true; break;
        }
      }
      if (!found) { Err(line, "unexpected character '" + c + "'"); i++; }
    }
    Add(K.Eof, "<eof>", line);
  }
  void Add(K k, string v, int line) { Tok t = new Tok(); t.k = k; t.v = v; t.line = line; toks.Add(t); }

  Tok Cur { get { return toks[p]; } }
  bool Is(string v) { Tok t = Cur; return (t.k == K.Op || t.k == K.Kw) && t.v == v; }
  bool Accept(string v) { if (Is(v)) { p++; return true; } return false; }
  void Expect(string v, string what) {
    if (!Accept(v)) throw new Exception("line " + Cur.line + ": '" + v + "' expected " + what + " near '" + Cur.v + "'");
  }
  string Name() {
    if (Cur.k != K.Name) throw new Exception("line " + Cur.line + ": name expected near '" + Cur.v + "'");
    return toks[p++].v;
  }

  // ---- scopes
  void OpenFunc(int line, string name) { Func f = new Func(); f.parent = fn; f.line = line; f.name = name; fn = f; OpenBlock(); }
  void CloseFunc() {
    CloseBlock();
    if (fn.upvals.Count > 32) Err(fn.line, "function " + fn.name + " has " + fn.upvals.Count + " upvalues (Lua 5.0 max 32)");
    if (fn.maxActive > 200) Err(fn.line, "function " + fn.name + " has " + fn.maxActive + " active locals (max 200)");
    fn = fn.parent;
  }
  void OpenBlock() { fn.blocks.Add(new List<string>()); }
  void CloseBlock() { List<string> b = fn.blocks[fn.blocks.Count - 1]; fn.active -= b.Count; fn.blocks.RemoveAt(fn.blocks.Count - 1); }
  void Declare(string name) { fn.blocks[fn.blocks.Count - 1].Add(name); fn.active++; if (fn.active > fn.maxActive) fn.maxActive = fn.active; }
  static bool Has(Func f, string name) {
    for (int i = f.blocks.Count - 1; i >= 0; i--) if (f.blocks[i].Contains(name)) return true;
    return false;
  }
  public SortedDictionary<string, int> globals = new SortedDictionary<string, int>();
  void Resolve(string name) {
    if (Has(fn, name)) return;
    List<Func> chain = new List<Func>();
    Func f = fn;
    while (f.parent != null) {
      chain.Add(f);
      f = f.parent;
      if (Has(f, name)) { foreach (Func c in chain) c.upvals.Add(name); return; }
    }
    if (!globals.ContainsKey(name)) globals[name] = toks[p].line;
  }

  // ---- grammar
  public void Run() {
    try {
      OpenFunc(1, "<main chunk>");
      Block();
      if (Cur.k != K.Eof) throw new Exception("line " + Cur.line + ": unexpected '" + Cur.v + "'");
      CloseFunc();
    } catch (Exception e) { errors.Add(file + ": " + e.Message); }
  }

  bool BlockEnd() { return Cur.k == K.Eof || Is("end") || Is("else") || Is("elseif") || Is("until"); }

  void Block() {
    while (!BlockEnd()) {
      if (Is("return")) {
        p++;
        if (!BlockEnd() && !Is(";")) ExpList();
        Accept(";");
        if (!BlockEnd()) throw new Exception("line " + Cur.line + ": statement after return");
        return;
      }
      if (Is("break")) {
        p++; Accept(";");
        if (!BlockEnd()) throw new Exception("line " + Cur.line + ": statement after break");
        return;
      }
      Statement();
      Accept(";");
    }
  }

  void Statement() {
    int line = Cur.line;
    if (Accept("if")) {
      Expr(); Expect("then", "after if condition"); OpenBlock(); Block(); CloseBlock();
      while (Accept("elseif")) { Expr(); Expect("then", "after elseif"); OpenBlock(); Block(); CloseBlock(); }
      if (Accept("else")) { OpenBlock(); Block(); CloseBlock(); }
      Expect("end", "to close if at line " + line); return;
    }
    if (Accept("while")) { Expr(); Expect("do", "after while"); OpenBlock(); Block(); CloseBlock(); Expect("end", "to close while at line " + line); return; }
    if (Accept("do")) { OpenBlock(); Block(); CloseBlock(); Expect("end", "to close do at line " + line); return; }
    if (Accept("repeat")) { OpenBlock(); Block(); Expect("until", "to close repeat at line " + line); Expr(); CloseBlock(); return; }
    if (Accept("for")) {
      string n1 = Name();
      if (Accept("=")) {
        Expr(); Expect(",", "in numeric for"); Expr(); if (Accept(",")) Expr();
        Expect("do", "in for"); OpenBlock(); Declare("(for index)"); Declare("(for limit)"); Declare("(for step)"); Declare(n1);
        Block(); CloseBlock(); Expect("end", "to close for at line " + line); return;
      }
      List<string> names = new List<string>(); names.Add(n1);
      while (Accept(",")) names.Add(Name());
      Expect("in", "in generic for"); ExpList(); Expect("do", "in for");
      OpenBlock(); Declare("(for generator)"); Declare("(for state)"); foreach (string nm in names) Declare(nm);
      Block(); CloseBlock(); Expect("end", "to close for at line " + line); return;
    }
    if (Accept("function")) {
      string first = Name(); Resolve(first); string full = first; bool method = false;
      while (Accept(".")) full += "." + Name();
      if (Accept(":")) { full += ":" + Name(); method = true; }
      FuncBody(method, line, full); return;
    }
    if (Accept("local")) {
      if (Accept("function")) { string nm = Name(); Declare(nm); FuncBody(false, line, nm); return; }
      List<string> names = new List<string>(); names.Add(Name());
      while (Accept(",")) names.Add(Name());
      if (Accept("=")) ExpList();
      foreach (string nm in names) Declare(nm);
      return;
    }
    // assignment or call
    bool isCall = SuffixedExp();
    if (Is("=") || Is(",")) {
      while (Accept(",")) { if (SuffixedExp()) throw new Exception("line " + Cur.line + ": cannot assign to a call"); }
      Expect("=", "in assignment"); ExpList(); return;
    }
    if (!isCall) throw new Exception("line " + Cur.line + ": syntax error near '" + Cur.v + "'");
  }

  void FuncBody(bool method, int line, string name) {
    OpenFunc(line, name);
    if (method) Declare("self");
    Expect("(", "for function parameters");
    if (!Is(")")) {
      do {
        if (Accept("...")) { Declare("arg"); break; }
        Declare(Name());
      } while (Accept(","));
    }
    Expect(")", "after parameters");
    Block();
    Expect("end", "to close function at line " + line);
    CloseFunc();
  }

  void ExpList() { Expr(); while (Accept(",")) Expr(); }

  // returns true when the expression ends in a call
  bool SuffixedExp() {
    bool call = false;
    if (Cur.k == K.Name) { Resolve(Cur.v); p++; }
    else if (Accept("(")) { Expr(); Expect(")", "to close ("); }
    else throw new Exception("line " + Cur.line + ": unexpected symbol near '" + Cur.v + "'");
    while (true) {
      if (Accept(".")) { Name(); call = false; }
      else if (Accept("[")) { Expr(); Expect("]", "to close ["); call = false; }
      else if (Accept(":")) { Name(); Args(); call = true; }
      else if (Is("(") || Is("{") || Cur.k == K.String) { Args(); call = true; }
      else return call;
    }
  }

  void Args() {
    if (Cur.k == K.String) { p++; return; }
    if (Is("{")) { Table(); return; }
    Expect("(", "for call arguments");
    if (!Is(")")) ExpList();
    Expect(")", "to close call arguments");
  }

  void Table() {
    Expect("{", "table");
    while (!Is("}")) {
      if (Accept("[")) { Expr(); Expect("]", "in table key"); Expect("=", "in table field"); Expr(); }
      else if (Cur.k == K.Name && toks[p+1].k == K.Op && toks[p+1].v == "=") { p += 2; Expr(); }
      else Expr();
      if (!Accept(",") && !Accept(";")) break;
    }
    Expect("}", "to close table");
  }

  static int Prio(string op, out int right) {
    right = 0;
    switch (op) {
      case "or": return 1; case "and": return 2;
      case "<": case ">": case "<=": case ">=": case "~=": case "==": return 3;
      case "..": right = 1; return 5;
      case "+": case "-": return 6;
      case "*": case "/": return 7;
      case "^": right = 1; return 10;
    }
    return -1;
  }

  void Expr() { SubExpr(0); }

  void SubExpr(int limit) {
    if (Is("not") || Is("-")) { p++; SubExpr(8); }
    else Simple();
    while (true) {
      Tok t = Cur;
      if (t.k != K.Op && t.k != K.Kw) return;
      int right; int pr = Prio(t.v, out right);
      if (pr <= limit) return;
      p++;
      SubExpr(right == 1 ? pr - 1 : pr);
    }
  }

  void Simple() {
    Tok t = Cur;
    if (t.k == K.Number || t.k == K.String) { p++; return; }
    if (Is("nil") || Is("true") || Is("false")) { p++; return; }
    if (Is("...")) throw new Exception("line " + t.line + ": '...' as an expression is Lua 5.1 (use arg)");
    if (Is("{")) { Table(); return; }
    if (Accept("function")) { FuncBody(false, t.line, "<anonymous>"); return; }
    SuffixedExp();
  }

  public static string Check(string file, string text) {
    LuaCheck c = new LuaCheck(file, text);
    if (c.errors.Count == 0) c.Run();
    return string.Join("\n", c.errors.ToArray());
  }

  public static string Globals(string file, string text) {
    LuaCheck c = new LuaCheck(file, text);
    if (c.errors.Count == 0) c.Run();
    List<string> l = new List<string>();
    foreach (KeyValuePair<string, int> kv in c.globals) l.Add(kv.Key + ":" + kv.Value);
    return string.Join(" ", l.ToArray());
  }
}
"@
Add-Type -TypeDefinition $src -Language CSharp

$bad = 0
foreach ($f in $Files) {
  $text = [IO.File]::ReadAllText($f)
  $r = [LuaCheck]::Check($f, $text)
  if ($r) { Write-Output $r; $bad++ } else { Write-Output ("ok   " + $f) }
  if ($Globals) { Write-Output ("     globals: " + [LuaCheck]::Globals($f, $text)) }
}
if ($bad -gt 0) { Write-Output "$bad file(s) with problems" }
