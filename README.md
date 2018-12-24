# dfuck
An optimized brainfuck interpreter and compiler.

## Usage

`dfuck [options] <source>`

### Argument

The brainfuck file to be run.

### Options

Flag | Abbreviation | Description
---- | ------------ | -----------
-only-compile | -oc | Compile a brainfuck file and generate an executable.
-compile-run | -cr | Compile and run a brainfuck file.
-interpret | -i | Interpret a brainfuck file.
-intermediate <file> | -ir | Specifies a file to ouput IR code to.
-graph <file> | -g | Specifies a file to output CFG DOT to.
-compiler <which> | -c | The compiler to use. Must be one of: gcc. Defaults to gcc.
