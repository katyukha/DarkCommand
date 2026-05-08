module darkcommand.command;

import darkcommand.entry;
import darkcommand.validators;
import std.stdio  : File;
import std.traits : isDynamicArray;
import std.range  : ElementType;

// ── Exceptions ────────────────────────────────────────────────────────────────

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
    package(darkcommand) Command     _parent;
    package(darkcommand) Command[]   _subcommands;
    package(darkcommand) EntrySpec[] _entries;

    // Subcommand group labels, parallel to _subcommands (empty string = ungrouped).
    package(darkcommand) string[] _subcommandGroups;

    // Name of the subcommand to dispatch to when no subcommand token is found.
    package(darkcommand) string _defaultCommand;

    string[] argsRest;

    this(string name, string summary = "") {
        _name    = name;
        _summary = summary;
    }

    final string name()    const { return _name; }
    final string summary() const { return _summary; }

    // ── Subcommand registration ────────────────────────────────────────────────

    Command add(Command sub) {
        _addSubcommand(sub, "");
        return this;
    }

    Command defaultCommand(string name) {
        _defaultCommand = name;
        return this;
    }

    TopicGroup topicGroup(string groupName) {
        return new TopicGroup(this, groupName);
    }

    package void _addSubcommand(Command sub, string group) {
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

    // ── Private helpers ───────────────────────────────────────────────────────

    package(darkcommand) void _checkDuplicateNames(string short_, string long_) {
        foreach (e; _entries) {
            if (short_.length && e.shortName == short_)
                throw new DarkCommandException("duplicate short name: -" ~ short_);
            if (long_.length  && e.longName  == long_)
                throw new DarkCommandException("duplicate long name: --" ~ long_);
        }
    }

    package(darkcommand) void _setupValueWriters(T)(EntrySpec spec, T* ptr) {
        import std.conv : to, ConvException;

        static if (isNullable!T) {
            alias U = NullableTarget!T;
            spec.fieldKind    = EntrySpec.FieldKind.optional;
            spec.writeValue   = (string raw) {
                try         { *ptr = T(raw.to!U); }
                catch (ConvException)
                            { throw new DarkCommandException(
                                spec.cliName ~ ": cannot convert '" ~ raw ~
                                "' to " ~ U.stringof); }
            };
            spec.writeDefault = () {};

        } else static if (isRepeatingField!T) {
            alias E = ElementType!T;
            spec.fieldKind    = EntrySpec.FieldKind.repeating;
            spec.writeValue   = (string raw) {
                try         { *ptr ~= raw.to!E; }
                catch (ConvException)
                            { throw new DarkCommandException(
                                spec.cliName ~ ": cannot convert '" ~ raw ~
                                "' to " ~ E.stringof); }
            };
            spec.writeDefault = () {};

        } else {
            spec.fieldKind    = EntrySpec.FieldKind.required;
            spec.writeValue   = (string raw) {
                try         { *ptr = raw.to!T; }
                catch (ConvException)
                            { throw new DarkCommandException(
                                spec.cliName ~ ": cannot convert '" ~ raw ~
                                "' to " ~ T.stringof); }
            };
            spec.writeDefault = () {};
        }
    }
}

// ── Program ───────────────────────────────────────────────────────────────────

class Program : Command {
    private string _version;
    private bool   _noAutoVersion;

    this(string name, string version_) {
        super(name, "");
        _version = version_;
    }

    Program summary(string s) { _summary = s; return this; }

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
        } catch (DarkCommandException e) {
            return onError(e);
        } catch (Exception e) {
            return onError(e);
        }
    }

    final Command parseOnly(string[] args) {
        import darkcommand.parser : parseChain;
        string[] argv = args.length > 0 ? args[1 .. $] : [];
        auto chain = parseChain(this, argv);
        foreach (cmd; chain) cmd.afterParse();
        foreach (cmd; chain) cmd.validate_();
        return chain.length > 0 ? chain[$ - 1] : this;
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
    self._checkDuplicateNames(short_, long_);

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
    } else {
        spec.fieldKind    = EntrySpec.FieldKind.intFlag;
        spec.increment_   = () { (*ptr)++; };
        spec.writeDefault = () {};
    }

    self._entries ~= spec;
    return new EntryBuilder!T(spec, ptr);
}

EntryBuilder!T addOption(alias field, C : Command, T = typeof(field))(
    C self, string short_, string long_, string desc)
{
    static assert(!is(T == bool), "addOption: bool fields should use addFlag");
    _checkOwnership!(field, C)();

    if (short_.length == 0 && long_.length == 0)
        throw new DarkCommandException("option must have at least one of short or long name");
    self._checkDuplicateNames(short_, long_);

    auto spec     = new EntrySpec();
    spec.kind      = EntrySpec.Kind.option;
    spec.shortName = short_;
    spec.longName  = long_;
    spec.desc      = desc;

    T* ptr = &field;
    self._setupValueWriters!T(spec, ptr);

    self._entries ~= spec;
    return new EntryBuilder!T(spec, ptr);
}

EntryBuilder!T addArgument(alias field, C : Command, T = typeof(field))(
    C self, string displayName, string desc)
{
    static assert(!is(T == bool), "addArgument: bool fields should use addFlag");
    _checkOwnership!(field, C)();

    foreach (e; self._entries) {
        if (e.kind == EntrySpec.Kind.argument && e.isRepeating())
            throw new DarkCommandException(
                "repeating argument '" ~ e.displayName ~
                "' must be the last argument; cannot add '" ~ displayName ~ "' after it");
    }

    auto spec        = new EntrySpec();
    spec.kind        = EntrySpec.Kind.argument;
    spec.displayName = displayName;
    spec.desc        = desc;

    T* ptr = &field;
    self._setupValueWriters!T(spec, ptr);

    self._entries ~= spec;
    return new EntryBuilder!T(spec, ptr);
}
