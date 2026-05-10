module integration.main;

import darkcommand;
import darkcommand.completion.bash : generateBashCompletion;
import thepath : Path, withTempDir;
import theprocess : Process;
import std.stdio : File, writeln;
import std.string : splitLines, strip, indexOf;
import std.algorithm : canFind, sort, map, filter;
import std.array : array;

// ── Fixtures ──────────────────────────────────────────────────────────────────

class CliApp : Program {
    int  verbosity;
    bool quiet;
    string format;
    string output;
    string[] files;

    this() {
        super("app", "1.0.0");
        summary("Integration test app.");
        this.addFlag!  (verbosity)("v", "verbose", "Increase verbosity");
        this.addFlag!  (quiet)    ("q", "quiet",   "Suppress output");
        this.addOption!(format)   ("f", "format",  "Output format")
            .acceptsValues(["json", "csv", "text"]);
        this.addOption!(output)   ("o", "output",  "Output file")
            .completesAsFile();
        this.addArgument!(files)  ("files", "Input files")
            .acceptsFiles();

        topicGroup("Data")
            .add(new ImportCmd())
            .add(new ExportCmd());
        add(new StatusCmd());
    }

    override protected void setup() {}
}

class ImportCmd : Command {
    string source;
    this() {
        super("import", "Import data");
        this.addArgument!(source)("source", "Source file").acceptsFiles();
    }
    override int execute() { return 0; }
}

class ExportCmd : Command {
    string dest;
    this() {
        super("export", "Export data");
        this.addOption!(dest)("d", "dest", "Destination").completesAsFile();
    }
    override int execute() { return 0; }
}

class StatusCmd : Command {
    this() { super("status", "Show status"); }
    override int execute() { return 0; }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

// Write completion script to tmp, return the path.
Path writeCompletion(Path tmp, Program prog) {
    auto p = tmp.join("completion.bash");
    auto f = File(p.toString, "w");
    prog.generateBashCompletion(f);
    f.close();
    return p;
}

// Write a bash driver that sources the completion script, sets COMP_WORDS /
// COMP_CWORD, calls the completion function, and prints COMPREPLY one per line.
// `words` is the full token list including the program name; the last element
// is what the user is currently typing (the "cur" word).
Path writeDriver(Path tmp, Path completion, string fnName, string[] words) {
    import std.format : format;
    import std.array  : join;

    string wordArray = `("` ~ words.join(`" "`) ~ `")`;
    string script = `#!/usr/bin/env bash
source "` ~ completion.toString ~ `"
COMP_WORDS=` ~ wordArray ~ `
COMP_CWORD=` ~ format("%d", words.length - 1) ~ `
COMPREPLY=()
` ~ fnName ~ `
printf '%s\n' "${COMPREPLY[@]}"
`;
    auto p = tmp.join("driver.bash");
    p.writeFile(script);
    return p;
}

// Run the driver, return sorted completion candidates.
string[] complete(Path driver) {
    auto result = Process("bash").withArgs(driver.toString).execute();
    assert(result.isOk, "bash driver failed: " ~ result.output);
    return result.output.splitLines
        .map!(l => l.strip)
        .filter!(l => l.length > 0)
        .array
        .sort
        .array;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void testFlagsAtRoot() {
    writeln("  flags and options appear at root level");
    withTempDir((Path tmp) {
        auto comp = writeCompletion(tmp, new CliApp());
        auto driver = writeDriver(tmp, comp, "__app_root", ["app", "-"]);
        auto got = complete(driver);
        assert(got.canFind("-v"),       "-v missing");
        assert(got.canFind("-q"),       "-q missing");
        assert(got.canFind("--verbose"),"--verbose missing");
        assert(got.canFind("--quiet"),  "--quiet missing");
        assert(got.canFind("--help"),   "--help missing");
        assert(got.canFind("--version"),"--version missing");
    });
}

void testSubcommandsAtRoot() {
    writeln("  subcommand names appear at root level");
    withTempDir((Path tmp) {
        auto comp = writeCompletion(tmp, new CliApp());
        auto driver = writeDriver(tmp, comp, "__app_root", ["app", ""]);
        auto got = complete(driver);
        assert(got.canFind("import"), "import missing");
        assert(got.canFind("export"), "export missing");
        assert(got.canFind("status"), "status missing");
    });
}

void testEnumOption() {
    writeln("  enum values offered after --format");
    withTempDir((Path tmp) {
        auto comp = writeCompletion(tmp, new CliApp());
        auto driver = writeDriver(tmp, comp, "__app_root", ["app", "--format", ""]);
        auto got = complete(driver);
        assert(got.canFind("json"), "json missing");
        assert(got.canFind("csv"),  "csv missing");
        assert(got.canFind("text"), "text missing");
    });
}

void testFileArgCompletion() {
    writeln("  file argument completion returns actual files");
    withTempDir((Path tmp) {
        // Create test files in temp dir.
        tmp.join("alpha.txt").writeFile("a");
        tmp.join("beta.txt").writeFile("b");
        tmp.join("gamma.txt").writeFile("g");

        auto comp = writeCompletion(tmp, new CliApp());

        // Run driver with working directory set to tmp so compgen -f sees the files.
        import std.format : format;
        string script = `#!/usr/bin/env bash
cd "` ~ tmp.toString ~ `"
source "` ~ comp.toString ~ `"
COMP_WORDS=("app" "")
COMP_CWORD=1
COMPREPLY=()
__app_root
printf '%s\n' "${COMPREPLY[@]}"
`;
        auto driver = tmp.join("driver_files.bash");
        driver.writeFile(script);

        auto result = Process("bash").withArgs(driver.toString).execute();
        assert(result.isOk, "bash driver failed: " ~ result.output);
        auto got = result.output.splitLines.map!(l => l.strip).filter!(l => l.length > 0).array;
        assert(got.canFind("alpha.txt"), "alpha.txt missing from completions");
        assert(got.canFind("beta.txt"),  "beta.txt missing from completions");
    });
}

void testSubcommandDispatch() {
    writeln("  dispatch routes to subcommand completion function");
    withTempDir((Path tmp) {
        auto comp = writeCompletion(tmp, new CliApp());

        // After typing "app import <TAB>" we should get file completion offered.
        // We test that the import subcommand function exists and is callable.
        string script = `#!/usr/bin/env bash
source "` ~ comp.toString ~ `"
COMP_WORDS=("app" "import" "")
COMP_CWORD=2
COMPREPLY=()
__app_dispatch import
printf '%s\n' "${COMPREPLY[@]}"
`;
        auto driver = tmp.join("driver_dispatch.bash");
        driver.writeFile(script);

        auto result = Process("bash").withArgs(driver.toString).execute();
        assert(result.isOk, "dispatch driver failed: " ~ result.output);
        // --help must appear (always in word list)
        auto got = result.output.splitLines.map!(l => l.strip).filter!(l => l.length > 0).array;
        assert(got.canFind("--help"), "--help missing in import subcommand");
    });
}

// ── thepath.Path integration ──────────────────────────────────────────────────
//
// thepath.Path has a this(string) constructor, so std.conv.to!Path(str) works.
// No special registration is needed — any such type works as an option or
// argument field in darkcommand.

class PathOptApp : Program {
    Path output;
    Path[] inputs;
    this() {
        super("app", "1.0.0");
        this.addOption!  (output)("o", "output", "Output path");
        this.addArgument!(inputs)("inputs", "Input paths");
    }
    override protected void setup() {}
}

class NullablePathApp : Program {
    import std.typecons : Nullable;
    Nullable!Path output;
    this() {
        super("app", "1.0.0");
        this.addOption!(output)("o", "output", "Output path");
    }
    override protected void setup() {}
}

void testPathType() {
    writeln("  thepath.Path fields parsed via std.conv.to!Path");
    auto app = new PathOptApp();
    app.parseOnly(["app", "--output", "out/result.txt", "a.txt", "b.txt"]);
    assert(app.output  == Path("out/result.txt"), "output path mismatch");
    assert(app.inputs.length == 2,                "expected 2 inputs");
    assert(app.inputs[0] == Path("a.txt"),        "first input mismatch");
    assert(app.inputs[1] == Path("b.txt"),        "second input mismatch");

    writeln("  Nullable!Path: absent → isNull, present → Path value");
    auto napp = new NullablePathApp();
    napp.parseOnly(["app"]);
    assert(napp.output.isNull, "expected isNull when not provided");

    napp = new NullablePathApp();
    napp.parseOnly(["app", "--output", "out/file.txt"]);
    assert(!napp.output.isNull,                   "expected non-null when provided");
    assert(napp.output.get == Path("out/file.txt"), "Nullable!Path value mismatch");
}

// ── Entry point ───────────────────────────────────────────────────────────────

int main() {
    import std.stdio : writefln;

    version (Posix) {
        writeln("Running bash completion integration tests...");
        testFlagsAtRoot();
        testSubcommandsAtRoot();
        testEnumOption();
        testFileArgCompletion();
        testSubcommandDispatch();
        writeln("All integration tests passed.");
        writeln("Running thepath integration tests...");
        testPathType();
        writeln("All integration tests passed.");
        return 0;
    } else {
        writeln("Bash integration tests skipped (Posix only).");
        return 0;
    }
}
