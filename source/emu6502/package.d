module emu6502;

/// Thrown when an invalid opcode is executed
class InvalidOpcodeException : Exception {
  ubyte opcode;
  this(ushort pc, ubyte opcode) {
    import std.format;
    super(format("Invalid opcode $%02x at address $%04x", opcode, pc));
    this.opcode = opcode;
  }
}

/// Thrown when a BRK ($00) instruction is executed and `throwExceptionOnBreak` is true
class BreakException : Exception {
  ushort pos;
  this(ushort pos) {
    import std.format;
    super(format("Break at $%04x", pos));
    this.pos = pos;
  }
}

/// Represents a single 6502 processor
class Emu6502 {
  ubyte delegate(ushort address) _load; /// Gives value of address
  void delegate(ushort address, ubyte value) _store; /// Stores a value to an address
  void delegate(ubyte n) _wait; /// Waits n cycles

  // This language is stupid and casts fucking everything to an int so I have do this stupid hack so I don't have
  // to have cast(ushort) everywhere
  ubyte load(int address) {
    return _load(cast(ushort)address);
  }
  void store(int address, int value) {
    return _store(cast(ushort)address, cast(ubyte)value);
  }
  void wait(int n) {
    _wait(cast(ubyte)n);
  }

  ushort pc; /// Program Counter
  ubyte a;   /// Accumulator
  ubyte x;   /// X register
  ubyte y;   /// Y register
  ubyte sr;  /// Status register
  /** 
   Contains all the SR Flags.

   You'd do something like `emu.sr & SRFlag.C` to check carry for example
   */
  enum SRFlag {
    // why can't I just say `ubyte enum { ... }` or something instead of having to do this
    N = cast(ubyte)(1 << 7),
    V = cast(ubyte)(1 << 6),
    B = cast(ubyte)(1 << 4),
    D = cast(ubyte)(1 << 3),
    I = cast(ubyte)(1 << 2),
    Z = cast(ubyte)(1 << 1),
    C = cast(ubyte)(1 << 0)
  }
  ubyte sp; /// Stack pointer

  bool throwExceptionOnBreak = false;

  /// Initializes the emulator and triggers a hardware reset
  this(ubyte delegate(ushort address) load, 
    void delegate(ushort address, ubyte value) store, 
    void delegate(ubyte n) wait) {
    this._load = load;
    this._store = store;
    this._wait = wait;
  }

  /// Set a SR flag
  void setFlag(SRFlag flag) {
    sr |= flag;
  }

  /// Clear SR flag
  void clearFlag(SRFlag flag) {
    sr &= ~flag;
  }

  /// Set an SR flag to a value
  void setFlag(SRFlag flag, bool value) {
    if(value)
      setFlag(flag);
    else
      clearFlag(flag);
  }

  void setFlag(SRFlag flag, int value) {
    setFlag(flag, value != 0);
  }

  /// Gets an SR flag
  bool getFlag(SRFlag flag) {
    return (sr & flag) != 0;
  }

  /// Loads a 16-bit word at a given address in little-endian order
  ushort loadw(ushort address) {
    return load(address) | load(address+1) << 8;
  }

  /// Triggers a hardware reset
  void reset() {
    pc = loadw(0xFFFC);
    wait(7);
  }

  /// Pushes a byte to the stack
  void push(ubyte b) {
    store(0x100+(sp++), b);
  }

  /// Pops a byte from the stack
  ubyte pop() {
    return load(0x100+(sp--));
  }

  /// Pushes a word to the stack
  void pushw(ushort w) {
    store(sp++, w & 0xFF);
    store(sp++, w >> 8);
  }

  /// Pops a word from the stack
  ushort popw() {
    return load(0x100+(sp--)) << 8 | load(0x100+(sp--));
  }

  // int version because again D is dumb
  void push(int b) {
    push(cast(ubyte)b);
  }
  void pushw(int w) {
    push(cast(ushort)w);
  }
  ushort loadw(int address) {
    return loadw(cast(ushort)address);
  }

  /// Returns the next byte after the PC and increments PC
  private ubyte next() {
    return load(pc++);
  }

  /// Returns the next word after the PC and increments PC by 2
  private ushort nextw() {
    ushort w = loadw(pc);
    pc += 2;
    return w;
  }

  /// Executes the next instruction
  void step() {
    ubyte opcode = next;
    void flagsFromA() {
      setFlag(SRFlag.Z, a == 0);
      setFlag(SRFlag.N, a > 127);
    }
    void asl(int l) {
      ubyte prev = load(l);
      ubyte v = (prev << 1) & 0xFF;
      setFlag(SRFlag.C, prev > v);
      setFlag(SRFlag.N, v > 127);
      setFlag(SRFlag.Z, v == 0);
      store(l, v);
    }
    void rol(int l) {
      ubyte prev = load(l);
      ubyte v = (prev << 1) & 0xFF;
      v |= getFlag(SRFlag.C);
      setFlag(SRFlag.C, prev > v);
      setFlag(SRFlag.N, v > 127);
      setFlag(SRFlag.Z, v == 0);
      store(l, v);
    }
    void ror(int l) {
      ubyte prev = load(l);
      ubyte v = prev >> 1;
      v |= getFlag(SRFlag.C) << 7;
      setFlag(SRFlag.C, prev & 0x01);
      setFlag(SRFlag.N, v > 127);
      setFlag(SRFlag.Z, v == 0);
      store(l, v);
    }
    void lsr(int l) {
      ubyte prev = load(l);
      ubyte v = prev >> 1;
      setFlag(SRFlag.C, prev > v);
      setFlag(SRFlag.Z, v == 0);
      store(l, v);
    }
    string accOp(string name, string o) {
      import std.string : replace;
      return q{
        void [name](int v) {
          a [o]= v;
          flagsFromA();
        }
      }.replace("[o]", o).replace("[name]", name);
    }
    mixin(accOp("ora", "|"));
    mixin(accOp("and", "&"));
    mixin(accOp("eor", "^"));
    void adc(int v) {
      ubyte prev = a;
      a += v;
      setFlag(SRFlag.C, prev > a);
      flagsFromA();
    }
    void sbc(int v) {
      ubyte prev = a;
      a -= v;
      a -= getFlag(SRFlag.C);
      clearFlag(SRFlag.C);
      setFlag(SRFlag.V, prev > a);
      flagsFromA();
    }
    void branchIf(bool b, ushort where) {
      if(b)
        pc = cast(ushort)(pc+cast(byte)where);
    }
    void compare(int a, int b) {
      if(a == b) {
        clearFlag(SRFlag.N);
        setFlag(SRFlag.Z);
        setFlag(SRFlag.C);
      } else if(a < b) {
        setFlag(SRFlag.N, a >> 7);
        clearFlag(SRFlag.Z);
        clearFlag(SRFlag.C);
      } else if(a > b) {
        setFlag(SRFlag.N, a >> 7);
        clearFlag(SRFlag.Z);
        setFlag(SRFlag.C);
      }
    }
    switch(opcode) {
      case 0x00: {
        //BRK impl
        // TODO
        if(throwExceptionOnBreak)
          throw new BreakException(cast(ushort)(pc-1));
        break;
      }
      case 0x01: {
        //ORA X,ind
        ora(next+x);
        break;
      }
      case 0x05: {
        //ORA zpg
        ora(load(next));
        wait(2);
        break;
      }
      case 0x06: {
        //ASL zpg
        asl(next);
        break;
      }
      case 0x08: {
        //PHP impl
        setFlag(SRFlag.B);
        push(sr);
        wait(1);
        break;
      }
      case 0x09: {
        //ORA #
        ora(next);
        wait(1);
        break;
      }
      case 0x0A: {
        //ASL A
        a <<= 1;
        wait(2);
        break;
      }
      case 0x0D: {
        //ORA abs
        ora(nextw);
        wait(4);
        break;
      }
      case 0x0E: {
        //ASL abs
        asl(nextw);
        wait(6);
        break;
      }
      case 0x10: {
        //BPL rel
        ushort l = nextw;
        if(!getFlag(SRFlag.N))
          pc = l;
        break;
      }
      case 0x11: {
        //ORA ind,Y
        ora(load(load(next)+y));
        wait(5); // TODO: inaccurate
        break;
      }
      case 0x15: {
        //ORA zpg,X
        ora(next+x);
        wait(4);
        break;
      }
      case 0x16: {
        //ASL zpg,X
        asl(next+x);
        wait(6);
        break;
      }
      case 0x18: {
        //CLC impl
        clearFlag(SRFlag.C);
        wait(2);
        break;
      }
      case 0x19: {
        //ORA abs,Y
        ora(load(nextw+y));
        wait(4); // TODO: inaccurate
        break;
      }
      case 0x1D: {
        //ORA abs,X
        ora(load(nextw+x));
        wait(4); // TODO: inaccurate
        break;
      }
      case 0x1E: {
        //ASL abs,X
        asl(nextw+x);
        wait(7);
        break;
      }
      case 0x20: {
        //JSR abs
        pushw(pc);
        pc = nextw;
        wait(6);
        break;
      }
      case 0x21: {
        //AND X,ind
        and(loadw(next+x));
        wait(6); // TODO: inaccurate
        break;
      }
      case 0x24: {
        //BIT zpg
        // TODO
        break;
      }
      case 0x25: {
        //AND zpg
        and(load(next));
        wait(3);
        break;
      }
      case 0x26: {
        //ROL zpg
        rol(next);
        wait(5);
        break;
      }
      case 0x28: {
        //PLP impl
        sr = pop;
        break;
      }
      case 0x29: {
        //AND #
        and(next);
        wait(2);
        break;
      }
      case 0x2A: {
        //ROL A
        ubyte prev = a;
        a <<= 1;
        a |= SRFlag.C;
        setFlag(SRFlag.C, prev > a);
        flagsFromA();
        wait(2);
        break;
      }
      case 0x2C: {
        //BIT abs
        // TODO
        break;
      }
      case 0x2D: {
        //AND abs
        and(load(nextw));
        wait(4);
        break;
      }
      case 0x2E: {
        //ROL abs
        rol(nextw);
        wait(6);
        break;
      }
      case 0x30: {
        //BMI rel
        branchIf(getFlag(SRFlag.N), next);
        wait(2); // TODO: inaccurate
        break;
      }
      case 0x31: {
        //AND ind,Y
        and(load(load(next)+y));
        wait(5); // TODO inaccurate
        break;
      }
      case 0x35: {
        //AND zpg,X
        and(load(next+x));
        wait(3);
        break;
      }
      case 0x36: {
        //ROL zpg,X
        rol(next+x);
        wait(6);
        break;
      }
      case 0x38: {
        //SEC impl
        setFlag(SRFlag.C, true);
        wait(2);
        break;
      }
      case 0x39: {
        //AND abs,Y
        and(load(nextw+y));
        wait(4); // TODO: inaccurate
        break;
      }
      case 0x3D: {
        //AND abs,X
        and(load(nextw+x));
        wait(4); // TODO: inaccurate
        break;
      }
      case 0x3E: {
        //ROL abs,X
        rol(nextw+x);
        wait(6);
        break;
      }
      case 0x40: {
        //RTI impl
        sr = pop;
        setFlag(SRFlag.B, false);
        pc = popw;
        wait(6);
        break;
      }
      case 0x41: {
        //EOR X,ind
        eor(load(load(x+next)));
        wait(6);
        break;
      }
      case 0x45: {
        //EOR zpg
        eor(load(next));
        wait(3);
        break;
      }
      case 0x46: {
        //LSR zpg
        lsr(next);
        wait(5);
        break;
      }
      case 0x48: {
        //PHA impl
        push(a);
        wait(3);
        break;
      }
      case 0x49: {
        //EOR #
        eor(next);
        break;
      }
      case 0x4A: {
        //LSR A
        ubyte prev = a;
        ubyte v = prev >> 1;
        setFlag(SRFlag.C, prev > v);
        setFlag(SRFlag.Z, v == 0);
        a = v;
        break;
      }
      case 0x4C: {
        //JMP abs
        pc = nextw;
        wait(3);
        break;
      }
      case 0x4D: {
        //EOR abs
        eor(load(nextw));
        wait(4);
        break;
      }
      case 0x4E: {
        //LSR abs
        lsr(nextw);
        wait(4);
        break;
      }
      case 0x50: {
        //BVC rel
        branchIf(!getFlag(SRFlag.V), pc);
        wait(2); // TODO: inaccurate
        break;
      }
      case 0x51: {
        //EOR ind,Y
        eor(load(load(next)+y));
        wait(5); // TODO: inaccurate
        break;
      }
      case 0x55: {
        //EOR zpg,X
        eor(load(next+x));
        wait(4);
        break;
      }
      case 0x56: {
        //LSR zpg,X
        lsr(next+x);
        wait(6);
        break;
      }
      case 0x58: {
        //CLI impl
        clearFlag(SRFlag.I);
        wait(2);
        break;
      }
      case 0x59: {
        //EOR abs,Y
        eor(load(load(nextw+y)));
        wait(5); // TODO: inaccurate
        break;
      }
      case 0x5D: {
        //EOR abs,X
        eor(load(load(nextw+x)));
        wait(4); // TODO: inaccurate
        break;
      }
      case 0x5E: {
        //LSR abs,X
        lsr(nextw+x);
        wait(7);
        break;
      }
      case 0x60: {
        //RTS impl
        pc = popw;
        break;
      }
      case 0x61: {
        //ADC X,ind
        adc(load(load(next+x)));
        wait(5); // TODO: inaccurate
        break;
      }
      case 0x65: {
        //ADC zpg
        adc(load(next));
        wait(3);
        break;
      }
      case 0x66: {
        //ROR zpg
        ror(next);
        wait(5);
        break;
      }
      case 0x68: {
        //PLA impl
        a = pop;
        wait(4);
        break;
      }
      case 0x69: {
        //ADC #
        adc(next);
        wait(2);
        break;
      }
      case 0x6A: {
        //ROR A
        ubyte prev = a;
        ubyte v = prev >> 1;
        v |= getFlag(SRFlag.C) << 7;
        setFlag(SRFlag.C, prev & 0x01);
        setFlag(SRFlag.N, v > 127);
        setFlag(SRFlag.Z, v == 0);
        a = v;
        wait(2);
        break;
      }
      case 0x6C: {
        //JMP ind
        pc = load(load(nextw));
        wait(5);
        break;
      }
      case 0x6D: {
        //ADC abs
        adc(load(nextw));
        wait(4);
        break;
      }
      case 0x6E: {
        //ROR abs
        ror(nextw);
        wait(6);
        break;
      }
      case 0x70: {
        //BVS rel
        branchIf(getFlag(SRFlag.V), next);
        wait(2); // TODO: inaccurate
        break;
      }
      case 0x71: {
        //ADC ind,Y
        adc(load(load(next)+y));
        wait(5); // TODO: inaccurate
        break;
      }
      case 0x75: {
        //ADC zpg,X
        adc(load(next+x));
        wait(4);
        break;
      }
      case 0x76: {
        //ROR zpg,X
        ror(next+x);
        wait(6);
        break;
      }
      case 0x78: {
        //SEI impl
        setFlag(SRFlag.I);
        wait(2);
        break;
      }
      case 0x79: {
        //ADC abs,Y
        adc(load(nextw+y));
        wait(4); // TODO: inaccurate
        break;
      }
      case 0x7D: {
        //ADC abs,X
        adc(load(nextw+x));
        wait(4); // TODO: inaccurate
        break;
      }
      case 0x7E: {
        //ROR abs,X
        ror(nextw+x);
        wait(7);
        break;
      }
      case 0x81: {
        //STA X,ind
        store(load(next+x), a);
        wait(6);
        break;
      }
      case 0x84: {
        //STY zpg
        store(next, y);
        wait(3);
        break;
      }
      case 0x85: {
        //STA zpg
        store(next, a);
        wait(3);
        break;
      }
      case 0x86: {
        //STX zpg
        store(next, x);
        wait(3);
        break;
      }
      case 0x88: {
        //DEY impl
        y--;
        wait(2);
        break;
      }
      case 0x8A: {
        //TXA impl
        a = x;
        wait(2);
        break;
      }
      case 0x8C: {
        //STY abs
        store(nextw, y);
        wait(4);
        break;
      }
      case 0x8D: {
        //STA abs
        store(nextw, a);
        wait(4);
        break;
      }
      case 0x8E: {
        //STX abs
        store(nextw, x);
        wait(4);
        break;
      }
      case 0x90: {
        //BCC rel
        branchIf(!getFlag(SRFlag.C), next);
        wait(2); // TODO: inaccurate
        break;
      }
      case 0x91: {
        //STA ind,Y
        store(load(next)+y, a);
        wait(6);
        break;
      }
      case 0x94: {
        //STY zpg,X
        store(next+x, y);
        wait(4);
        break;
      }
      case 0x95: {
        //STA zpg,X
        store(next+x, a);
        wait(4);
        break;
      }
      case 0x96: {
        //STX zpg,Y
        store(next+y, x);
        wait(4);
        break;
      }
      case 0x98: {
        //TYA impl
        a = y;
        wait(2);
        break;
      }
      case 0x99: {
        //STA abs,Y
        store(nextw+y, a);
        wait(5);
        break;
      }
      case 0x9A: {
        //TXS impl
        sp = x;
        wait(2);
        break;
      }
      case 0x9D: {
        //STA abs,X
        store(nextw+x, a);
        wait(4);
        break;
      }
      case 0xA0: {
        //LDY #
        y = next;
        wait(2);
        break;
      }
      case 0xA1: {
        //LDA X,ind
        a = load(load(next+x));
        wait(6);
        break;
      }
      case 0xA2: {
        //LDX #
        x = next;
        wait(2);
        break;
      }
      case 0xA4: {
        //LDY zpg
        y = load(next);
        wait(3);
        break;
      }
      case 0xA5: {
        //LDA zpg
        a = load(next);
        wait(3);
        break;
      }
      case 0xA6: {
        //LDX zpg
        x = load(next);
        wait(3);
        break;
      }
      case 0xA8: {
        //TAY impl
        y = a;
        wait(2);
        break;
      }
      case 0xA9: {
        //LDA #
        a = next;
        wait(2);
        break;
      }
      case 0xAA: {
        //TAX impl
        x = a;
        wait(2);
        break;
      }
      case 0xAC: {
        //LDY abs
        y = load(nextw);
        wait(4);
        break;
      }
      case 0xAD: {
        //LDA abs
        a = load(nextw);
        wait(4);
        break;
      }
      case 0xAE: {
        //LDX abs
        x = load(nextw);
        wait(4);
        break;
      }
      case 0xB0: {
        //BCS rel
        branchIf(getFlag(SRFlag.C), next);
        wait(2); // TODO: inaccurate
        break;
      }
      case 0xB1: {
        //LDA ind,Y
        a = load(load(next)+y);
        wait(5); // TODO: inaccurate
        break;
      }
      case 0xB4: {
        //LDY zpg,X
        y = load(next+x);
        wait(4);
        break;
      }
      case 0xB5: {
        //LDA zpg,X
        a = load(next+x);
        wait(4);
        break;
      }
      case 0xB6: {
        //LDX zpg,Y
        x = load(next+y);
        wait(4);
        break;
      }
      case 0xB8: {
        //CLV impl
        clearFlag(SRFlag.V);
        wait(2);
        break;
      }
      case 0xB9: {
        //LDA abs,Y
        a = load(nextw+y);
        wait(4); // TODO: inaccurate
        break;
      }
      case 0xBA: {
        //TSX impl
        x = sp;
        wait(2);
        break;
      }
      case 0xBC: {
        //LDY abs,X
        y = load(nextw+x);
        wait(4); // TODO: inaccurate
        break;
      }
      case 0xBD: {
        //LDA abs,X
        a = load(nextw+x);
        wait(4); // TODO: inaccurate
        break;
      }
      case 0xBE: {
        //LDX abs,Y
        x = load(nextw+y);
        wait(4); // TODO: inaccurate
        break;
      }
      case 0xC0: {
        //CPY #
        compare(y, next);
        wait(2);
        break;
      }
      case 0xC1: {
        //CMP X,ind
        compare(a, load(load(next+x)));
        wait(6);
        break;
      }
      case 0xC4: {
        //CPY zpg
        compare(y, load(next));
        wait(3);
        break;
      }
      case 0xC5: {
        //CMP zpg
        compare(a, load(next));
        wait(3);
        break;
      }
      case 0xC6: {
        //DEC zpg
        ubyte l = next;
        store(next, load(next)-1);
        break;
      }
      case 0xC8: {
        //INY impl
        y++;
        wait(2);
        break;
      }
      case 0xC9: {
        //CMP #
        compare(a, next);
        wait(2);
        break;
      }
      case 0xCA: {
        //DEX impl
        x--;
        wait(2);
        break;
      }
      case 0xCC: {
        //CPY abs
        compare(y, load(nextw));
        wait(4);
        break;
      }
      case 0xCD: {
        //CMP abs
        compare(a, load(nextw));
        wait(4);
        break;
      }
      case 0xCE: {
        //DEC abs
        ushort l = nextw;
        store(l, load(l)-1);
        break;
      }
      case 0xD0: {
        //BNE rel
        branchIf(!getFlag(SRFlag.Z), next);
        break;
      }
      case 0xD1: {
        //CMP ind,Y
        compare(a, load(load(next)+y));
        break;
      }
      case 0xD5: {
        //CMP zpg,X
        compare(a, load(next+x));
        wait(4);
        break;
      }
      case 0xD6: {
        //DEC zpg,X
        ushort l = next+x;
        store(l, load(l)-1);
        wait(6);
        break;
      }
      case 0xD8: {
        //CLD impl
        clearFlag(SRFlag.D);
        wait(2);
        break;
      }
      case 0xD9: {
        //CMP abs,Y
        compare(a, load(nextw+y));
        wait(4); // TODO: inaccurate
        break;
      }
      case 0xDD: {
        //CMP abs,X
        compare(a, load(nextw+x));
        wait(4); // TODO: inaccurate
        break;
      }
      case 0xDE: {
        //DEC abs,X
        int l = nextw+x;
        store(l, load(l)-1);
        break;
      }
      case 0xE0: {
        //CPX #
        compare(x, next);
        wait(2);
        break;
      }
      case 0xE1: {
        //SBC X,ind
        sbc(load(load(next+x)));
        wait(6);
        break;
      }
      case 0xE4: {
        //CPX zpg
        compare(x, load(next));
        wait(3);
        break;
      }
      case 0xE5: {
        //SBC zpg
        sbc(load(next));
        wait(3);
        break;
      }
      case 0xE6: {
        //INC zpg
        ushort l = next;
        store(l, load(l)+1);
        wait(5);
        break;
      }
      case 0xE8: {
        //INX impl
        x++;
        wait(2);
        break;
      }
      case 0xE9: {
        //SBC #
        sbc(next);
        wait(2);
        break;
      }
      case 0xEA: {
        //NOP impl
        break;
      }
      case 0xEC: {
        //CPX abs
        compare(x, load(nextw));
        wait(4);
        break;
      }
      case 0xED: {
        //SBC abs
        sbc(load(nextw));
        wait(4);
        break;
      }
      case 0xEE: {
        //INC abs
        ushort l = nextw;
        store(l, load(l)+1);
        break;
      }
      case 0xF0: {
        //BEQ rel
        branchIf(getFlag(SRFlag.Z), next);
        break;
      }
      case 0xF1: {
        //SBC ind,Y
        sbc(load(load(next)+y));
        wait(5); // TODO: inaccurate
        break;
      }
      case 0xF5: {
        //SBC zpg,X
        sbc(load(next));
        wait(6);
        break;
      }
      case 0xF6: {
        //INC zpg,X
        ushort l = next+x;
        store(l, load(l+1));
        break;
      }
      case 0xF8: {
        //SED impl
        setFlag(SRFlag.D);
        wait(2);
        break;
      }
      case 0xF9: {
        //SBC abs,Y
        sbc(load(nextw+y));
        wait(4); // TODO: inaccurate
        break;
      }
      case 0xFD: {
        //SBC abs,X
        sbc(load(nextw+x));
        wait(4); // TODO: inaccurate
        break;
      }
      case 0xFE: {
        //INC abs,X
        int l = nextw+x;
        store(l, load(l)+1);
        wait(7);
        break;
      }
      default:
        throw new InvalidOpcodeException(cast(ushort)(pc-1), opcode);
    }
  }
}