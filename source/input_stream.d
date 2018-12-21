module input_stream;

class InputStream(T) {
    size_t pos = 0;
    T[] range;

    this(T[] range) {
        this.range = range;
    }

    T read() {
        if(pos >= range.length) return 0;
        return range[pos++];
    }

    void seek(int amt) {
        pos += amt;
    }
}

auto take_one(R)(R range) {
    return range.take(1).array[0];
}