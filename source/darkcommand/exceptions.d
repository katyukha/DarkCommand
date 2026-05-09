module darkcommand.exceptions;

class DarkCommandException : Exception {
    this(string msg, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
    }
}

class DarkCommandExitException : DarkCommandException {
    int code;
    this(int code, string msg = null,
         string file = __FILE__, size_t line = __LINE__) {
        super(msg !is null ? msg : "", file, line);
        this.code = code;
    }
}
