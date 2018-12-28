module brainfuck;

import std.conv;
import std.array;
import std.stdio;
import std.format;

class VM {
    uint pointer = 0;
    ubyte[] tape;

    this() {
        tape.length = 30000;
    }
}

class BrainfuckInstruction {
    abstract void run(VM);
    abstract string compile(uint);
    abstract string to_string(uint);

    string compile() {
        return compile(0);
    }

    string to_string() {
        return to_string(0);
    }
}

class Modify : BrainfuckInstruction {
    int amt;

    this(int amt) {
        this.amt = amt;
    }

    override void run(VM vm) {
        vm.tape[vm.pointer] += amt;
    }

    override string compile(uint depth) {
        return "%s*p += %s;".format("    ".replicate(depth), amt);
    }

    override string to_string(uint depth) {
        return "%sModify(%s)".format("    ".replicate(depth), amt.to!string);
    }
}

class Select : BrainfuckInstruction {
    int amt;

    this(int amt) {
        this.amt = amt;
    }

    override void run(VM vm) {
        vm.pointer += amt;
    }

    override string compile(uint depth) {
        return "%sp += %s;".format("    ".replicate(depth), amt);
    }

    override string to_string(uint depth) {
        return "%sSelect(%s)".format("    ".replicate(depth), amt.to!string);
    }
}

class Loop : BrainfuckInstruction {
    BrainfuckInstruction[] insts;

    this(BrainfuckInstruction[] insts) {
        this.insts = insts;
    }

    override void run(VM vm) {
        while(vm.tape[vm.pointer] != 0) {
            foreach(inst; insts) {
                inst.run(vm);
            }
        }
    }

    override string compile(uint depth) {
        char[] s;
        s ~= "%swhile(*p) {\n".format("    ".replicate(depth));

        foreach(inst; insts) {
            s ~= "%s\n".format(inst.compile(depth + 1));
        }

        s ~= "%s}".format("    ".replicate(depth));
        return cast(string) s;
    }

    override string to_string(uint depth) {
        char[] s;
        s ~= "%sLoop {\n".format("    ".replicate(depth));

        foreach(inst; insts) {
            s ~= "%s\n".format(inst.to_string(depth + 1));
        }

        s ~= "%s}".format("    ".replicate(depth));
        return cast(string) s;
    }
}

class Input : BrainfuckInstruction {
    override void run(VM vm) {
        char c;
        readf("%s", &c);
        vm.tape[vm.pointer] = c;
    }

    override string compile(uint depth) {
        return "%s*p = getchar();".format("    ".replicate(depth));
    }

    override string to_string(uint depth) {
        return "%sInput".format("    ".replicate(depth));
    }
}

class Output : BrainfuckInstruction {
    override void run(VM vm) {
        write(cast(char) vm.tape[vm.pointer]);
        stdout.flush;
    }

    override string compile(uint depth) {
        return "%sputchar(*p); fflush(stdout);".format("    ".replicate(depth));
    }

    override string to_string(uint depth) {
        return "%sOutput".format("    ".replicate(depth));
    }
}

class Clear : BrainfuckInstruction {
    override void run(VM vm) {
        vm.tape[vm.pointer] = 0;
    }

    override string compile(uint depth) {
        return "%s*p = 0;".format("    ".replicate(depth));
    }

    override string to_string(uint depth) {
        return "%sClear".format("    ".replicate(depth));
    }
}

class MoveLoop : BrainfuckInstruction {
    int[int] modifications;

    this(int[int] modifications) {
        this.modifications = modifications;
    }

    override void run(VM vm) {
        auto src = vm.tape[vm.pointer];
        if(src == 0) return;

        foreach(pointer, modify; modifications) {
            vm.tape[vm.pointer + pointer] += modify * src;
        }

        vm.tape[vm.pointer] = 0;
    }

    override string compile(uint depth) {
        char[] s;
        s ~= "%sif(*p) {\n".format("    ".replicate(depth));

        foreach(pointer, modify; modifications) {
            s ~= "%s*(p + %s) += %s * (*p);\n".format("    ".replicate(depth + 1), pointer, modify);
        }

        s ~= "%s*p = 0;\n".format("    ".replicate(depth + 1));
        s ~= "%s}".format("    ".replicate(depth));
        return cast(string) s;
    }

    override string to_string(uint depth) {
        return "%sMoveLoop %s".format("    ".replicate(depth), modifications.to!string);
    }
}

class If : BrainfuckInstruction {
    BrainfuckInstruction[] insts;

    this(BrainfuckInstruction[] insts) {
        this.insts = insts;
    }

    override void run(VM vm) {
        if(vm.tape[vm.pointer] != 0) {
            foreach(inst; insts) {
                inst.run(vm);
            }
        }
    }

    override string compile(uint depth) {
        char[] s;
        s ~= "%sif(*p) {\n".format("    ".replicate(depth));

        foreach(inst; insts) {
            s ~= "%s\n".format(inst.compile(depth + 1));
        }

        s ~= "%s}".format("    ".replicate(depth));
        return cast(string) s;
    }

    override string to_string(uint depth) {
        char[] s;
        s ~= "%sIf {\n".format("    ".replicate(depth));

        foreach(inst; insts) {
            s ~= "%s\n".format(inst.to_string(depth + 1));
        }

        s ~= "%s}".format("    ".replicate(depth));
        return cast(string) s;
    }
}

class UnrolledLoop : BrainfuckInstruction {
    uint count;
    BrainfuckInstruction[] insts;

    this(uint count, BrainfuckInstruction[] insts) {
        this.count = count;
        this.insts = insts;
    }

    override void run(VM vm) {
        for(uint i = 0; i < count; i++) {
            foreach(inst; insts) {
                inst.run(vm);
            }
        }
    }

    override string compile(uint depth) {
        char[] s;

        for(uint i = 0; i < count; i++) {
            foreach(inst; insts) {
                s ~= "%s\n".format(inst.compile(depth));
            }
        }

        return cast(string) s;
    }

    override string to_string(uint depth) {
        char[] s;
        s ~= "%sUnrolledLoop(%s) {\n".format("    ".replicate(depth), count);

        foreach(inst; insts) {
            s ~= "%s\n".format(inst.to_string(depth + 1));
        }

        s ~= "%s}".format("    ".replicate(depth));
        return cast(string) s;
    }
}