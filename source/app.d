module dfuck;

import optimize;
import brainfuck;
import input_stream;
import parse;
import cfg;

import darg;

import std.stdio;
import core.stdc.stdlib;
import std.file;
import std.range;
import std.conv;
import std.traits;
import std.regex;
import std.string;
import std.conv;
import std.process;
import std.array;
import std.algorithm.iteration;

struct Options {
    @Option("help", "h")
    @Help("Prints this help.")
    OptionFlag help;

    @Option("only-compile", "oc")
    @Help("Compile a brainfuck file and generate an executable.")
    OptionFlag only_compile;

    @Option("compile-run", "cr")
    @Help("Compile and run a brainfuck file.")
    OptionFlag compile_run;
    
    @Option("interpret", "i")
    @Help("Interpret a brainfuck file.")
    OptionFlag interpret;

    @Option("intermediate", "ir")
    @Help("Specifies a file to ouput IR code to.")
    string intermediate;

    @Option("compiler", "c")
    @Help("The compiler to use. Must be one of: gcc. Defaults to gcc.")
    string compiler = "gcc";

    @Option("graph", "g")
    @Help("Specifies a file to output the CFG to.")
    string graph;

    @Argument("source")
    @Help("The brainfuck file to be run.")
    string source;
}

int main(string[] args) {
    immutable help = helpString!Options;
    immutable usage = usageString!Options("dfuck");
    Options options;

    try {
        options = parseArgs!Options(args[1 .. $]);
    } catch (ArgParseError e) {
        writeln(e.msg);
        writeln(usage);
        return 1;
    } catch (ArgParseHelp e) {
        writeln(usage);
        write(help);
        return 0;
    }

    auto code = readText(options.source);

    std.stdio.write("Sanitizing code... ");
    stdout.flush();
    auto re = regex(r"[^(\[|\]|\+|\-|>|<|\.|,)]", "g");
    auto sanitized_code = replaceAll(code, re, "");
    writeln("done\n");

    BrainfuckInstruction[] insts;

    writeln("Parsing instructions...");
    stdout.flush();
    insts = parse_brainfuck(sanitized_code);
    auto counts0 = count_instructions(insts);
    write_inst_count(counts0);
    writeln();

    writeln("Clear optimization...");
    stdout.flush();
    insts = clear_opt(insts);
    Counts counts1 = count_instructions(insts);
    write_inst_count(counts1);
    writefln("Removed %s instructions.\n", get_total_insts(counts0) - get_total_insts(counts1));
    
    writeln("UnrolledLoop optimization...");
    stdout.flush();
    insts = unroll_opt(insts, true);
    Counts counts2 = count_instructions(insts);
    write_inst_count(counts2);
    writeln;

    writeln("If optimization...");
    stdout.flush();
    insts = if_opt(insts);
    Counts counts3 = count_instructions(insts);
    write_inst_count(counts3);
    writeln;

    writeln("BalancedLoop optimization...");
    stdout.flush();
    insts = balanced_opt(insts);
    Counts counts4 = count_instructions(insts);
    write_inst_count(counts4);
    writefln("Removed %s instructions.\n\n", get_total_insts(counts3) - get_total_insts(counts4));
    
    stdout.flush();

    auto parser = new IRParser(insts);
    auto cfg = parser.parse;

    char[] file_out;

    if(options.intermediate != "") {
        foreach(inst; insts) {
            file_out ~= inst.to_string() ~ "\n";
        }
        std.file.write(options.intermediate, file_out);
    }

    if(options.graph != "") {
        file_out.length = 0;
        file_out ~= "digraph {\n";

        bool[CFG] cfgs;
        collect_nodes(cfg, cfgs);

        file_out ~= "    _%s [color=red];\n".format(cast(void*) cfg);
        foreach(cfg, _; cfgs) {
            if(auto basic_cfg = cast(BasicBlockCFG) cfg) {
                char[] label = cast(char[]) "%s\\n".format(typeid(cfg).toString);
                
                foreach(inst; basic_cfg.insts) {
                    label ~= "%s\\n".format(inst.to_string);
                }

                file_out ~= "    _%s [label=\"%s\"];\n".format(cast(void*) cfg, cast(string) label);
            } else if(auto move_cfg = cast(MoveCFG) cfg) {
                char[] label = cast(char[]) "%s\\n%s".format(typeid(cfg).toString, move_cfg.inst.to_string(0));
                file_out ~= "    _%s [label=\"%s\"];\n".format(cast(void*) cfg, cast(string) label);
            } else if(auto if_cfg = cast(IfCFG) cfg) {
                file_out ~= "    _%s [label=\"%s\\n%s\"];\n".format(cast(void*) cfg, typeid(cfg).toString, if_cfg.type);
            }
        }
        
        foreach(cfg, _; cfgs) {
            if(auto basic_cfg = cast(BasicBlockCFG) cfg) {
                auto basic_ptr = cast(void*) basic_cfg;
                auto next_ptr = cast(void*) basic_cfg.outgoing;
                file_out ~= "    _%s -> _%s [splines=ortho];\n".format(basic_ptr, next_ptr);
            } else if(auto if_cfg = cast(IfCFG) cfg) {
                auto if_ptr = cast(void*) if_cfg;
                auto true_ptr = cast(void*) if_cfg.outgoing_true;
                auto false_ptr = cast(void*) if_cfg.outgoing_false;
                file_out ~= "    _%s -> _%s [label=\"T\"] [splines=ortho];\n".format(if_ptr, true_ptr);
                file_out ~= "    _%s -> _%s [label=\"F\"] [splines=ortho];\n".format(if_ptr, false_ptr);
            } else if(auto move_cfg = cast(MoveCFG) cfg) {
                auto move_ptr = cast(void*) move_cfg;
                auto next_ptr = cast(void*) move_cfg.outgoing;
                file_out ~= "    _%s -> _%s [splines=ortho];\n".format(move_ptr, next_ptr);
            }
        }

        file_out ~= "}";
        std.file.write(options.graph, file_out);
    }

    if(options.compile_run == OptionFlag.yes || options.only_compile == OptionFlag.yes) {
        file_out.length = 0;
        file_out ~=
"#include <stdio.h>
char t[30000];
char* p = t;
int main(int argc, const char* argv[]) {\n";
        
        file_out ~= "goto _%s;\n".format(cast(void*) cfg);

        bool[CFG] cfgs;
        collect_nodes(cfg, cfgs);

        foreach(cfg, _; cfgs) {
            file_out ~= "%s\n".format(cfg.compile);
        }
        
        file_out ~= "    _null:\n";
        file_out ~= "    return 0;\n";
        file_out ~= "}";
        std.file.write("dfuck_temp.c", file_out);

        switch(options.compiler) {
            case "gcc":
                auto com = "gcc -O3 dfuck_temp.c -o dfuck_temp.exe";
                writefln("Running %s", com);
                stdout.flush();
                executeShell(com);
                break;
            default:
                writefln("Compiler %s is not supported.", options.compiler);
                return -1;
        }

        if(options.compile_run == OptionFlag.yes) {
            auto pid = spawnProcess("./dfuck_temp.exe");
            wait(pid);
            executeShell("rm dfuck_temp.c && rm dfuck_temp.exe");
        }
    }

    if(options.interpret == OptionFlag.yes) {
        auto vm = new VM();

        /*while(cfg !is null) {
            cfg = cfg.run(vm);
        }*/

        foreach(inst; insts) {
            inst.run(vm);
        }
    }

    return 0;
}

void write_inst_count(Counts counts) {
    foreach(k, v; counts) {
        writefln("%s: %s", k, v);
    }
}

uint get_total_insts(Counts counts) {
    return counts.byValue.sum();
}

void collect_nodes(CFG cfg, ref bool[CFG] collected) {
    if(cfg in collected || cfg is null) return;
    collected[cfg] = true;

    if(auto basic_cfg = cast(BasicBlockCFG) cfg) {
        collect_nodes(basic_cfg.outgoing, collected);
    } else if(auto if_cfg = cast(IfCFG) cfg) {
        collect_nodes(if_cfg.outgoing_true, collected);
        collect_nodes(if_cfg.outgoing_false, collected);
    } else if(auto move_cfg = cast(MoveCFG) cfg) {
        collect_nodes(move_cfg.outgoing, collected);
    }
}