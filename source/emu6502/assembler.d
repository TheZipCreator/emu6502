/**
  A simple assembler for the 6502.
*/

module emu6502.assembler;

import std.conv, std.array;

class AssemblerException : Exception {
  size_t line;
  this(size_t line, string msg) {
    super(line.to!string~": "~msg);
  }
}

struct AssemblerWarning {
  size_t line;
  string msg;
  this(size_t line, string msg) {
    msg = line.to!string~": "~msg;
  }
}

struct AssemblerResult {
  ubyte[0x10000] memory;
  AssemblerWarning[] warnings;
}

private {
  enum TknType {
    COMMAND, IDENTIFIER, LABEL, NUMBER
  }
  struct Token {
    size_t line;
    TknType type;
    string name;
  }
  Token[] lex(string input) {
    static immutable string[] commands = [
      "brk", "ora", "asl", "php", "bpl", "clc", "jsr", "and", "bit", "rol", "plp", "bmi","sec", 
    ];
    {
      import std.string : replace;
      input = input.replace("\r\n", "\n"); // windows
    }
    Token[] tokens;
    auto ap = appender!string;
    size_t line;
    for(size_t i = 0; i < input.length; i++) {
      char c = input[i];
      switch(c) {

        default:
          ap ~= c;
      }
    }
    return tokens;
  }
}

AssemblerResult assemble(string code) {
  ubyte[0x10000] memory;
  AssemblerWarning[] warnings;
  return AssemblerResult(memory, warnings);
}