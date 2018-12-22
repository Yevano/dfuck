module cfg;

import brainfuck;

import std.algorithm.iteration;
import std.array;

abstract class CFG { }

class BasicBlockCFG : CFG {
    CFG outgoing;
    BrainfuckInstruction[] insts;

    this(BrainfuckInstruction[] insts) {
        this.insts = insts;
    }
}

class IfCFG : CFG {
    CFG outgoing_true;
    CFG outgoing_false;
}

class MoveCFG : CFG {
    CFG outgoing;
    MoveLoop inst;

    this(MoveLoop inst) {
        this.inst = inst;
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

    void seek(uint d) {
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
            || cast(Output) inst;
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
            insts ~= inst;
            next;
            inst = instruction;
        }

        auto block = new BasicBlockCFG(insts);
        block.outgoing = parse;
        return block;
    }

    IfCFG parse_if() {
        auto inst = instruction;

        if(auto loop = cast(Loop) inst) {
            auto if_cfg = new IfCFG;
            next;
            if_cfg.outgoing_false = parse;
            dive(loop.insts);
            if_cfg.outgoing_true = parse;

            CFG current = if_cfg.outgoing_true;
            while(true) {
                if(auto basic_cfg = cast(BasicBlockCFG) current) {
                    current = basic_cfg.outgoing;
                    if(current is null) {
                        basic_cfg.outgoing = if_cfg;
                        break;
                    }
                } else if(auto inner_if_cfg = cast(IfCFG) current) {
                    current = inner_if_cfg.outgoing_false;
                    if(current is null) {
                        inner_if_cfg.outgoing_false = if_cfg;
                        break;
                    }
                } else if(auto move_cfg = cast(MoveCFG) current) {
                    current = move_cfg.outgoing;
                    if(current is null) {
                        move_cfg.outgoing = if_cfg;
                        break;
                    }
                }
            }

            rise;
            return if_cfg;
        } else if(auto move = cast(MoveLoop) inst) {
            auto move_cfg = new MoveCFG(move);
            auto if_cfg = new IfCFG;
            if_cfg.outgoing_true = move_cfg;
            next;

            auto next_instruction = parse;
            if_cfg.outgoing_false = next_instruction;
            move_cfg.outgoing = next_instruction;
            return if_cfg;
        }

        return null;
    }
}