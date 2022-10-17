# Emu6502

An MOS 6502 emulator written in the D language

Example:
```d
module example;

import std.stdio;
import emu6502;

void main() {
  ubyte[0x10000] memory;
  ubyte[29] code = [
    0xA2, 0x00,       //   lda #0
                      // loop:
    0xBD, 0x0E, 0x80, //   lda data,x
    0x8D, 0x00, 0xE0, //   sta $E000
    0xC9, 0x00,       //   cmp #0
    0xE8,             //   inx
    0xD0, 0xF5,       //   bne loop
    0x00,             //   brk
                      // data: .asciiz 'Hello, World!\n'
    0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x2C, 0x20, 0x57, 0x6F, 0x72, 0x6C, 0x64, 0x21, 0x0A, 0x00
  ];
  // put code into memory
  foreach(i, b; code)
    memory[0x8000+i] = b;
  // set reset vector
  memory[0xFFFC] = 0x00;
  memory[0xFFFD] = 0x80;
  // create emulator
  auto emu = new Emu6502(
    (ushort address) {
      return memory[address];
    },
    (ushort address, ubyte value) {
      if(address == 0xE000)
        write(cast(char)value);
      else
        memory[address] = value;
    },
    (ubyte n) {}
  );
  emu.reset();
  emu.throwExceptionOnBreak = true;
  // run until brk triggered
  try {
    while(true)
      emu.step();
  } catch(BreakException) {}
}
```

# TODO
* `BIT` instruction (currently acts like `NOP`)
* Handling `BRK` when `throwExceptionOnBreak` is false.
* Non-Maskable Interrupt
* Timings for some commands are inaccurate
