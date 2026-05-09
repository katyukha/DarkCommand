module darkcommand.command;

import darkcommand.entry;
import darkcommand.validators;
import std.stdio  : File;
import std.traits : isDynamicArray;
import std.range  : ElementType;

public import darkcommand.exceptions : DarkCommandException, DarkCommandExitException;

// ── TopicGroup ────────────────────────────────────────────────────────────────

class TopicGroup {
    private Command _owner;
    private string  _name;

    this(Command owner, string name) {
        _owner = owner;
        _name  = name;
    }

    TopicGroup add(Command sub) {
        _owner._addSubcommand(sub, _name);
        return this;
    }
}

// ── Command ───────────────────────────────────────────────────────────────────

class Command {
    private string    _name;
    private string    _summary;
    private string    _description;
    package(darkcommand) Command     _parent;
    package(darkcommand) Command[]   _subcommands;
    package(darkcommand) EntrySpec[] _entries;

    // Subcommand group labels, parallel to _subcommands (empty string = ungrouped).
    package(darkcommand) string[] _subcommandGroups;

    // Name of the subcommand to dispatch to when no subcommand token is found.
    package(darkcommand) string _defaultCommand;

    string[] argsRest;

    this(string name, string summary = "") {
        import std.ascii : isAlphaNum;
        if (name.length == 0)
            throw new DarkCommandException("command name must not be empty");
        if (!isAlphaNum(name[0]))
            throw new DarkCommandException(
                "invalid command name '" ~ name ~
                "': must start with an alphanumeric character");
        foreach (c; name[1 .. $]) {
            if (!isAlphaNum(c) && c != '-' && c != '_')
                throw new DarkCommandException(
                    "invalid command name '" ~ name ~
                    "': invalid character '" ~ [c] ~ "'");
        }
        _name    = name;
        _summary = summary;
    }

    final string name()        const { return _name; }
    final string summary()     const { return _summary; }
    final string description() const { return _description; }

    Command description(string d) { _description = d; return this; }

    // ── Subcommand registration ────────────────────────────────────────────────

    Command add(Command sub) {
        _addSubcommand(sub, "");
        return this;
    }

    Command defaultCommand(string name) {
        if (_findSubcommand(name) is null)
            throw new DarkCommandException(
                "defaultCommand: no subcommand named '" ~ name ~ "'");
        _defaultCommand = name;
        return this;
    }

    TopicGroup topicGroup(string groupName) {
        return new TopicGroup(this, groupName);
    }

    package(darkcommand) void _addSubcommand(Command sub, string group) {
        foreach (existing; _subcommands)
            if (existing.name == sub.name)
                throw new DarkCommandException(
                    "duplicate subcommand name: '" ~ sub.name ~ "'");
        sub._parent = this;
        _subcommands      ~= sub;
        _subcommandGroups ~= group;
    }

    // ── Hooks (override in subclasses) ─────────────────────────────────────────

    protected void afterParse() {}
    protected void validate_()  {}   // named validate_ to avoid D keyword conflict

    int execute() {
        if (_subcommands.length > 0) {
            import darkcommand.help : printHelp;
            printHelp(this);
            return 1;
        }
        return 0;
    }

    // ── parent!T() ────────────────────────────────────────────────────────────

    T parent(T)() {
        auto p = cast(T) _parent;
        if (p is null)
            throw new DarkCommandException(
                "parent command is " ~
                (_parent !is null ? typeid(_parent).name : "null") ~
                ", expected " ~ T.stringof);
        return p;
    }

    // ── exitWith ──────────────────────────────────────────────────────────────

    final void exitWith(int code, string msg = null) {
        throw new DarkCommandExitException(code, msg);
    }

    // ── Protected finish-helpers (called by free-function templates) ──────────
    //
    // Free-function templates (addFlag/addOption/addArgument) are instantiated
    // in external-user modules that are not in the darkcommand package, so they
    // cannot access package(darkcommand) members directly.  Calling a protected
    // method on `self` works because `self : Command` and protected members are
    // accessible from any subclass context.

    protected final EntryBuilder!T _finishFlag(T)(
        EntrySpec spec, T* ptr, string short_, string long_)
    {
        _checkDuplicateNames(short_, long_);
        _entries ~= spec;
        return new EntryBuilder!T(spec, ptr, this);
    }

    protected final EntryBuilder!T _finishOption(T)(
        EntrySpec spec, T* ptr, string short_, string long_)
    {
        _checkDuplicateNames(short_, long_);
        _setupValueWriters!T(spec, ptr);
        _entries ~= spec;
        return new EntryBuilder!T(spec, ptr, this);
    }

    protected final EntryBuilder!T _finishArgument(T)(
        EntrySpec spec, T* ptr, string displayName)
    {
        foreach (e; _entries) {
            if (e.kind == EntrySpec.Kind.argument && e.isRepeating())
                throw new DarkCommandException(
                    "repeating argument '" ~ e.displayName ~
                    "' must be the last argument; cannot add '" ~ displayName ~ "' after it");
        }
        _setupValueWriters!T(spec, ptr);
        _entries ~= spec;
        return new EntryBuilder!T(spec, ptr, this);
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    package(darkcommand) void _checkDuplicateNames(string short_, string long_) {
        import std.ascii : isAlphaNum;
        if (short_.length) {
            if (short_.length != 1 || !isAlphaNum(short_[0]))
                throw new DarkCommandException(
                    "invalid short name '-" ~ short_ ~
                    "': must be a single alphanumeric character");
        }
        if (long_.length) {
            if (!isAlphaNum(long_[0]))
                throw new DarkCommandException(
                    "invalid long name '--" ~ long_ ~
                    "': must start with an alphanumeric character");
            foreach (c; long_[1 .. $]) {
                if (!isAlphaNum(c) && c != '-' && c != '_')
                    throw new DarkCommandException(
                        "invalid long name '--" ~ long_ ~
                        "': invalid character '" ~ [c] ~ "'");
            }
        }
        foreach (e; _entries) {
            if (short_.length && e.shortName == short_)
                throw new DarkCommandException("duplicate short name: -" ~ short_);
            if (long_.length  && e.longName  == long_)
                throw new DarkCommandException("duplicate long name: --" ~ long_);
            // Registering --no-X when --X is already negatable is a conflict.
            if (long_.length > 3 && long_[0 .. 3] == "no-" &&
                    e.negatable && e.longName == long_[3 .. $])
                throw new DarkCommandException(
                    "--" ~ long_ ~ " conflicts with negatable flag --" ~ long_[3 .. $]);
        }
    }

    package(darkcommand) void _checkNegatable(string baseName) {
        foreach (e; _entries)
            if (e.longName == "no-" ~ baseName)
                throw new DarkCommandException(
                    "--" ~ baseName ~ " cannot be negatable: --no-" ~ baseName ~
                    " is already registered");
    }

    package(darkcommand) Command _findSubcommand(string name) {
        foreach (sub; _subcommands)
            if (sub.name == name) return sub;
        return null;
    }

    package(darkcommand) void _setupValueWriters(T)(EntrySpec spec, T* ptr) {
        import std.conv : to, ConvException;

        spec.writeDefault = () {};  // overridden by .defaultValue() on the builder

        static if (isNullable!T) {
            alias U = NullableTarget!T;
            spec.fieldKind  = EntrySpec.FieldKind.optional;
            spec.writeValue = (string raw) {
                try         { *ptr = T(raw.to!U); }
                catch (ConvException)
                            { throw new DarkCommandException(
                                spec.cliName ~ ": cannot convert '" ~ raw ~
                                "' to " ~ U.stringof); }
            };
            spec.writeReset = () { *ptr = T.init; };

        } else static if (isRepeatingField!T) {
            alias E = ElementType!T;
            spec.fieldKind  = EntrySpec.FieldKind.repeating;
            spec.writeValue = (string raw) {
                try         { *ptr ~= raw.to!E; }
                catch (ConvException)
                            { throw new DarkCommandException(
                                spec.cliName ~ ": cannot convert '" ~ raw ~
                                "' to " ~ E.stringof); }
            };
            spec.writeReset = () { *ptr = null; };

        } else {
            spec.fieldKind  = EntrySpec.FieldKind.required;
            spec.writeValue = (string raw) {
                try         { *ptr = raw.to!T; }
                catch (ConvException)
                            { throw new DarkCommandException(
                                spec.cliName ~ ": cannot convert '" ~ raw ~
                                "' to " ~ T.stringof); }
            };
            spec.writeReset = () { *ptr = T.init; };
        }
    }
}

// ── Program ───────────────────────────────────────────────────────────────────

class Program : Command {
    package(darkcommand) string _version;
    package(darkcommand) bool   _noAutoVersion;

    this(string name, string version_) {
        super(name, "");
        _version = version_;
    }

    Program summary(string s)     { _summary = s; return this; }
    Program noAutoVersion()       { _noAutoVersion = true; return this; }

    protected void setup() {}

    protected int onError(Exception e) {
        import std.stdio : stderr;
        stderr.writeln("Error: ", e.msg);
        return 1;
    }

    final int run(string[] args) {
        import darkcommand.parser : parseChain;
        import std.stdio : stdout, stderr;
        try {
            string[] argv = args.length > 0 ? args[1 .. $] : [];
            auto chain = parseChain(this, argv);

            setup();

            foreach (cmd; chain)
                cmd.afterParse();

            foreach (cmd; chain)
                cmd.validate_();

            Command leaf = chain.length > 0 ? chain[$ - 1] : this;
            return leaf.execute();

        } catch (DarkCommandExitException e) {
            if (e.msg.length > 0) {
                if (e.code == 0) stdout.writeln(e.msg);
                else             stderr.writeln(e.msg);
            }
            return e.code;
        } catch (Exception e) {
            return onError(e);
        }
    }

    final Command parseOnly(string[] args) {
        import darkcommand.parser : parseChain;
        string[] argv = args.length > 0 ? args[1 .. $] : [];
        try {
            auto chain = parseChain(this, argv);
            foreach (cmd; chain) cmd.afterParse();
            foreach (cmd; chain) cmd.validate_();
            return chain.length > 0 ? chain[$ - 1] : this;
        } catch (DarkCommandExitException) {
            return this;
        }
    }

    final void generateBashCompletion(File output) {
        import darkcommand.completion.bash : _gen = generateBashCompletion;
        _gen(this, output);
    }

    final void generateMarkdownDocs(File output) {
        import darkcommand.docs.markdown : _gen = generateMarkdownDocs;
        _gen(this, output);
    }
}

// ── Field registration — free functions, call via UFCS: this.addFlag!(field)(...) ─

private void _checkOwnership(alias field, C)() {
    alias Parent = __traits(parent, field);
    static assert(is(Parent == class),
        __traits(identifier, field) ~ " is not a class field (local variable?)");
    static assert(is(C : Parent),
        __traits(identifier, field) ~ " belongs to " ~ Parent.stringof ~
        " which is not in " ~ C.stringof ~ "'s class hierarchy");
}

EntryBuilder!T addFlag(alias field, C : Command, T = typeof(field))(
    C self, string short_, string long_, string desc)
{
    static assert(is(T == bool) || is(T == int),
        "addFlag: field must be bool or int, not " ~ T.stringof);
    _checkOwnership!(field, C)();

    if (short_.length == 0 && long_.length == 0)
        throw new DarkCommandException("flag must have at least one of short or long name");

    auto spec     = new EntrySpec();
    spec.kind      = EntrySpec.Kind.flag;
    spec.shortName = short_;
    spec.longName  = long_;
    spec.desc      = desc;

    T* ptr = &field;
    static if (is(T == bool)) {
        spec.fieldKind    = EntrySpec.FieldKind.boolFlag;
        spec.setTrue      = () { *ptr = true; };
        spec.writeDefault = () {};
        spec.writeReset   = () { *ptr = false; };
    } else {
        spec.fieldKind    = EntrySpec.FieldKind.intFlag;
        spec.increment_   = () { (*ptr)++; };
        spec.writeDefault = () {};
        spec.writeReset   = () { *ptr = 0; };
    }

    return self._finishFlag!T(spec, ptr, short_, long_);
}

EntryBuilder!T addOption(alias field, C : Command, T = typeof(field))(
    C self, string short_, string long_, string desc)
{
    static assert(!is(T == bool), "addOption: bool fields should use addFlag");
    _checkOwnership!(field, C)();

    if (short_.length == 0 && long_.length == 0)
        throw new DarkCommandException("option must have at least one of short or long name");

    auto spec     = new EntrySpec();
    spec.kind      = EntrySpec.Kind.option;
    spec.shortName = short_;
    spec.longName  = long_;
    spec.desc      = desc;

    T* ptr = &field;
    return self._finishOption!T(spec, ptr, short_, long_);
}

EntryBuilder!T addArgument(alias field, C : Command, T = typeof(field))(
    C self, string displayName, string desc)
{
    static assert(!is(T == bool), "addArgument: bool fields should use addFlag");
    _checkOwnership!(field, C)();

    auto spec        = new EntrySpec();
    spec.kind        = EntrySpec.Kind.argument;
    spec.displayName = displayName;
    spec.desc        = desc;

    T* ptr = &field;
    return self._finishArgument!T(spec, ptr, displayName);
}
