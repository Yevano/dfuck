module parse;

import brainfuck;
import input_stream;

BrainfuckInstruction[] parse_brainfuck(string code) {
    code ~= "\u0000";
    return parse_block(new InputStream!(immutable char)(code), '\u0000');
}

BrainfuckInstruction[] parse_block(InputStream!(immutable char) stream, char delimiter) {
    BrainfuckInstruction[] insts;
    char first_char = stream.read;

    while(first_char != delimiter) {
        switch(first_char) {
            case '+':
            case '-':
                auto amt = first_char == '+' ? 1 : -1;

                auto c = cast(char) stream.read;
                while(c == '+' || c == '-') {
                    amt += c == '+' ? 1 : -1;
                    c = stream.read;
                }

                insts ~= new Modify(amt);
                stream.seek(-1);
                break;
            case '>':
            case '<':
                auto amt = first_char == '>' ? 1 : -1;

                auto c = cast(char) stream.read;
                while(c == '>' || c == '<') {
                    amt += c == '>' ? 1 : -1;
                    c = stream.read;
                }

                insts ~= new Select(amt);
                stream.seek(-1);
                break;
            case '[':
                insts ~= new Loop(parse_block(stream, ']'));
                break;
            case ',':
                insts ~= new Input;
                break;
            case '.':
                insts ~= new Output;
                break;
            default:
                break;
        }

        first_char = stream.read;
    }
    return insts;
}