module darkcommand.help;

import darkcommand.command;
import darkcommand.entry;

// Returns true when color output should be suppressed (NO_COLOR env var set,
// per https://no-color.org).  Colors are not yet used in Phase 1; this flag is
// the hook for Phase 2+ formatting enhancements.
bool noColor() {
    import std.process : environment;
    return environment.get("NO_COLOR", "").length > 0;
}

void printHelp(Command cmd) {
    import std.stdio : write, writeln, writef, writefln;
    import std.algorithm : map, maxElement;
    import std.array : array;

    // Usage line
    bool hasOptions   = false;
    bool hasArguments = false;
    foreach (e; cmd._entries) {
        if (e.kind == EntrySpec.Kind.argument) hasArguments = true;
        else                                    hasOptions   = true;
    }

    write("Usage: ");
    _writeBreadcrumb(cmd);
    if (hasOptions)   write(" [options]");
    foreach (e; cmd._entries)
        if (e.kind == EntrySpec.Kind.argument)
            write(" <" ~ e.displayName ~ ">");
    if (cmd._subcommands.length > 0) write(" <command>");
    writeln();

    if (cmd.summary.length > 0) {
        writeln();
        writeln(cmd.summary);
    }

    // Options / Flags
    if (hasOptions) {
        writeln();
        writeln("Options:");
        foreach (e; cmd._entries) {
            if (e.kind == EntrySpec.Kind.argument) continue;
            string longPart = e.negatable
                ? "--[no-]" ~ e.longName
                : "--" ~ e.longName;
            string names;
            if (e.shortName.length && e.longName.length)
                names = "  -" ~ e.shortName ~ ", " ~ longPart;
            else if (e.shortName.length)
                names = "  -" ~ e.shortName;
            else
                names = "      " ~ longPart;
            writefln("%-28s  %s", names, e.desc);
        }
        writefln("%-28s  %s", "  -h, --help", "Show this help");
    }

    // Arguments
    if (hasArguments) {
        writeln();
        writeln("Arguments:");
        foreach (e; cmd._entries) {
            if (e.kind != EntrySpec.Kind.argument) continue;
            writefln("  %-26s  %s", e.displayName, e.desc);
        }
    }

    // Subcommands grouped
    if (cmd._subcommands.length > 0) {
        // Collect groups
        string[] groupOrder;
        string[][string] grouped;
        bool[]  usedGrouped;
        usedGrouped.length = cmd._subcommands.length;

        foreach (i, sub; cmd._subcommands) {
            string g = cmd._subcommandGroups[i];
            if (g.length == 0) continue;
            if ((g in grouped) is null) groupOrder ~= g;
            grouped[g] ~= sub.name;
            usedGrouped[i] = true;
        }

        // Ungrouped
        string[] ungrouped;
        foreach (i, sub; cmd._subcommands)
            if (!usedGrouped[i]) ungrouped ~= sub.name;

        foreach (g; groupOrder) {
            writeln();
            writeln(g ~ ":");
            foreach (n; grouped[g]) {
                Command sub = cmd._findSubcommand(n);
                writefln("  %-26s  %s", n, sub ? sub.summary : "");
            }
        }
        if (ungrouped.length > 0) {
            writeln();
            writeln("Commands:");
            foreach (n; ungrouped) {
                Command sub = cmd._findSubcommand(n);
                writefln("  %-26s  %s", n, sub ? sub.summary : "");
            }
        }
    }
}

private void _writeBreadcrumb(Command cmd) {
    import std.stdio : write;
    if (cmd._parent !is null) {
        _writeBreadcrumb(cmd._parent);
        write(" " ~ cmd.name);
    } else {
        write(cmd.name);
    }
}

