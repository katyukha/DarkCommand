module darkcommand.help;

private import darkcommand.command;
private import darkcommand.entry;
private import darkcommand.ansi;

void printHelp(Command cmd) {
    _printHelp(cmd, _colorEnabled());
}

package(darkcommand) void printHelpColored(Command cmd) {
    _printHelp(cmd, true);
}

private void _printHelp(Command cmd, bool color) {
    import std.stdio : write, writeln, writefln;
    import std.array : replicate, join;

    // Usage line
    bool hasArguments = false;
    foreach (e; cmd._entries)
        if (e.kind == EntrySpec.Kind.argument) hasArguments = true;

    if (cmd.summary.length > 0)
        writeln(cmd.summary);

    if (cmd.description.length > 0) {
        writeln();
        write(_dim(_wrapText(cmd.description), color));
    }

    writeln();
    writeln(_bold("Usage", color));
    write("  " ~ _dim("$", color) ~ " ");
    _writeBreadcrumb(cmd);
    write(" " ~ _dim("[options]", color));
    foreach (e; cmd._entries)
        if (e.kind == EntrySpec.Kind.argument)
            write(" " ~ _dim("<" ~ e.displayName ~ ">", color));
    if (cmd._subcommands.length > 0) write(" " ~ _dim("<command>", color));
    writeln();

    // Options — always shown; at minimum -h/--help (and --version for Programs).
    writeln();
    writeln(_bold("Options", color));
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
        string valueTag = e.isFlag() ? "" :
            " <" ~ (e.longName.length ? e.longName : "value") ~ ">";
        size_t visualWidth = names.length + valueTag.length;
        size_t pad = visualWidth < 28 ? 28 - visualWidth : 0;
        writeln(names, _underline(valueTag, color), replicate(" ", pad), "  ", _dim(e.desc, color));
    }
    {
        enum hnames = "  -h, --help";
        writeln(hnames, replicate(" ", 28 - hnames.length), "  ", _dim("Show this help", color));
    }
    if (auto prog = cast(Program) cmd) {
        if (!prog._noAutoVersion) {
            enum vnames = "      --version";
            writeln(vnames, replicate(" ", 28 - vnames.length), "  ", _dim("Show version", color));
        }
    }

    // Arguments
    if (hasArguments) {
        writeln();
        writeln(_bold("Arguments", color));
        foreach (e; cmd._entries) {
            if (e.kind != EntrySpec.Kind.argument) continue;
            size_t pad = e.displayName.length < 26 ? 26 - e.displayName.length : 0;
            writeln("  ", e.displayName, replicate(" ", pad), "  ", _dim(e.desc, color));
        }
    }

    // Subcommands grouped
    if (cmd._subcommands.length > 0) {
        string[] groupOrder;
        string[][string] grouped;
        bool[] usedGrouped;
        usedGrouped.length = cmd._subcommands.length;

        foreach (i, sub; cmd._subcommands) {
            string g = cmd._subcommandGroups[i];
            if (g.length == 0) continue;
            if ((g in grouped) is null) groupOrder ~= g;
            grouped[g] ~= sub.name;
            usedGrouped[i] = true;
        }

        string[] ungrouped;
        foreach (i, sub; cmd._subcommands)
            if (!usedGrouped[i]) ungrouped ~= sub.name;

        writeln();
        writeln(_bold("Commands", color));
        foreach (g; groupOrder) {
            writeln();
            writeln("  ", _underline(g ~ ":", color));
            foreach (n; grouped[g]) {
                Command sub = cmd._findSubcommand(n);
                writefln("    %-24s  %s", n, _dim(sub ? sub.summary : "", color));
            }
        }
        if (ungrouped.length > 0) {
            if (groupOrder.length > 0) writeln();
            foreach (n; ungrouped) {
                Command sub = cmd._findSubcommand(n);
                writefln("  %-26s  %s", n, _dim(sub ? sub.summary : "", color));
            }
        }
    }

    if (auto prog = cast(Program) cmd) {
        if (prog._shortcuts.length > 0) {
            writeln();
            writeln(_bold("Shortcuts", color));
            foreach (s; prog._shortcuts) {
                string right = s.expansion.join(" ");
                if (s.summary.length)
                    right ~= " — " ~ _dim(s.summary, color);
                writefln("  %-26s  %s", s.name, right);
            }
        }
    }
}

// Wraps text at `width` columns, preserving blank lines as paragraph breaks.
// Words longer than `width` are placed on their own line without splitting.
private string _wrapText(string text, int width = 78) {
    import std.array  : appender;
    import std.string : splitLines, split;

    auto result = appender!string;
    foreach (para; splitLines(text)) {
        if (para.length == 0) {
            result ~= "\n";
            continue;
        }
        int col = 0;
        foreach (word; para.split(" ")) {
            if (word.length == 0) continue;
            int wlen = cast(int) word.length;
            if (col == 0) {
                result ~= word;
                col = wlen;
            } else if (col + 1 + wlen <= width) {
                result ~= " ";
                result ~= word;
                col += 1 + wlen;
            } else {
                result ~= "\n";
                result ~= word;
                col = wlen;
            }
        }
        result ~= "\n";
    }
    return result.data;
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
