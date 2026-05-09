module darkcommand.docs.markdown;

private import darkcommand.command;
private import darkcommand.entry;
private import std.stdio : File;

// Writes a Markdown command reference for `prog` to `output`.
// Each command and subcommand gets its own section at increasing heading depth.
void generateMarkdownDocs(Program prog, File output) {
    _writeSection(output, cast(Command) prog, 1, "");
}

// ── Private ───────────────────────────────────────────────────────────────────

private void _writeSection(File f, Command cmd, int depth, string breadcrumb) {
    import std.array : replicate;

    immutable fullName = breadcrumb.length ? breadcrumb ~ " " ~ cmd.name : cmd.name;
    immutable heading  = replicate("#", depth);

    f.writeln(heading ~ " " ~ fullName);
    f.writeln();

    if (cmd.summary.length) {
        f.writeln(cmd.summary);
        f.writeln();
    }
    if (cmd.description.length) {
        f.writeln(cmd.description);
        f.writeln();
    }

    // Usage line
    f.writeln("**Usage:**");
    f.writeln();
    f.writeln("```");
    _writeUsageLine(f, cmd, fullName);
    f.writeln("```");

    // Options table — always emitted; at minimum --help is always available.
    f.writeln();
    f.writeln("**Options:**");
    f.writeln();
    f.writeln("| Flag | Description |");
    f.writeln("|------|-------------|");
    foreach (e; cmd._entries) {
        if (e.kind == EntrySpec.Kind.argument) continue;
        string names;
        if (e.shortName.length && e.longName.length)
            names = "`-" ~ e.shortName ~ "`, `--" ~ e.longName ~ "`";
        else if (e.shortName.length)
            names = "`-" ~ e.shortName ~ "`";
        else
            names = "`--" ~ e.longName ~ "`";
        f.writefln("| %s | %s |", names, _escapeMdCell(e.desc));
    }
    f.writefln("| %s | %s |", "`-h`, `--help`", "Show this help");
    if (auto prog = cast(Program) cmd) {
        if (!prog._noAutoVersion)
            f.writefln("| %s | %s |", "`--version`", "Show version");
    }

    // Arguments table
    bool hasArgs = false;
    foreach (e; cmd._entries) if (e.kind == EntrySpec.Kind.argument) { hasArgs = true; break; }
    if (hasArgs) {
        f.writeln();
        f.writeln("**Arguments:**");
        f.writeln();
        f.writeln("| Name | Description |");
        f.writeln("|------|-------------|");
        foreach (e; cmd._entries)
            if (e.kind == EntrySpec.Kind.argument)
                f.writefln("| `%s` | %s |", e.displayName, _escapeMdCell(e.desc));
    }

    // Shortcuts table (Program only)
    if (auto prog = cast(Program) cmd) {
        if (prog._shortcuts.length > 0) {
            import std.array : join;
            f.writeln();
            f.writeln("**Shortcuts:**");
            f.writeln();
            f.writeln("| Name | Expands to | Description |");
            f.writeln("|------|------------|-------------|");
            foreach (s; prog._shortcuts)
                f.writefln("| `%s` | `%s` | %s |",
                    s.name, s.expansion.join(" "), _escapeMdCell(s.summary));
        }
    }

    // Subcommand index
    if (cmd._subcommands.length > 0) {
        f.writeln();
        f.writeln("**Commands:**");
        f.writeln();
        foreach (sub; cmd._subcommands)
            f.writefln("- [`%s`](#%s) — %s",
                       sub.name, _anchor(fullName ~ " " ~ sub.name), sub.summary);
        f.writeln();

        // Recurse into each subcommand
        foreach (sub; cmd._subcommands)
            _writeSection(f, sub, depth + 1, fullName);
    }
}

private void _writeUsageLine(File f, Command cmd, string fullName) {
    f.write(fullName);
    bool hasOptions = false;
    foreach (e; cmd._entries) if (e.kind != EntrySpec.Kind.argument) { hasOptions = true; break; }
    if (hasOptions) f.write(" [options]");
    foreach (e; cmd._entries)
        if (e.kind == EntrySpec.Kind.argument)
            f.write(" <" ~ e.displayName ~ ">");
    if (cmd._subcommands.length > 0) f.write(" <command>");
    f.writeln();
}

// Produce a GitHub-style anchor slug: lowercase, spaces→hyphens, strip the rest.
private string _anchor(string s) {
    char[] r;
    foreach (c; s) {
        if (c == ' ')
            r ~= '-';
        else if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '_')
            r ~= c;
        else if (c >= 'A' && c <= 'Z')
            r ~= cast(char)(c + 32);
    }
    return r.idup;
}

// Escape characters that break a Markdown table cell.
private string _escapeMdCell(string s) {
    import std.array : replace;
    return s.replace("\n", " ").replace("|", "\\|").replace("`", "\\`");
}
