module darkcommand.validators;

interface IValidator {
    // Returns null if valid, or an error message.
    string validate(string value);
}

class EnumValidator : IValidator {
    private string[] _allowed;

    this(string[] allowed) {
        _allowed = allowed;
    }

    string validate(string value) {
        import std.algorithm : canFind;
        import std.array : join;
        if (!_allowed.canFind(value))
            return "must be one of: " ~ _allowed.join(", ");
        return null;
    }
}

class DelegateValidator(T) : IValidator {
    private bool delegate(T) _pred;
    private string _msg;

    this(bool delegate(T) pred, string msg) {
        _pred = pred;
        _msg  = msg;
    }

    string validate(string raw) {
        import std.conv : to, ConvException;
        try {
            if (!_pred(raw.to!T))
                return _msg;
        } catch (ConvException) {
            // conversion errors are handled by the parser; skip here
        }
        return null;
    }
}

class FileSystemValidator : IValidator {
    enum Mode { file, directory }

    private Mode _mode;
    private bool _validateExistence;

    this(Mode mode, bool validateExistence = true) {
        _mode             = mode;
        _validateExistence = validateExistence;
    }

    string validate(string path) {
        if (!_validateExistence)
            return null;
        import std.file : exists, isFile, isDir, FileException;
        try {
            if (!exists(path))
                return "path does not exist: " ~ path;
            final switch (_mode) {
                case Mode.file:
                    return isFile(path) ? null : "not a file: " ~ path;
                case Mode.directory:
                    return isDir(path) ? null : "not a directory: " ~ path;
            }
        } catch (FileException e) {
            return "cannot access path: " ~ e.msg;
        }
    }
}

unittest {
    auto ev = new EnumValidator(["a", "b", "c"]);
    assert(ev.validate("a") is null);
    assert(ev.validate("d") !is null);

    auto dv = new DelegateValidator!int(v => v > 0, "must be positive");
    assert(dv.validate("1") is null);
    assert(dv.validate("0") !is null);
    assert(dv.validate("notanint") is null); // conv error skipped

    auto fv = new FileSystemValidator(FileSystemValidator.Mode.file, false);
    assert(fv.validate("/nonexistent/path") is null); // no existence check
}
