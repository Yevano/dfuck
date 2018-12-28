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
        } else if(auto if_bf = cast(If) inst) {
            auto inner_counts = count_instructions(if_bf.insts);
            add_counts(counts, inner_counts);
        } else if(auto unrolled = cast(UnrolledLoop) inst) {
            auto inner_counts = count_instructions(unrolled.insts);
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
    return insts.map!(delegate BrainfuckInstruction(inst) {
        if(auto loop = cast(Loop) inst) {
            auto loop_insts = loop.insts;
            if(loop_insts.length == 1) {
                if(auto modify = cast(Modify) loop_insts[0]) {
                    if(modify.amt == -1) return new Clear;
                }
            }

            return new Loop(clear_opt(loop.insts));
        }

        return inst;
    }).array;
}

BrainfuckInstruction[] balanced_opt(BrainfuckInstruction[] insts) {
    return insts.map!(delegate BrainfuckInstruction(inst) {
        if(auto loop = cast(Loop) inst) {
            auto loop_insts = loop.insts;
            if(loop_insts.all!(loop_inst => (cast(Modify) loop_inst) || (cast(Select) loop_inst))) {
                if(loop_insts
                    .filter!(loop_inst => cast(Select) loop_inst)
                    .map!(loop_inst => (cast(Select) loop_inst).amt)
                    .sum == 0) {
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
    }).array;
}

BrainfuckInstruction[] if_opt(BrainfuckInstruction[] insts) {
    return insts.map!((inst) {
        if(auto loop = cast(Loop) inst) {
            int pointer;
            ubyte[int] tape;

            foreach(ref loop_inst; loop.insts) {
                if(auto modify = cast(Modify) loop_inst) {
                    if(pointer in tape)
                        tape[pointer] += modify.amt;
                } else if(auto select = cast(Select) loop_inst) {
                    pointer += select.amt;                    
                } else if(cast(Clear) loop_inst) {
                    tape[pointer] = 0;
                } else if(cast(Input) loop_inst) {
                    tape.remove(pointer);
                } else if(cast(Loop) loop_inst || cast(MoveLoop) loop_inst) {
                    pointer = 0;
                    tape.clear;
                    tape[0] = 0;

                    if(auto inner_loop = cast(Loop) loop_inst) {
                        loop_inst = new Loop(if_opt(inner_loop.insts));
                    }
                }
            }

            if(pointer in tape && tape[pointer] == 0) {
                return new If(loop.insts);
            }

            return inst;
        } else {
            return inst;
        }
    }).array;
}

BrainfuckInstruction[] unroll_opt(BrainfuckInstruction[] insts, bool program_body) {
    int pointer;
    ubyte[int] tape;
    
    if(program_body) {
        for(uint i = 0; i < 30000; i++) {
            tape[i] = 0;
        }
    }

    foreach(ref inst; insts) {
        if(auto modify = cast(Modify) inst) {
            if(pointer in tape)
                tape[pointer] += modify.amt;
        } else if(auto select = cast(Select) inst) {
            pointer += select.amt;
        } else if(cast(Clear) inst) {
            tape[pointer] = 0;
        } else if(cast(Input) inst) {
            tape.remove(pointer);
        } else if(cast(Loop) inst || cast(MoveLoop) inst) {
            if(auto loop = cast(Loop) inst) {
                if(pointer in tape) {
                    auto count = tape[pointer];
                    int inner_pointer;
                    int[int] inner_tape;

                    foreach(inner_inst; loop.insts) {
                        if(auto modify = cast(Modify) inner_inst) {
                            inner_tape[inner_pointer] += modify.amt;
                        } else if(auto select = cast(Select) inner_inst) {
                            inner_pointer += select.amt;                    
                        } else if(cast(Clear) inner_inst) {
                            inner_tape[inner_pointer] = 0;
                        } else if(cast(Input) inner_inst) {
                            inner_tape.remove(inner_pointer);
                        } else if(cast(Loop) inner_inst || cast(MoveLoop) inner_inst) {
                            inner_pointer = 0;
                            inner_tape.clear;
                            inner_tape[0] = 0;
                            
                            if(auto inner_loop = cast(Loop) inner_inst) {
                                inner_loop.insts = unroll_opt(inner_loop.insts, false);
                            }
                        }
                    }

                    if(0 in inner_tape && inner_tape[0] == -1 && inner_pointer == 0) {
                        inst = new UnrolledLoop(count, loop.insts);
                    }
                }
            }
            
            pointer = 0;
            tape.clear;
            tape[0] = 0;
        }
    }

    return insts;
}