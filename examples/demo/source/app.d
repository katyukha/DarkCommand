module app;

import darkcommand;
import std.stdio : writeln, writefln;
import std.typecons : Nullable;

// ── Program ───────────────────────────────────────────────────────────────────
//
// Demonstrates:
//   int flag (occurrence count), bool flag, negatable bool flag,
//   topicGroup, setup() hook, onError() hook, exitWith()

class DevTool : Program {
    int  verbosity;   // int Flag: -v → 1, -vv → 2, -vvv → 3
    bool quiet;
    bool color;
    bool genCompletion;  // --generate-completion: write bash completion to stdout
    bool genDocs;        // --generate-docs: write Markdown reference to stdout

    this() {
        super("devtool", "1.0.0");
        summary("A sample app demonstrating darkcommand features.");

        this.addFlag!(verbosity)    ("v", "verbose",             "Increase verbosity (stackable: -vvv)");
        this.addFlag!(quiet)        ("q", "quiet",               "Suppress non-error output");
        this.addFlag!(color)        (null, "color",               "Colorize output").negatable();
        this.addFlag!(genCompletion)(null, "generate-completion", "Print bash completion script and exit");
        this.addFlag!(genDocs)      (null, "generate-docs",       "Print Markdown command reference and exit");

        topicGroup("Build")
            .add(new BuildCmd())
            .add(new TestCmd())
            .add(new CleanCmd());

        topicGroup("Server")
            .add(new ServerCmd());
    }

    override protected void setup() {
        import std.stdio : stdout;

        // Self-documentation flags bypass normal subcommand dispatch.
        if (genCompletion) {
            generateBashCompletion(stdout);
            exitWith(0);
        }
        if (genDocs) {
            generateMarkdownDocs(stdout);
            exitWith(0);
        }

        // setup() runs after program-level args are parsed, before subcommand dispatch.
        if (quiet && verbosity > 0)
            exitWith(1, "error: --quiet and --verbose are mutually exclusive");
    }

    override protected int onError(Exception e) {
        import std.stdio : stderr;
        stderr.writefln("devtool: %s", e.msg);
        return 1;
    }
}

// ── build ─────────────────────────────────────────────────────────────────────
//
// Demonstrates:
//   required positional argument, int option with defaultValue,
//   negatable bool flag, parent!T() access, argsRest (forwarded via --)

class BuildCmd : Command {
    string target;
    int    jobs;
    bool   release_;

    this() {
        super("build", "Build the project");
        this.addArgument!(target)  ("target",  "Build target");
        this.addOption!  (jobs)    ("j", "jobs",    "Parallel jobs").defaultValue(4);
        this.addFlag!    (release_)(null, "release", "Release build").negatable();
    }

    override int execute() {
        DevTool prog = parent!DevTool;

        if (prog.verbosity > 0)
            writefln("[verbose=%d] target=%s jobs=%d release=%s",
                     prog.verbosity, target, jobs, release_);

        writefln("Building '%s' with %d job(s)%s",
            target, jobs, release_ ? " [release]" : "");

        // argsRest holds everything after -- on the command line:
        //   devtool build myproject -- --extra-flag value
        if (argsRest.length)
            writefln("Forwarding to build system: %-(%s %)", argsRest);

        return 0;
    }
}

// ── test ──────────────────────────────────────────────────────────────────────
//
// Demonstrates:
//   repeating option (string[]), Nullable option

class TestCmd : Command {
    string[]        patterns;  // repeating: --pattern a --pattern b → ["a", "b"]
    Nullable!string filter;    // optional: .isNull when not provided

    this() {
        super("test", "Run the test suite");
        this.addOption!(patterns)("p", "pattern", "Test pattern (repeatable)");
        this.addOption!(filter)  ("f", "filter",  "Substring filter on test names");
    }

    override int execute() {
        if (patterns.length)
            writefln("Running patterns: %-(%s, %)", patterns);
        else
            writeln("Running all tests");

        if (!filter.isNull)
            writefln("Filtering by: %s", filter.get);

        return 0;
    }
}

// ── clean ─────────────────────────────────────────────────────────────────────

class CleanCmd : Command {
    bool all;

    this() {
        super("clean", "Remove build artifacts");
        this.addFlag!(all)(null, "all", "Remove caches and intermediates too");
    }

    override int execute() {
        writeln(all ? "Cleaning everything (including caches)" : "Cleaning build artifacts");
        return 0;
    }
}

// ── server ────────────────────────────────────────────────────────────────────
//
// Demonstrates:
//   nested subcommands, defaultCommand, parent!T() up one level,
//   afterParse(), validate_(), negatable flag on a leaf command

class ServerCmd : Command {
    string host;

    this() {
        super("server", "Manage the dev server");
        this.addOption!(host)(null, "host", "Bind address").defaultValue("127.0.0.1");
        add(new StartCmd());
        add(new StopCmd());
        defaultCommand("start");  // devtool server  →  devtool server start
    }
}

class StartCmd : Command {
    int  port;
    bool watch;
    string resolvedAddr;  // derived in afterParse

    this() {
        super("start", "Start the dev server");
        this.addOption!(port) ("p", "port",  "Port number").defaultValue(8080);
        this.addFlag!  (watch)(null, "watch", "Reload on file changes").negatable();
    }

    override protected void afterParse() {
        import std.format : format;
        resolvedAddr = format("%s:%d", parent!ServerCmd.host, port);
    }

    override protected void validate_() {
        if (port < 1 || port > 65535)
            throw new DarkCommandException("--port must be between 1 and 65535");
    }

    override int execute() {
        writefln("Starting dev server on %s%s",
            resolvedAddr, watch ? " (watching for changes)" : "");
        return 0;
    }
}

class StopCmd : Command {
    bool force;

    this() {
        super("stop", "Stop the dev server");
        this.addFlag!(force)(null, "force", "Kill without graceful shutdown");
    }

    override int execute() {
        string host = parent!ServerCmd.host;
        writefln("Stopping dev server on %s%s", host, force ? " (forced)" : "");
        return 0;
    }
}

// ── entry point ───────────────────────────────────────────────────────────────

int main(string[] args) {
    return new DevTool().run(args);
}
