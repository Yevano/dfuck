module cfg;

import brainfuck;

import std.algorithm.iteration;
import std.array;
import std.format;

abstract class CFG {
    CFG[] incoming;

    abstract CFG run(VM);
    abstract string compile();
}

class BasicBlockCFG : CFG {
    CFG outgoing;
    BrainfuckInstruction[] insts;

    this(BrainfuckInstruction[] insts) {
        this.insts = insts;
    }

    override CFG run(VM vm) {
        foreach(inst; insts) {
            inst.run(vm);
        }

        return outgoing;
    }

    override string compile() {
        char[] s;
        s ~= "    _%s:\n".format(cast(void*) this);

        foreach(inst; insts) {
            s ~= "    %s\n".format(inst.compile);
        }

        s ~= "    goto _%s;\n".format(cast(void*) outgoing);
        return cast(string) s;
    }
}

enum IfType { Loop, If, Move }

class IfCFG : CFG {
    IfType type;
    CFG outgoing_true;
    CFG outgoing_false;

    this(IfType type) {
        this.type = type;
    }

    override CFG run(VM vm) {
        if(vm.tape[vm.pointer] != 0) {
            return outgoing_true;
        } else {
            return outgoing_false;
        }
    }

    override string compile() {
        char[] s;
        s ~= "    _%s:\n".format(cast(void*) this);
        s ~= "    if(*p) goto _%s;\n".format(cast(void*) outgoing_true);
        s ~= "    goto _%s;\n".format(cast(void*) outgoing_false);
        return cast(string) s;
    }
}

class MoveCFG : CFG {
    CFG outgoing;
    MoveLoop inst;

    this(MoveLoop inst) {
        this.inst = inst;
    }

    override CFG run(VM vm) {
        inst.run(vm);
        return outgoing;
    }

    override string compile() {
        char[] s;
        s ~= "    _%s:\n".format(cast(void*) this);
        
        foreach(pointer, modify; inst.modifications) {
            s ~= "    *(p + %s) += %s * (*p);\n".format(pointer, modify);
        }

        s ~= "    *p = 0;\n";
        s ~= "    goto _%s;\n".format(cast(void*) outgoing);
        return cast(string) s;
    }
}

class IRParser {
    BrainfuckInstruction[][] insts;
    uint[] index;
    size_t depth;

    this(BrainfuckInstruction[] insts) {
        index ~= 0;
        this.insts ~= insts;
    }

    void seek(int d) {
        index[depth] += d;
    }

    void next() {
        seek(1);
    }

    void prev() {
        seek(-1);
    }

    void dive(BrainfuckInstruction[] i) {
        depth++;
        insts ~= i;
        index ~= 0;
    }

    void rise() {
        depth--;
        index.popBack;
        insts.popBack;
    }

    BrainfuckInstruction instruction() {
        auto i = index[depth];

        if(i >= 0 && i < insts[depth].length) {
            return insts[depth][index[depth]];
        }

        return null;
    }

    bool is_basic(BrainfuckInstruction inst) {
        return cast(Select) inst
            || cast(Modify) inst
            || cast(Clear) inst
            || cast(Input) inst
            || cast(Output) inst
            || cast(UnrolledLoop) inst;
    }

    CFG parse() {
        auto inst = instruction;

        if(inst !is null) {
            if(is_basic(inst)) {
                return parse_basic_block;
            } else {
                return parse_if;
            }
        }

        return null;
    }

    BasicBlockCFG parse_basic_block() {
        auto inst = instruction;
        BrainfuckInstruction[] insts;

        while(is_basic(inst)) {
            if(auto unroll = cast(UnrolledLoop) inst) {
                for(uint i = 0; i < unroll.count; i++) {
                    foreach(inner_inst; unroll.insts) {
                        insts ~= inner_inst;
                    }
                }
            } else {
               insts ~= inst;
            }

            next;
            inst = instruction;
        }

        auto block = new BasicBlockCFG(insts);
        block.outgoing = parse;
        if(block.outgoing !is null) block.outgoing.incoming ~= block;
        return block;
    }

    IfCFG parse_if() {
        auto inst = instruction;

        if(auto loop = cast(Loop) inst) {
            auto if_cfg = new IfCFG(IfType.Loop);
            next;
            if_cfg.outgoing_false = parse;
            if(if_cfg.outgoing_false !is null) if_cfg.outgoing_false.incoming ~= if_cfg;
            dive(loop.insts);
            if_cfg.outgoing_true = parse;
            if(if_cfg.outgoing_true !is null) if_cfg.outgoing_true.incoming ~= if_cfg;

            CFG current = if_cfg.outgoing_true;
            while(true) {
                if(auto basic_cfg = cast(BasicBlockCFG) current) {
                    current = basic_cfg.outgoing;
                    if(current is null) {
                        basic_cfg.outgoing = if_cfg;
                        if_cfg.incoming ~= basic_cfg;
                        break;
                    }
                } else if(auto inner_if_cfg = cast(IfCFG) current) {
                    current = inner_if_cfg.outgoing_false;
                    if(current is null) {
                        inner_if_cfg.outgoing_false = if_cfg;
                        if_cfg.incoming ~= inner_if_cfg;
                        break;
                    }
                } else if(auto move_cfg = cast(MoveCFG) current) {
                    current = move_cfg.outgoing;
                }
            }

            rise;
            return if_cfg;
        } else if(auto move = cast(MoveLoop) inst) {
            auto move_cfg = new MoveCFG(move);
            auto if_cfg = new IfCFG(IfType.Move);
            if_cfg.outgoing_true = move_cfg;
            move_cfg.incoming ~= if_cfg;
            next;

            auto next_instruction = parse;
            if_cfg.outgoing_false = next_instruction;
            if(next_instruction !is null) next_instruction.incoming ~= if_cfg;
            move_cfg.outgoing = if_cfg;
            if_cfg.incoming ~= move_cfg;
            return if_cfg;
        } else if(auto if_bf = cast(If) inst) {
            auto if_cfg = new IfCFG(IfType.If);
            dive(if_bf.insts);
            if_cfg.outgoing_true = parse;
            if(if_cfg !is null) if_cfg.outgoing_true.incoming ~= if_cfg;
            rise;

            next;
            auto next_instruction = parse;
            if_cfg.outgoing_false = next_instruction;
            if(next_instruction !is null) next_instruction.incoming ~= if_cfg.outgoing_false;

            CFG current = if_cfg.outgoing_true;
            while(true) {
                if(auto basic_cfg = cast(BasicBlockCFG) current) {
                    current = basic_cfg.outgoing;
                    if(current is null) {
                        basic_cfg.outgoing = if_cfg;
                        if_cfg.incoming ~= basic_cfg;
                        break;
                    }
                } else if(auto inner_if_cfg = cast(IfCFG) current) {
                    current = inner_if_cfg.outgoing_false;
                    if(current is null) {
                        inner_if_cfg.outgoing_false = if_cfg;
                        if_cfg.incoming ~= inner_if_cfg;
                        break;
                    }
                } else if(auto move_cfg = cast(MoveCFG) current) {
                    current = move_cfg.outgoing;
                }
            }

            return if_cfg;
        }

        return null;
    }
}