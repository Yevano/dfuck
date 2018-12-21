module optimize;

import brainfuck;

import std.algorithm.iteration;
import std.algorithm.searching;
import std.array;
import std.range;
import std.conv;

alias Counts = size_t[string];

Counts count_instructions(BrainfuckInstruction[] insts) {
    Counts counts;

    foreach(inst; insts) {
        counts[typeid(inst).toString]++;
        if(auto loop = cast(Loop) inst) {
            auto inner_counts = count_instructions(loop.insts);
            add_counts(counts, inner_counts);
        }
    }

    return counts;
}

void add_counts(Counts dst, Counts src) {
    foreach(k, v; src) {
        dst[k] += v;
    }
}

BrainfuckInstruction[] clear_opt(BrainfuckInstruction[] insts) {
    return insts.map!(inst => delegate BrainfuckInstruction() {
        if(auto loop = cast(Loop) inst) {
            auto loop_insts = loop.insts;
            if(loop_insts.length == 1) {
                if(auto modify = cast(Modify) loop_insts[0]) {
                    if(modify.amt == -1) return new Clear();
                }
            }

            return new Loop(clear_opt(loop.insts));
        }

        return inst;
    }()).array;
}

BrainfuckInstruction[] balanced_opt(BrainfuckInstruction[] insts) {
    return insts.map!(inst => delegate BrainfuckInstruction() {
        if(auto loop = cast(Loop) inst) {
            auto loop_insts = loop.insts;
            if(loop_insts.all!(loop_inst => (cast(Modify) loop_inst) || (cast(Select) loop_inst))) {
                if(loop_insts
                    .filter!(loop_inst => cast(Select) loop_inst)
                    .map!(loop_inst => (cast(Select) loop_inst).amt)
                    .sum() == 0) {
                    int[int] ms;
                    int pointer = 0;
                    
                    foreach(loop_inst; loop_insts) {
                        if(auto modify = cast(Modify) loop_inst) {
                            ms[pointer] += modify.amt;
                        } else if(auto select = cast(Select) loop_inst) {
                            pointer += select.amt;
                        }
                    }

                    if(ms[0] == -1) {
                        ms.remove(0);
                        return new MoveLoop(ms);
                    }
                }
            }

            return new Loop(balanced_opt(loop.insts));
        }

        return inst;
    }()).array;
}