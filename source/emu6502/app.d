/**
  A simple application to use Emu6502 in the terminal

  Reading from $E000 will return a single char from stdin and writing to it will output a char to stdout.
  On Non-Windows systems, stdin is line-buffered
	
	Storing to $E001 will output the number as hex

  Programs are placed at $8000 and reset vector is set to $8000
*/
module emu6502.app;

import emu6502;

import std.stdio, std.file;

ubyte getch();

version(Windows) {
  extern(C) int _getch();
  ubyte getch() {
    int k = _getch;
    return k == '\r' ? '\n' : cast(ubyte)k;
  }
} else {
  string buf;
  ubyte getch() {
    if(buf.length == 0)
      buf = readln();
    ubyte b = cast(ubyte)buf[0];
    buf = buf[1..$];
    return b;
  }
}

void main(string[] args) {
  if(args.length != 3) {
    writeln("Required args: "~args[0]~" <run / assemble> <file>");
    return;
  }
  if(args[1] == "run") {
    ubyte[] code = cast(ubyte[])read(args[2]);
    ubyte[0x10000] memory;
    foreach(i, b; code) {
      memory[i+0x8000] = b;
    }
    memory[0xFFFC] = 0x00;
    memory[0xFFFD] = 0x80;
    auto emu = new Emu6502(
      (ushort address) {
        if(address == 0xE000)
          return getch;
        return memory[address];
      },
      (ushort address, ubyte value) {
        if(address == 0xE000)
          write(cast(char)value);
        else if(address == 0xE001)
          writef("%02x", value);
        memory[address] = value;
      },
      (ubyte n) {}
    );
    emu.reset();
    emu.throwExceptionOnBreak = true;
    try {
      while(true)
        emu.step;
    } catch(BreakException e) {
      writeln("\n", e.msg);
    } catch(InvalidOpcodeException e) {
      writeln("\n", e.msg);
    }
    return;
  } else if(args[1] == "assemble") {
    string output = args[1]~".bin";
    
    return;
  }
  writeln("Mode "~args[1]~" not found");
}