module dfuck;

import optimize;
import brainfuck;
import input_stream;
import parse;

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
    
    writeln("BalancedLoop optimization...");
    stdout.flush();
    insts = balanced_opt(insts);
    Counts counts2 = count_instructions(insts);
    write_inst_count(counts1);
    writefln("Removed %s instructions.\n", get_total_insts(counts1) - get_total_insts(counts2));
    
    stdout.flush();

    char[] file_out;

    if(options.intermediate != "") {
        foreach(inst; insts) {
            file_out ~= inst.to_string() ~ "\n";
        }
        std.file.write(options.intermediate, file_out);
    }

    if(options.compile_run == OptionFlag.yes || options.only_compile == OptionFlag.yes) {
        file_out.length = 0;
        file_out ~=
"#include <stdio.h>
char t[30000];
char* p = t;
int main(int argc, const char* argv[]) {\n";
        
        foreach(inst; insts) {
            file_out ~= inst.compile(1) ~ "\n";
        }
        
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