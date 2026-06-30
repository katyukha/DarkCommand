module darkcommand.entry;

private import darkcommand.validators;

// ── Field-kind helpers ─────────────────────────────────────────────────────────

template isNullable(T) {
    import std.typecons : Nullable;
    static if (is(T == Nullable!U, U))
        enum isNullable = true;
    else
        enum isNullable = false;
}

template NullableTarget(T) {
    import std.typecons : Nullable;
    static if (is(T == Nullable!U, U))
        alias NullableTarget = U;
    else
        static assert(false, T.stringof ~ " is not Nullable!T");
}

// True for dynamic arrays that are not string (string is treated as a scalar).
template isRepeatingField(T) {
    import std.traits : isDynamicArray;
    static if (isDynamicArray!T && !is(T == string))
        enum isRepeatingField = true;
    else
        enum isRepeatingField = false;
}

// ── EntrySpec ─────────────────────────────────────────────────────────────────

class EntrySpec {
    enum Kind     { flag, option, argument }
    enum FieldKind { boolFlag, intFlag, required, optional, repeating }

    Kind      kind;
    FieldKind fieldKind;
    string    shortName;   // empty if none
    string    longName;    // empty if none; unused for arguments
    string    displayName; // for positional arguments (shown in usage)
    string    desc;
    bool      provided;
    bool      hasDefault;

    IValidator[] validators;

    // Completion hints — set by EntryBuilder fluent methods.
    enum CompletionHint { none, file, directory, path }
    CompletionHint completionHint;
    string[] completionValues; // populated by acceptsValues()

    bool negatable;  // --no-<longname> sets bool flag to false
    bool oneOrMore;  // repeating field marked .required(): at least one value required
    string completionCommand; // shell command whose stdout provides completion words

    // Write delegates — set at registration time in Command.addFlag/addOption/addArgument.
    void delegate(string) writeValue;  // option / argument: raw string → field
    void delegate()       writeDefault;
    void delegate()       writeReset;  // resets field to zero/init before each parse
    void delegate()       setTrue;     // bool flag
    void delegate()       setFalse;    // bool flag (negatable form --no-X)
    void delegate()       increment;   // int flag

    string cliName() const {
        if (longName.length)  return "--" ~ longName;
        if (shortName.length) return "-"  ~ shortName;
        return displayName;
    }

    // Required = "parse error if absent", mirroring what the parser enforces.
    // A repeating field (T[]) is zero-or-more by default; calling .required()
    // sets `oneOrMore`, making it one-or-more (parse error if absent).
    bool isRequired() const {
        if (fieldKind == FieldKind.repeating) return oneOrMore;
        if (hasDefault) return false;
        return fieldKind == FieldKind.required;
    }
    bool isBoolFlag()   const { return fieldKind == FieldKind.boolFlag; }
    bool isIntFlag()    const { return fieldKind == FieldKind.intFlag; }
    bool isRepeating()  const { return fieldKind == FieldKind.repeating; }
    bool isFlag()       const { return kind == Kind.flag; }
    bool isArgument()   const { return kind == Kind.argument; }

    // Runs all validators; throws DarkCommandException on first failure.
    void runValidators(string raw) {
        import darkcommand.exceptions : DarkCommandException;
        foreach (v; validators) {
            string err = v.validate(raw);
            if (err !is null)
                throw new DarkCommandException(cliName ~ ": " ~ err);
        }
    }
}

// ── EntryBuilder ──────────────────────────────────────────────────────────────

class EntryBuilder(T) {
    private EntrySpec _spec;
    private T*        _ptr;
    private Object    _cmd;  // Command (as Object to avoid module-level circular import)

    this(EntrySpec spec, T* ptr, Object cmd = null) {
        _spec = spec;
        _ptr  = ptr;
        _cmd  = cmd;
    }

    // defaultValue is only available for non-Nullable fields.
    // For Nullable!T, calling .defaultValue() is a compile error ("no such member").
    static if (!isNullable!T) {
        EntryBuilder!T defaultValue(T val) {
            static if (isRepeatingField!T) {
                import darkcommand.exceptions : DarkCommandException;
                if (_spec.oneOrMore)
                    throw new DarkCommandException(
                        "defaultValue() conflicts with required() — a required " ~
                        "(one-or-more) field cannot also have a default");
            }
            auto ptr = _ptr;
            _spec.writeDefault = () { *ptr = val; };
            _spec.hasDefault   = true;
            return this;
        }
    }

    EntryBuilder!T acceptsValues(string[] vals) {
        _spec.validators ~= new EnumValidator(vals);
        _spec.completionValues = vals;
        return this;
    }

    static if (isRepeatingField!T) {
        import std.range : ElementType;
        EntryBuilder!T validateEachWith(bool delegate(ElementType!T) pred, string msg) {
            _spec.validators ~= new DelegateValidator!(ElementType!T)(pred, msg);
            return this;
        }

        // Mark a repeating field (option or argument) as one-or-more: at least
        // one value must be supplied, otherwise the parser reports it missing.
        // Without this, a repeating field is zero-or-more (empty if absent).
        EntryBuilder!T required() {
            import darkcommand.exceptions : DarkCommandException;
            if (_spec.hasDefault)
                throw new DarkCommandException(
                    "required() conflicts with defaultValue() — a required " ~
                    "(one-or-more) field cannot also have a default");
            _spec.oneOrMore = true;
            return this;
        }
    } else static if (isNullable!T) {
        // Predicate receives the inner type, matching what the parser converts to.
        EntryBuilder!T validateEachWith(bool delegate(NullableTarget!T) pred, string msg) {
            _spec.validators ~= new DelegateValidator!(NullableTarget!T)(pred, msg);
            return this;
        }
    } else {
        EntryBuilder!T validateEachWith(bool delegate(T) pred, string msg) {
            _spec.validators ~= new DelegateValidator!T(pred, msg);
            return this;
        }
    }

    EntryBuilder!T acceptsFiles() {
        _spec.validators ~= new FileSystemValidator(FileSystemValidator.Mode.file, true);
        _spec.completionHint = EntrySpec.CompletionHint.file;
        return this;
    }

    EntryBuilder!T acceptsDirectories() {
        _spec.validators ~= new FileSystemValidator(FileSystemValidator.Mode.directory, true);
        _spec.completionHint = EntrySpec.CompletionHint.directory;
        return this;
    }

    EntryBuilder!T completesAsFile() {
        _spec.completionHint = EntrySpec.CompletionHint.file;
        return this;
    }

    EntryBuilder!T completesAsDirectory() {
        _spec.completionHint = EntrySpec.CompletionHint.directory;
        return this;
    }

    EntryBuilder!T acceptsPath() {
        _spec.validators ~= new FileSystemValidator(FileSystemValidator.Mode.path, true);
        _spec.completionHint = EntrySpec.CompletionHint.path;
        return this;
    }

    EntryBuilder!T completesAsPath() {
        _spec.completionHint = EntrySpec.CompletionHint.path;
        return this;
    }

    EntryBuilder!T completesWithCommand(string cmd) {
        _spec.completionCommand = cmd;
        return this;
    }

    // Only available for bool flags; calling on EntryBuilder!int is a compile error.
    static if (is(T == bool)) {
        EntryBuilder!T negatable() {
            import darkcommand.command : Command;
            import darkcommand.exceptions : DarkCommandException;
            if (_spec.longName.length == 0)
                throw new DarkCommandException(
                    "negatable() requires a long name (--no-<name> needs a base name)");
            if (_cmd !is null) {
                auto cmd = cast(Command) _cmd;
                if (cmd !is null) cmd._checkNegatable(_spec.longName);
            }
            auto ptr = _ptr;
            _spec.negatable = true;
            _spec.setFalse  = () { *ptr = false; };
            return this;
        }
    }
}
