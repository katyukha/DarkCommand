# Dark Command

[![Tests](https://github.com/katyukha/darkcommand/actions/workflows/ci.yml/badge.svg)](https://github.com/katyukha/darkcommand/actions/workflows/ci.yml)

> **Alpha:** This library is in early development. The API may change between releases.

Subclass-based CLI argument parsing for D.

The idea is to implement each command as a separate class — command definition, option spec, parsed values, and implementation all live in one place.
No callbacks, no string-key lookups, no result objects.

## Quick start

```d
import darkcommand;
import std.stdio : writefln;

class BuildCmd : Command {
    string target;
    int    jobs;
    bool   release_;

    this() {
        super("build", "Build the project");
        this.addArgument!(target)  ("target",  "Build target");
        this.addOption!  (jobs)    ("j", "jobs",    "Parallel jobs").defaultValue(4);
        this.addFlag!    (release_)(null, "release", "Release build");
    }

    override int execute() {
        writefln("Building %s with %d jobs (release=%s)", target, jobs, release_);
        return 0;
    }
}

class MyApp : Program {
    bool verbose;

    this() {
        super("myapp", "1.0.0");
        summary("My build tool.");
        this.addFlag!(verbose)("v", "verbose", "Verbose output");
        add(new BuildCmd());
    }

    override protected void setup() {
        // verbose is already populated here
    }
}

int main(string[] args) {
    return new MyApp().run(args);
}
```

```
$ myapp build src --jobs 8 --release
Building src with 8 jobs (release=true)
```

## Field type → semantics

| Field type | Registration | Behaviour |
|---|---|---|
| `bool` | `addFlag` | `true` if flag present |
| `int` | `addFlag` | occurrence count: `-vvv` → 3 |
| `T` | `addOption` / `addArgument` | required; `std.conv.to!T`; error if absent |
| `T` + `.defaultValue(x)` | `addOption` / `addArgument` | optional with default |
| `Nullable!T` | `addOption` / `addArgument` | optional; `.isNull` if not provided |
| `T[]` (Option) | `addOption` | zero or more; accumulated |
| `T[]` (Argument) | `addArgument` | zero or more; empty if absent |
| `T[]` + `.required()` | `addOption` / `addArgument` | one or more; error if absent |

`T` can be any type that `std.conv.to!T` can construct from a `string` — including custom structs with a `this(string)` constructor. For example, `thepath.Path` works directly as a field type with no extra registration:

```d
import thepath : Path;

class MyCmd : Program {
    Path output;
    Path[] inputs;
    this() {
        super("mytool", "1.0.0");
        this.addOption!  (output)("o", "output", "Output path");
        this.addArgument!(inputs)("inputs",       "Input paths");
    }
    override protected void setup() {}
}
// mytool --output out/result.txt a.txt b.txt
// → output == Path("out/result.txt"), inputs == [Path("a.txt"), Path("b.txt")]
```

## Fluent builder

```d
this.addOption!(format)("f", "format", "Output format")
    .acceptsValues(["json", "csv", "text"])   // validated enum
    .defaultValue("json");

this.addArgument!(inputFile)("input", "Input file")
    .acceptsFiles();                           // validates existence (file) + completion hint

this.addArgument!(source)("source", "File or directory")
    .acceptsPath();                            // validates existence (file or directory) + completion hint

this.addOption!(count)("n", "count", "Count")
    .validateEachWith(v => v > 0, "must be positive");

this.addArgument!(files)("files", "Input files")
    .required();                               // one or more (default is zero or more)
```

## Subcommands and parent access

```d
class DbCmd : Command {
    string host;
    this() {
        super("db", "Database management");
        this.addOption!(host)("H", "host", "DB host").defaultValue("localhost");
        add(new CreateCmd());
    }
}

class CreateCmd : Command {
    string name;
    this() {
        super("create", "Create a database");
        this.addArgument!(name)("name", "Database name");
    }
    override int execute() {
        string host = parent!DbCmd.host;   // typed, runtime-checked
        // ...
        return 0;
    }
}
```

## Lifecycle hooks

```d
class DeployCmd : Command {
    string target;
    string resolvedConfig;    // derived in afterParse

    this() {
        super("deploy", "Deploy");
        this.addOption!(target)("t", "target", "Target env");
    }

    override protected void afterParse() {
        resolvedConfig = lookupConfig(target);
    }

    override protected void validate() {
        if (target == "prod" && !confirmProd())
            throw new DarkCommandException("prod deploy requires confirmation");
    }

    override int execute() {
        deploy(target, resolvedConfig);
        return 0;
    }
}
```

Lifecycle order: parse → `setup()` (Program only) → `afterParse()` → `validate()` → `execute()` (leaf).

## Topic groups, default command, argsRest

```d
this() {
    super("myapp", "1.0.0");

    topicGroup("Server")
        .add(new StartCmd())
        .add(new StopCmd());

    topicGroup("Database")
        .add(new DbCmd());

    add(new HelpCmd());          // ungrouped

    defaultCommand("start");     // `myapp` with no subcommand → runs StartCmd
}
```

`argsRest` is auto-populated with everything after `--`:
```d
// myapp run -- --port 8080 --reload
// argsRest == ["--port", "8080", "--reload"]
```

## Error handling

```d
class MyApp : Program {
    override protected int onError(Exception e) {
        import std.logger : criticalf;
        criticalf("Error: %s", e.msg);
        return 1;
    }
}
```

`exitWith(code, msg)` in any command throws `DarkCommandExitException`, caught by `run()`:
```d
override int execute() {
    if (!dbExists(name))
        exitWith(1, "Database does not exist: " ~ name);
    return 0;
}
```

## Bash completion, Markdown, and JSON docs

```d
// In a separate dub configuration entry point:
import std.stdio : stdout;
new MyApp().generateBashCompletion(stdout);   // source the output in ~/.bashrc
new MyApp().generateMarkdownDocs(stdout);     // pipe to docs/reference.md

import darkcommand.docs.json : generateJSONDocs, commandTreeToJSON;
new MyApp().generateJSONDocs(stdout);         // machine-readable command tree
auto tree = commandTreeToJSON(new MyApp());   // or get the JSONValue to embed
```

The JSON export is a drift-free dump of the live command tree (commands,
options, flags, arguments, shortcuts) for agent tooling, scripts, and IDEs. It
emits only declared entries — the universal `--help`/`--version` are omitted.

## Testing commands in isolation

```d
// parseOnly parses + validates without calling setup() or execute()
unittest {
    auto app = new MyApp();
    auto leaf = app.parseOnly(["myapp", "build", "src", "--release"]);
    auto cmd  = cast(BuildCmd) leaf;
    assert(cmd !is null);
    assert(cmd.target   == "src");
    assert(cmd.release_ == true);
    assert(cmd.jobs     == 4);   // default
}
```

## License

MPL-2.0 — see `LICENSE`.
