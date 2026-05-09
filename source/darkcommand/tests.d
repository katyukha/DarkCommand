module darkcommand.tests;

import darkcommand;
import std.typecons : Nullable;

// ── Helpers ───────────────────────────────────────────────────────────────────

T parseOnly(T)(Program prog, string[] args) {
    auto leaf = prog.parseOnly(args);
    auto t = cast(T) leaf;
    assert(t !is null, "leaf is not " ~ T.stringof ~ " but " ~ typeid(leaf).name);
    return t;
}

void assertParseError(Program prog, string[] args, string substr = "") {
    import std.string : indexOf;
    bool thrown = false;
    try { prog.parseOnly(args); }
    catch (DarkCommandException e) {
        thrown = true;
        if (substr.length)
            assert(e.msg.indexOf(substr) >= 0,
                "Expected '" ~ substr ~ "' in error: " ~ e.msg);
    }
    assert(thrown, "Expected DarkCommandException but none was thrown");
}

// ── Fixtures — all at module scope to avoid DMD dual-context deprecation ──────

class BoolFlagApp : Program {
    bool quiet;
    this() {
        super("app", "1.0.0");
        this.addFlag!(quiet)("q", "quiet", "Suppress output");
    }
    override protected void setup() {}
}

class IntFlagApp : Program {
    int verbosity;
    this() {
        super("app", "1.0.0");
        this.addFlag!(verbosity)("v", "verbose", "Increase verbosity");
    }
    override protected void setup() {}
}

class RequiredOptApp : Program {
    string output;
    this() {
        super("app", "1.0.0");
        this.addOption!(output)("o", "output", "Output path");
    }
    override protected void setup() {}
}

class NullableOptApp : Program {
    Nullable!string format;
    this() {
        super("app", "1.0.0");
        this.addOption!(format)("f", "format", "Format");
    }
    override protected void setup() {}
}

class DefaultOptApp : Program {
    int shards;
    this() {
        super("app", "1.0.0");
        this.addOption!(shards)(null, "shards", "Shard count").defaultValue(4);
    }
    override protected void setup() {}
}

class RepeatingOptApp : Program {
    string[] tags;
    this() {
        super("app", "1.0.0");
        this.addOption!(tags)(null, "tag", "Tag (repeatable)");
    }
    override protected void setup() {}
}

class TypedOptApp : Program {
    int port;
    this() {
        super("app", "1.0.0");
        this.addOption!(port)("p", "port", "Port").defaultValue(8080);
    }
    override protected void setup() {}
}

class PosArgApp : Program {
    string name;
    this() {
        super("app", "1.0.0");
        this.addArgument!(name)("name", "The name");
    }
    override protected void setup() {}
}

class RepArgApp : Program {
    string[] files;
    this() {
        super("app", "1.0.0");
        this.addArgument!(files)("files", "Input files");
    }
    override protected void setup() {}
}

class ArgsRestApp : Program {
    this() { super("app", "1.0.0"); }
    override protected void setup() {}
}

class SubDispatchCmd : Command {
    string value;
    this() {
        super("foo", "Foo command");
        this.addOption!(value)("v", "value", "A value");
    }
}
class SubDispatchApp : Program {
    this() {
        super("app", "1.0.0");
        add(new SubDispatchCmd());
    }
    override protected void setup() {}
}

class SubStopsAtDashDashSub : Command {
    this() { super("sub", "A subcommand"); }
}
class SubStopsAtDashDashApp : Program {
    this() {
        super("app", "1.0.0");
        add(new SubStopsAtDashDashSub());
    }
    override protected void setup() {}
}

class ParentCmd : Command {
    this() {
        super("parent", "parent");
        add(new ChildCmd());
    }
}
class ChildCmd : Command {
    this() { super("child", "child"); }
    string getParentName() { return parent!ParentCmd.name; }
}
class ParentChildApp : Program {
    this() {
        super("app", "1.0.0");
        add(new ParentCmd());
    }
    override protected void setup() {}
}

// Hooks are on a Command subclass; Program uses setup(), not afterParse/validate.
class HooksCmd : Command {
    string method;
    string target;
    bool   afterParseCalled;
    bool   validateCalled;
    this() {
        super("deploy", "Deploy");
        this.addOption!(method)("m", "method", "Method");
        this.addOption!(target)("t", "target", "Target");
    }
    override protected void afterParse() { afterParseCalled = true; }
    override protected void validate() {
        validateCalled = true;
        if (method == "bad" && target == "prod")
            throw new DarkCommandException("bad+prod not allowed");
    }
}
class HooksApp : Program {
    this() {
        super("app", "1.0.0");
        add(new HooksCmd());
    }
    override protected void setup() {}
}

class EnumValApp : Program {
    string fmt;
    this() {
        super("app", "1.0.0");
        this.addOption!(fmt)("f", "format", "Format").acceptsValues(["json", "csv"]);
    }
    override protected void setup() {}
}

class DelegateValApp : Program {
    int count;
    this() {
        super("app", "1.0.0");
        this.addOption!(count)("n", "count", "Count")
            .defaultValue(1)
            .validateEachWith(v => v > 0, "must be positive");
    }
    override protected void setup() {}
}

class MixedStackApp : Program {
    int    verbosity;
    string output;
    this() {
        super("app", "1.0.0");
        this.addFlag!(verbosity)("v", "verbose", "Verbosity");
        this.addOption!(output)("o", "output", "Output");
    }
    override protected void setup() {}
}

class ExitWithApp : Program {
    this() { super("app", "1.0.0"); }
    override protected void setup() {}
    override int execute() {
        exitWith(1, "something failed");
        return 0;
    }
}

class TopicGroupApp : Program {
    this() {
        super("app", "1.0.0");
        topicGroup("Main")
            .add(new SubDispatchCmd());
        add(new SubStopsAtDashDashSub());
    }
    override protected void setup() {}
}

// ── negatable flag fixtures ───────────────────────────────────────────────────

class NegatableApp : Program {
    bool verbose;
    bool color;
    this() {
        super("app", "1.0.0");
        this.addFlag!(verbose)("v", "verbose", "Verbose output").negatable();
        this.addFlag!(color)(null, "color", "Enable color").negatable();
    }
    override protected void setup() {}
}

// ── defaultCommand fixtures ───────────────────────────────────────────────────

class DefaultSub : Command {
    this() { super("serve", "Serve mode"); }
}
class DefaultCmdApp : Program {
    this() {
        super("app", "1.0.0");
        add(new DefaultSub());
        defaultCommand("serve");
    }
    override protected void setup() {}
}

class DefaultSubWithOpt : Command {
    int port;
    this() {
        super("serve", "Serve mode");
        this.addOption!(port)("p", "port", "Port").defaultValue(8080);
    }
}
class DefaultCmdOptApp : Program {
    this() {
        super("app", "1.0.0");
        add(new DefaultSubWithOpt());
        defaultCommand("serve");
    }
    override protected void setup() {}
}

// ── GenDocs fixtures ──────────────────────────────────────────────────────────

class GenDocsSubCmd : Command {
    string output;
    this() {
        super("run", "Run the thing");
        this.addOption!(output)("o", "output", "Output path").completesAsFile();
    }
}
class GenDocsApp : Program {
    string format;
    int verbosity;
    this() {
        super("myprog", "1.0.0");
        summary("Does things.");
        this.addFlag!(verbosity)("v", "verbose", "Verbosity");
        this.addOption!(format)("f", "format", "Output format").acceptsValues(["json", "csv"]);
        add(new GenDocsSubCmd());
    }
    override protected void setup() {}
}

// ── Tests ─────────────────────────────────────────────────────────────────────

unittest { // bool flag: absent → false, -q → true, --quiet → true
    auto app = new BoolFlagApp();
    app.parseOnly(["app"]);
    assert(app.quiet == false);

    app = new BoolFlagApp();
    app.parseOnly(["app", "-q"]);
    assert(app.quiet == true);

    app = new BoolFlagApp();
    app.parseOnly(["app", "--quiet"]);
    assert(app.quiet == true);
}

unittest { // int flag: -vvv → 3, -v -v → 2, --verbose --verbose → 2
    auto app = new IntFlagApp();
    app.parseOnly(["app", "-vvv"]);
    assert(app.verbosity == 3);

    app = new IntFlagApp();
    app.parseOnly(["app", "-v", "-v"]);
    assert(app.verbosity == 2);

    app = new IntFlagApp();
    app.parseOnly(["app", "--verbose", "--verbose"]);
    assert(app.verbosity == 2);
}

unittest { // bool flag stacking error
    assertParseError(new BoolFlagApp(), ["app", "-qq"], "boolean");
}

unittest { // int flag is not value-taking: "--verbose 3" treats 3 as unexpected arg
    assertParseError(new IntFlagApp(), ["app", "--verbose", "3"], "unexpected argument");
}

unittest { // required option: --output, -o, --output=, missing → error
    auto app = new RequiredOptApp();
    app.parseOnly(["app", "--output", "file.txt"]);
    assert(app.output == "file.txt");

    app = new RequiredOptApp();
    app.parseOnly(["app", "-o", "file.txt"]);
    assert(app.output == "file.txt");

    app = new RequiredOptApp();
    app.parseOnly(["app", "--output=file.txt"]);
    assert(app.output == "file.txt");

    assertParseError(new RequiredOptApp(), ["app"], "missing required option: --output");
}

unittest { // Nullable option: absent → isNull, provided → has value
    auto app = new NullableOptApp();
    app.parseOnly(["app"]);
    assert(app.format.isNull);

    app = new NullableOptApp();
    app.parseOnly(["app", "--format", "json"]);
    assert(!app.format.isNull);
    assert(app.format.get == "json");
}

unittest { // defaultValue: absent → default, provided → user value
    auto app = new DefaultOptApp();
    app.parseOnly(["app"]);
    assert(app.shards == 4);

    app = new DefaultOptApp();
    app.parseOnly(["app", "--shards", "8"]);
    assert(app.shards == 8);
}

unittest { // repeating option: absent → [], multiple → accumulated
    auto app = new RepeatingOptApp();
    app.parseOnly(["app"]);
    assert(app.tags == []);

    app = new RepeatingOptApp();
    app.parseOnly(["app", "--tag", "a", "--tag", "b"]);
    assert(app.tags == ["a", "b"]);
}

unittest { // typed option: int conversion, bad value → error with "cannot convert"
    auto app = new TypedOptApp();
    app.parseOnly(["app", "--port", "9000"]);
    assert(app.port == 9000);

    assertParseError(new TypedOptApp(), ["app", "--port", "notanumber"], "cannot convert");
}

unittest { // positional argument: present → value, absent → error
    auto app = new PosArgApp();
    app.parseOnly(["app", "alice"]);
    assert(app.name == "alice");

    assertParseError(new PosArgApp(), ["app"], "missing required argument: name");
}

unittest { // repeating positional T[]: one or more, absent → error
    auto app = new RepArgApp();
    app.parseOnly(["app", "a.txt", "b.txt", "c.txt"]);
    assert(app.files == ["a.txt", "b.txt", "c.txt"]);

    assertParseError(new RepArgApp(), ["app"], "missing required argument: files");
}

unittest { // argsRest: everything after -- goes to argsRest
    auto app = new ArgsRestApp();
    app.parseOnly(["app", "--", "--port", "8080"]);
    assert(app.argsRest == ["--port", "8080"]);
}

unittest { // argsRest: defaults still applied when -- is present
    auto app = new TypedOptApp();
    app.parseOnly(["app", "--", "extra"]);
    assert(app.port == 8080);   // defaultValue must fire even with --
    assert(app.argsRest == ["extra"]);
}

unittest { // -- before subcommand stops dispatch
    auto app = new SubStopsAtDashDashApp();
    auto leaf = app.parseOnly(["app", "--", "sub"]);
    assert(leaf is app);
    assert(app.argsRest == ["sub"]);
}

unittest { // subcommand dispatch + option on subcommand
    auto app = new SubDispatchApp();
    auto leaf = .parseOnly!SubDispatchCmd(app, ["app", "foo", "--value", "hello"]);
    assert(leaf.value == "hello");
}

unittest { // parent!T()
    auto app  = new ParentChildApp();
    auto child = .parseOnly!ChildCmd(app, ["app", "parent", "child"]);
    assert(child.getParentName() == "parent");
}

unittest { // afterParse and validate hooks called on subcommand; validate can abort
    auto app = new HooksApp();
    auto cmd = .parseOnly!HooksCmd(app, ["app", "deploy", "--method", "ok", "--target", "dev"]);
    assert(cmd.afterParseCalled);
    assert(cmd.validateCalled);

    assertParseError(new HooksApp(),
        ["app", "deploy", "--method", "bad", "--target", "prod"], "bad+prod not allowed");
}

unittest { // EnumValidator via acceptsValues
    auto app = new EnumValApp();
    app.parseOnly(["app", "--format", "json"]);
    assert(app.fmt == "json");

    assertParseError(new EnumValApp(), ["app", "--format", "xml"], "must be one of");
}

unittest { // validateEachWith
    auto app = new DelegateValApp();
    app.parseOnly(["app", "--count", "5"]);
    assert(app.count == 5);

    assertParseError(new DelegateValApp(), ["app", "--count", "0"], "must be positive");
}

// Stack variable rejection and unrelated-class field rejection are compile-time static asserts.
// Passing a local variable triggers: "stackVar is not a class field (local variable?)"
// Passing a field from an unrelated class triggers: "x belongs to OtherCmd which is not
// in MyCmd's class hierarchy"

unittest { // definition-time: duplicate short name
    import std.exception : assertThrown;
    assertThrown!DarkCommandException({
        class Bad : Program {
            bool a, b;
            this() {
                super("app", "1.0.0");
                this.addFlag!(a)("x", "aaa", "A");
                this.addFlag!(b)("x", "bbb", "B");
            }
        }
        new Bad();
    }());
}

unittest { // definition-time: T[] argument not last
    import std.exception : assertThrown;
    assertThrown!DarkCommandException({
        class Bad : Program {
            string[] files;
            string   extra;
            this() {
                super("app", "1.0.0");
                this.addArgument!(files)("files", "Files");
                this.addArgument!(extra)("extra", "Extra");
            }
        }
        new Bad();
    }());
}

unittest { // did-you-mean suggestion on unknown option
    assertParseError(new IntFlagApp(), ["app", "--vrebose"], "did you mean");
}

unittest { // exitWith: run() returns the exit code; non-zero message goes to stderr
    import std.stdio : stderr, File;
    import std.string : strip;

    auto tmp   = File.tmpfile();
    auto saved = stderr;
    stderr = tmp;
    int code = new ExitWithApp().run(["app"]);
    tmp.flush();
    stderr = saved;

    assert(code == 1);
    tmp.seek(0);
    char[] line;
    tmp.readln(line);
    assert(line.strip == "something failed");
}

unittest { // short option with = form: -o=file.txt
    auto app = new RequiredOptApp();
    app.parseOnly(["app", "-o=file.txt"]);
    assert(app.output == "file.txt");
}

unittest { // mixed stack + value option: -vo file.txt
    auto app = new MixedStackApp();
    app.parseOnly(["app", "-vo", "file.txt"]);
    assert(app.verbosity == 1);
    assert(app.output == "file.txt");
}

unittest { // topicGroup subcommands are still reachable
    auto app = new TopicGroupApp();
    auto leaf = .parseOnly!SubDispatchCmd(app, ["app", "foo", "--value", "x"]);
    assert(leaf !is null);
}

// ── negatable flags ───────────────────────────────────────────────────────────

unittest { // --flag → true, --no-flag → false, absent → false
    auto app = new NegatableApp();
    app.parseOnly(["app"]);
    assert(app.verbose == false);

    app = new NegatableApp();
    app.parseOnly(["app", "--verbose"]);
    assert(app.verbose == true);

    app = new NegatableApp();
    app.parseOnly(["app", "--no-verbose"]);
    assert(app.verbose == false);
}

unittest { // --flag --no-flag → false (last wins); --no-flag --flag → true
    auto app = new NegatableApp();
    app.parseOnly(["app", "--verbose", "--no-verbose"]);
    assert(app.verbose == false);

    app = new NegatableApp();
    app.parseOnly(["app", "--no-verbose", "--verbose"]);
    assert(app.verbose == true);
}

unittest { // short flag still works alongside negatable long form
    auto app = new NegatableApp();
    app.parseOnly(["app", "-v"]);
    assert(app.verbose == true);

    app = new NegatableApp();
    app.parseOnly(["app", "-v", "--no-verbose"]);
    assert(app.verbose == false);
}

unittest { // negatable flag without short name
    auto app = new NegatableApp();
    app.parseOnly(["app", "--no-color"]);
    assert(app.color == false);

    app = new NegatableApp();
    app.parseOnly(["app", "--color"]);
    assert(app.color == true);
}

unittest { // --no-flag=value is an error
    assertParseError(new NegatableApp(), ["app", "--no-verbose=yes"], "does not take a value");
}

unittest { // negatable: definition-time error when flag has no long name
    import std.exception : assertThrown;
    assertThrown!DarkCommandException({
        class Bad : Program {
            bool f;
            this() {
                super("app", "1.0.0");
                this.addFlag!(f)("f", null, "Flag").negatable();
            }
        }
        new Bad();
    }());
}

// negatable() on an int flag is a compile-time error (no .negatable() on EntryBuilder!int).
// negatable() on an option is also a compile-time error.

unittest { // help output shows --[no-]name for negatable flags
    import std.stdio : stdout, File;
    import std.string : indexOf;

    auto tmp   = File.tmpfile();
    auto saved = stdout;
    stdout = tmp;
    scope(exit) stdout = saved;

    import darkcommand.help : printHelp;
    printHelp(new NegatableApp());
    stdout.flush();

    tmp.seek(0);
    string content;
    char[] line;
    while (tmp.readln(line)) content ~= line;

    assert(content.indexOf("--[no-]verbose") >= 0, content);
    assert(content.indexOf("--[no-]color")   >= 0, content);
}

// ── defaultCommand ────────────────────────────────────────────────────────────

unittest { // defaultCommand: no subcommand typed → dispatches to default
    auto app = new DefaultCmdApp();
    auto leaf = app.parseOnly(["app"]);
    assert(cast(DefaultSub) leaf !is null);
}

unittest { // defaultCommand: explicit subcommand still routed normally
    auto app = new DefaultCmdApp();
    auto leaf = app.parseOnly(["app", "serve"]);
    assert(cast(DefaultSub) leaf !is null);
}

unittest { // defaultCommand: options on the default subcommand parsed correctly
    auto app = new DefaultCmdOptApp();
    auto leaf = .parseOnly!DefaultSubWithOpt(app, ["app", "--port", "9000"]);
    assert(leaf.port == 9000);
}

unittest { // defaultCommand: default subcommand gets its own defaultValue
    auto app = new DefaultCmdOptApp();
    auto leaf = .parseOnly!DefaultSubWithOpt(app, ["app"]);
    assert(leaf.port == 8080);
}

// ── Bash completion ───────────────────────────────────────────────────────────

unittest { // bash completion: entry point and complete directive present
    import darkcommand.completion.bash : generateBashCompletion;
    import std.stdio : File;
    import std.string : indexOf;

    auto tmp = File.tmpfile();
    new GenDocsApp().generateBashCompletion(tmp);
    tmp.flush(); tmp.seek(0);

    string content;
    char[] line;
    while (tmp.readln(line)) content ~= line;

    assert(content.indexOf("complete -F __myprog myprog") >= 0);
    assert(content.indexOf("__myprog()") >= 0);
}

unittest { // bash completion: subcommand and options appear in word lists
    import darkcommand.completion.bash : generateBashCompletion;
    import std.stdio : File;
    import std.string : indexOf;

    auto tmp = File.tmpfile();
    new GenDocsApp().generateBashCompletion(tmp);
    tmp.flush(); tmp.seek(0);

    string content;
    char[] line;
    while (tmp.readln(line)) content ~= line;

    assert(content.indexOf("run") >= 0);       // subcommand name
    assert(content.indexOf("--format") >= 0);  // option
    assert(content.indexOf("-v") >= 0);        // short flag
    assert(content.indexOf("--help") >= 0);
}

unittest { // bash completion: --version present for Program with auto-version
    import darkcommand.completion.bash : generateBashCompletion;
    import std.stdio : File;
    import std.string : indexOf;
    auto tmp = File.tmpfile();
    new GenDocsApp().generateBashCompletion(tmp);
    tmp.flush(); tmp.seek(0);
    string content; char[] line;
    while (tmp.readln(line)) content ~= line;
    assert(content.indexOf("--version") >= 0, content);
}

unittest { // bash completion: enum values and file completion hints
    import darkcommand.completion.bash : generateBashCompletion;
    import std.stdio : File;
    import std.string : indexOf;

    auto tmp = File.tmpfile();
    new GenDocsApp().generateBashCompletion(tmp);
    tmp.flush(); tmp.seek(0);

    string content;
    char[] line;
    while (tmp.readln(line)) content ~= line;

    assert(content.indexOf("json csv") >= 0);   // enum values for --format
    assert(content.indexOf("compgen -f") >= 0); // file completion for --output
}

// ── Markdown docs ─────────────────────────────────────────────────────────────

unittest { // markdown docs: top-level heading and summary
    import darkcommand.docs.markdown : generateMarkdownDocs;
    import std.stdio : File;
    import std.string : indexOf;

    auto tmp = File.tmpfile();
    new GenDocsApp().generateMarkdownDocs(tmp);
    tmp.flush(); tmp.seek(0);

    string content;
    char[] line;
    while (tmp.readln(line)) content ~= line;

    assert(content.indexOf("# myprog") >= 0);
    assert(content.indexOf("Does things.") >= 0);
}

unittest { // markdown docs: options and subcommand sections present
    import darkcommand.docs.markdown : generateMarkdownDocs;
    import std.stdio : File;
    import std.string : indexOf;

    auto tmp = File.tmpfile();
    new GenDocsApp().generateMarkdownDocs(tmp);
    tmp.flush(); tmp.seek(0);

    string content;
    char[] line;
    while (tmp.readln(line)) content ~= line;

    assert(content.indexOf("--format") >= 0);
    assert(content.indexOf("run") >= 0);          // subcommand name appears
    assert(content.indexOf("## myprog run") >= 0); // subcommand heading
    assert(content.indexOf("--output") >= 0);
}

// ── Fixtures for issue-fix tests ─────────────────────────────────────────────

class PipeDescApp : Program {
    string fmt;
    this() {
        super("app", "1.0.0");
        this.addOption!(fmt)("f", "format", "one | two | three");
    }
    override protected void setup() {}
}

class UnderscoreSubCmd : Command {
    this() { super("my_command", "Sub"); }
}
class UnderscoreApp : Program {
    this() {
        super("my_app", "1.0.0");
        add(new UnderscoreSubCmd());
    }
    override protected void setup() {}
}

// ── Same-instance reparse ─────────────────────────────────────────────────────

unittest { // same-instance reparse: bool flag resets to false
    auto app = new BoolFlagApp();
    app.parseOnly(["app", "-q"]);
    assert(app.quiet == true);
    app.parseOnly(["app"]);
    assert(app.quiet == false);
}

unittest { // same-instance reparse: int flag count resets to zero
    auto app = new IntFlagApp();
    app.parseOnly(["app", "-vvv"]);
    assert(app.verbosity == 3);
    app.parseOnly(["app", "-v"]);
    assert(app.verbosity == 1);
}

unittest { // same-instance reparse: default value re-applied
    auto app = new DefaultOptApp();
    app.parseOnly(["app", "--shards", "8"]);
    assert(app.shards == 8);
    app.parseOnly(["app"]);
    assert(app.shards == 4);
}

unittest { // same-instance reparse: required option re-enforced
    auto app = new RequiredOptApp();
    app.parseOnly(["app", "--output", "first.txt"]);
    assertParseError(app, ["app"], "missing required");
}

unittest { // same-instance reparse: repeating array resets to empty
    auto app = new RepeatingOptApp();
    app.parseOnly(["app", "--tag", "a", "--tag", "b"]);
    assert(app.tags == ["a", "b"]);
    app.parseOnly(["app", "--tag", "c"]);
    assert(app.tags == ["c"]);
}

// ── Markdown pipe escaping ────────────────────────────────────────────────────

unittest { // markdown docs: pipe in description is escaped as \|
    import darkcommand.docs.markdown : generateMarkdownDocs;
    import std.stdio : File;
    import std.string : indexOf;
    auto tmp = File.tmpfile();
    new PipeDescApp().generateMarkdownDocs(tmp);
    tmp.flush(); tmp.seek(0);
    string content; char[] line;
    while (tmp.readln(line)) content ~= line;
    assert(content.indexOf("one \\| two \\| three") >= 0, content);
}

// ── Markdown anchor underscores ───────────────────────────────────────────────

unittest { // markdown anchor: underscore in command name preserved
    import darkcommand.docs.markdown : generateMarkdownDocs;
    import std.stdio : File;
    import std.string : indexOf;
    auto tmp = File.tmpfile();
    new UnderscoreApp().generateMarkdownDocs(tmp);
    tmp.flush(); tmp.seek(0);
    string content; char[] line;
    while (tmp.readln(line)) content ~= line;
    assert(content.indexOf("my_app-my_command") >= 0, content);
}

// ── parseOnly: exit exception handling ───────────────────────────────────────

unittest { // parseOnly: --help returns leaf without throwing
    import std.stdio : stdout, File;
    auto tmp   = File.tmpfile();
    auto saved = stdout;
    stdout = tmp;
    scope(exit) stdout = saved;
    auto app = new BoolFlagApp();
    Command leaf = app.parseOnly(["app", "--help"]);
    assert(leaf !is null);
}

// ── Negatable conflict detection ──────────────────────────────────────────────

unittest { // definition-time: negatable --X then option --no-X → error
    import std.exception : assertThrown;
    assertThrown!DarkCommandException({
        class BadNeg1 : Program {
            bool verbose;
            string noVerbose;
            this() {
                super("app", "1.0.0");
                this.addFlag!(verbose)("v", "verbose", "Verbose").negatable();
                this.addOption!(noVerbose)("", "no-verbose", "Opt");
            }
        }
        new BadNeg1();
    }());
}

unittest { // definition-time: option --no-X then negatable --X → error
    import std.exception : assertThrown;
    assertThrown!DarkCommandException({
        class BadNeg2 : Program {
            bool verbose;
            string noVerbose;
            this() {
                super("app", "1.0.0");
                this.addOption!(noVerbose)("", "no-verbose", "Opt");
                this.addFlag!(verbose)("v", "verbose", "Verbose").negatable();
            }
        }
        new BadNeg2();
    }());
}

// ── Bash completion: negatable flags ──────────────────────────────────────────

unittest { // bash completion: --no-X form listed for negatable flags
    import darkcommand.completion.bash : generateBashCompletion;
    import std.stdio : File;
    import std.string : indexOf;
    auto tmp = File.tmpfile();
    new NegatableApp().generateBashCompletion(tmp);
    tmp.flush(); tmp.seek(0);
    string content; char[] line;
    while (tmp.readln(line)) content ~= line;
    assert(content.indexOf("--no-verbose") >= 0, content);
    assert(content.indexOf("--no-color")   >= 0, content);
}

// ── Malformed option names ────────────────────────────────────────────────────

unittest { // definition-time: multi-char short name rejected
    import std.exception : assertThrown;
    assertThrown!DarkCommandException({
        class BadName1 : Program {
            bool f;
            this() {
                super("app", "1.0.0");
                this.addFlag!(f)("ab", "flag", "Flag");
            }
        }
        new BadName1();
    }());
}

unittest { // definition-time: long name with space rejected
    import std.exception : assertThrown;
    assertThrown!DarkCommandException({
        class BadName2 : Program {
            bool f;
            this() {
                super("app", "1.0.0");
                this.addFlag!(f)("f", "flag name", "Flag");
            }
        }
        new BadName2();
    }());
}

// ── Command name validation ───────────────────────────────────────────────────

unittest { // definition-time: empty command name rejected
    import std.exception : assertThrown;
    assertThrown!DarkCommandException(new Command(""));
}

unittest { // definition-time: command name with invalid character rejected
    import std.exception : assertThrown;
    assertThrown!DarkCommandException(new Command("bad name"));
}

// ── Version support ───────────────────────────────────────────────────────────

unittest { // --version prints name + version to stdout and exits 0
    import std.stdio : stdout, File;
    import std.string : strip;
    auto tmp   = File.tmpfile();
    auto saved = stdout;
    stdout = tmp;
    int code = new BoolFlagApp().run(["app", "--version"]);
    tmp.flush();
    stdout = saved;
    assert(code == 0);
    tmp.seek(0);
    char[] line;
    tmp.readln(line);
    assert(line.strip == "app 1.0.0", cast(string) line);
}

unittest { // noAutoVersion(): --version treated as unknown option
    auto app = new BoolFlagApp();
    app.noAutoVersion();
    assertParseError(app, ["app", "--version"], "unknown option");
}

// ── Help always shows -h/--help and --version ─────────────────────────────────

class ArgOnlyApp : Program {
    string val;
    this() {
        super("app", "1.0.0");
        this.addArgument!(val)("val", "A value");
    }
    override protected void setup() {}
}

unittest { // help: -h/--help shown even when command has no user-defined options
    import std.stdio : stdout, File;
    import std.string : indexOf;
    auto tmp   = File.tmpfile();
    auto saved = stdout;
    stdout = tmp;
    scope(exit) stdout = saved;
    import darkcommand.help : printHelp;
    printHelp(new ArgOnlyApp());
    stdout.flush();
    tmp.seek(0);
    string content; char[] line;
    while (tmp.readln(line)) content ~= line;
    assert(content.indexOf("--help") >= 0, content);
}

unittest { // help: --version shown for Program with auto-version enabled
    import std.stdio : stdout, File;
    import std.string : indexOf;
    auto tmp   = File.tmpfile();
    auto saved = stdout;
    stdout = tmp;
    scope(exit) stdout = saved;
    import darkcommand.help : printHelp;
    printHelp(new BoolFlagApp());
    stdout.flush();
    tmp.seek(0);
    string content; char[] line;
    while (tmp.readln(line)) content ~= line;
    assert(content.indexOf("--version") >= 0, content);
}

// ── Duplicate subcommand + defaultCommand existence ───────────────────────────

unittest { // definition-time: duplicate subcommand name rejected
    import std.exception : assertThrown;
    assertThrown!DarkCommandException({
        class DupSub : Program {
            this() {
                super("app", "1.0.0");
                add(new SubDispatchCmd());
                add(new SubDispatchCmd());
            }
        }
        new DupSub();
    }());
}

unittest { // definition-time: defaultCommand with nonexistent name rejected
    import std.exception : assertThrown;
    assertThrown!DarkCommandException({
        class BadDef : Program {
            this() {
                super("app", "1.0.0");
                add(new DefaultSub());
                defaultCommand("nonexistent");
            }
        }
        new BadDef();
    }());
}

// ── Markdown newline in description ──────────────────────────────────────────

class NewlineDescApp : Program {
    string val;
    this() {
        super("app", "1.0.0");
        this.addOption!(val)("v", "value", "line1\nline2");
    }
    override protected void setup() {}
}

unittest { // markdown docs: newline in description does not break table row
    import darkcommand.docs.markdown : generateMarkdownDocs;
    import std.stdio : File;
    import std.string : indexOf;
    auto tmp = File.tmpfile();
    new NewlineDescApp().generateMarkdownDocs(tmp);
    tmp.flush(); tmp.seek(0);
    string content; char[] line;
    while (tmp.readln(line)) content ~= line;
    assert(content.indexOf("line1 line2") >= 0, content);
}

// ── Long description ──────────────────────────────────────────────────────────

class LongDescApp : Program {
    this() {
        super("app", "1.0.0");
        summary("Short summary.");
        description("First paragraph.\n\nSecond paragraph.");
    }
    override protected void setup() {}
}

class LongDescSubCmd : Command {
    this() {
        super("sub", "Sub summary.");
        description("Sub long description.");
    }
}
class LongDescSubApp : Program {
    this() {
        super("app", "1.0.0");
        add(new LongDescSubCmd());
    }
    override protected void setup() {}
}

unittest { // description: defaults to empty string
    assert(new BoolFlagApp().description == "");
}

unittest { // description: setter stores value; getter returns it
    assert(new LongDescApp().description == "First paragraph.\n\nSecond paragraph.");
}

unittest { // help: description appears after summary, before options
    import std.stdio : stdout, File;
    import std.string : indexOf;
    auto tmp = File.tmpfile();
    auto saved = stdout;
    stdout = tmp;
    scope(exit) stdout = saved;
    import darkcommand.help : printHelp;
    printHelp(new LongDescApp());
    stdout.flush();
    tmp.seek(0);
    string content; char[] line;
    while (tmp.readln(line)) content ~= line;
    assert(content.indexOf("First paragraph.") >= 0, content);
    assert(content.indexOf("Short summary.") < content.indexOf("First paragraph."), content);
}

unittest { // help: subcommand description shown
    import std.stdio : stdout, File;
    import std.string : indexOf;
    auto app = new LongDescSubApp();
    auto sub = cast(LongDescSubCmd) app.parseOnly(["app", "sub"]);
    auto tmp = File.tmpfile();
    auto saved = stdout;
    stdout = tmp;
    scope(exit) stdout = saved;
    import darkcommand.help : printHelp;
    printHelp(sub);
    stdout.flush();
    tmp.seek(0);
    string content; char[] line;
    while (tmp.readln(line)) content ~= line;
    assert(content.indexOf("Sub long description.") >= 0, content);
}

unittest { // markdown: description appears after summary
    import darkcommand.docs.markdown : generateMarkdownDocs;
    import std.stdio : File;
    import std.string : indexOf;
    auto tmp = File.tmpfile();
    new LongDescApp().generateMarkdownDocs(tmp);
    tmp.flush(); tmp.seek(0);
    string content; char[] line;
    while (tmp.readln(line)) content ~= line;
    assert(content.indexOf("First paragraph.") >= 0, content);
    assert(content.indexOf("Short summary.") < content.indexOf("First paragraph."), content);
}

unittest { // markdown: subcommand description appears in its section
    import darkcommand.docs.markdown : generateMarkdownDocs;
    import std.stdio : File;
    import std.string : indexOf;
    auto tmp = File.tmpfile();
    new LongDescSubApp().generateMarkdownDocs(tmp);
    tmp.flush(); tmp.seek(0);
    string content; char[] line;
    while (tmp.readln(line)) content ~= line;
    assert(content.indexOf("Sub long description.") >= 0, content);
}

// ── validateEachWith on T[] is a compile-time error ───────────────────────────

// validateEachWith on a T[] (repeating) field used to silently become a no-op
// because DelegateValidator!(T[]) tried raw.to!(T[]) per token, always threw
// ConvException, and was swallowed.  A static assert now prevents misuse.
static assert(!__traits(compiles, {
    import darkcommand.entry : EntrySpec, EntryBuilder;
    auto spec = new EntrySpec();
    string[] arr;
    auto b = new EntryBuilder!(string[])(spec, &arr);
    b.validateEachWith((string[] v) => v.length > 0, "msg");
}));

// ── Bash completion: shell-special chars in acceptsValues escaped ──────────────

class EscapeValApp : Program {
    string fmt;
    this() {
        super("app", "1.0.0");
        this.addOption!(fmt)("f", "format", "Format")
            .acceptsValues(["a\"b", `c\d`]);  // " and \ need escaping in bash
    }
    override protected void setup() {}
}

unittest { // bash completion: double-quote in enum value is escaped as \"
    import darkcommand.completion.bash : generateBashCompletion;
    import std.stdio : File;
    import std.string : indexOf;
    auto tmp = File.tmpfile();
    new EscapeValApp().generateBashCompletion(tmp);
    tmp.flush(); tmp.seek(0);
    string content; char[] line;
    while (tmp.readln(line)) content ~= line;
    assert(content.indexOf(`a\"b`) >= 0, content);   // escaped form present
}

unittest { // bash completion: backslash in enum value is escaped as \\
    import darkcommand.completion.bash : generateBashCompletion;
    import std.stdio : File;
    import std.string : indexOf;
    auto tmp = File.tmpfile();
    new EscapeValApp().generateBashCompletion(tmp);
    tmp.flush(); tmp.seek(0);
    string content; char[] line;
    while (tmp.readln(line)) content ~= line;
    assert(content.indexOf(`c\\d`) >= 0, content);   // escaped form present
}

// ── Word-wrapping in help output ─────────────────────────────────────────────

class WrapDescApp : Program {
    this() {
        super("app", "1.0.0");
        description(
            "This is a deliberately long paragraph that exceeds eighty columns "
          ~ "and should be automatically wrapped by the help renderer.\n\n"
          ~ "Second paragraph is also deliberately longer than eighty characters "
          ~ "to ensure wrapping is applied uniformly.");
    }
    override protected void setup() {}
}

unittest { // help: description is word-wrapped; no line exceeds 80 chars
    import std.stdio  : stdout, File;
    import std.string : splitLines;
    auto tmp = File.tmpfile();
    auto saved = stdout;
    stdout = tmp;
    scope(exit) stdout = saved;
    import darkcommand.help : printHelp;
    printHelp(new WrapDescApp());
    stdout.flush();
    tmp.seek(0);
    string content; char[] line;
    while (tmp.readln(line)) content ~= line;
    foreach (l; splitLines(content))
        assert(l.length <= 80, "line too long: " ~ l);
}

// ── Markdown docs: --help and --version entries ───────────────────────────────

unittest { // markdown docs: --help always appears in options table
    import darkcommand.docs.markdown : generateMarkdownDocs;
    import std.stdio : File;
    import std.string : indexOf;
    auto tmp = File.tmpfile();
    new ArgOnlyApp().generateMarkdownDocs(tmp);   // has no user-defined options
    tmp.flush(); tmp.seek(0);
    string content; char[] line;
    while (tmp.readln(line)) content ~= line;
    assert(content.indexOf("--help") >= 0, content);
}

unittest { // markdown docs: --version appears for Program with auto-version
    import darkcommand.docs.markdown : generateMarkdownDocs;
    import std.stdio : File;
    import std.string : indexOf;
    auto tmp = File.tmpfile();
    new BoolFlagApp().generateMarkdownDocs(tmp);
    tmp.flush(); tmp.seek(0);
    string content; char[] line;
    while (tmp.readln(line)) content ~= line;
    assert(content.indexOf("--version") >= 0, content);
}
