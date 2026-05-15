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

// Thrown by the default onUnknownCommand implementation when a positional token
// is unrecognized as a subcommand and close matches exist.  Catch in onError to
// render suggestions differently from generic parse errors.
class UnknownCommandException : DarkCommandException {
    string   tok;         // the unrecognized token
    string[] suggestions; // candidates sorted by closeness (may be empty)

    this(string tok, string[] suggestions, string msg,
         string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
        this.tok         = tok;
        this.suggestions = suggestions;
    }
}

// Thrown when an unknown --option or -flag is encountered and close matches exist.
// `input` is the full CLI token as typed (e.g. "--vrebose", "-V").
// `suggestions` are formatted with dashes (e.g. ["--verbose"], ["-v"]).
class UnknownOptionException : DarkCommandException {
    string   input;       // the unrecognized token as typed
    string[] suggestions; // close matches with dashes included (may be empty)

    this(string input, string[] suggestions, string msg,
         string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
        this.input       = input;
        this.suggestions = suggestions;
    }
}
