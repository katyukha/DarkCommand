module darkcommand.docs.json;

private import darkcommand.command;
private import darkcommand.entry;
private import std.json : JSONValue;
private import std.stdio : File;

// Build the command tree of `prog` as a JSONValue — a machine-readable,
// drift-free dump of the live command tree (commands, subcommands, options,
// flags, arguments, shortcuts). This is the reusable primitive behind
// `generateJSONDocs`; callers can print it or embed it in a larger document.
//
// Intentional omissions (mirroring how the tree is actually declared):
//   * The framework-universal `-h/--help` (every command) and `--version`
//     (every program) options are NOT emitted. Only entries the user declared
//     in `_entries` appear; consumers can assume the universals exist. (The
//     markdown generator *renders* a --help row; JSON deliberately does not.)
//   * The dynamic-completion shell command (`.completesWithCommand`) is not
//     serialized — only the static `completion` hint and `accepts_values`.
JSONValue commandTreeToJSON(Program prog) {
    JSONValue root = JSONValue.emptyObject;
    root["schema_version"] = 1;
    root["program"]        = prog.name;
    root["version"]        = prog._version;
    root["command"]        = _commandToJSON(cast(Command) prog, true);
    return root;
}

// Write the command tree of `prog` to `output` as pretty-printed JSON.
void generateJSONDocs(Program prog, File output) {
    output.writeln(commandTreeToJSON(prog).toPrettyString());
}

// ── Private ───────────────────────────────────────────────────────────────────

private JSONValue _commandToJSON(Command cmd, bool isRoot) {
    JSONValue node = JSONValue.emptyObject;
    node["name"] = cmd.name;
    if (cmd.summary.length)     node["summary"]     = cmd.summary;
    if (cmd.description.length)  node["description"] = cmd.description;

    JSONValue[] options;
    JSONValue[] arguments;
    foreach (e; cmd._entries) {
        if (e.kind == EntrySpec.Kind.argument)
            arguments ~= _argumentToJSON(e);
        else
            options ~= _optionToJSON(e);
    }
    node["options"]   = options;
    node["arguments"] = arguments;

    JSONValue[] subs;
    foreach (sub; cmd._subcommands)
        subs ~= _commandToJSON(sub, false);
    node["subcommands"] = subs;

    // Shortcuts live on the Program (root) only.
    if (isRoot) {
        if (auto prog = cast(Program) cmd) {
            if (prog._shortcuts.length > 0) {
                JSONValue[] shortcuts;
                foreach (s; prog._shortcuts)
                    shortcuts ~= _shortcutToJSON(s);
                node["shortcuts"] = shortcuts;
            }
        }
    }
    return node;
}

private JSONValue _optionToJSON(EntrySpec e) {
    JSONValue node = JSONValue.emptyObject;
    node["name"] = e.cliName;
    if (e.shortName.length) node["short"] = e.shortName;
    if (e.longName.length)  node["long"]  = e.longName;
    node["kind"] = e.kind == EntrySpec.Kind.flag ? "flag" : "option";
    if (e.desc.length) node["description"] = e.desc;
    node["required"]   = e.isRequired();
    node["repeating"]  = e.isRepeating();
    node["negatable"]  = e.negatable;
    node["has_default"] = e.hasDefault;

    if (e.completionValues.length) {
        JSONValue[] vals;
        foreach (v; e.completionValues) vals ~= JSONValue(v);
        node["accepts_values"] = vals;
    }
    if (auto hint = _completionHint(e.completionHint))
        node["completion"] = hint;
    return node;
}

private JSONValue _argumentToJSON(EntrySpec e) {
    JSONValue node = JSONValue.emptyObject;
    node["name"] = e.displayName;
    if (e.desc.length) node["description"] = e.desc;
    node["required"]  = e.isRequired();
    node["repeating"] = e.isRepeating();
    return node;
}

private JSONValue _shortcutToJSON(ShortcutEntry s) {
    JSONValue node = JSONValue.emptyObject;
    node["name"] = s.name;
    JSONValue[] expansion;
    foreach (t; s.expansion) expansion ~= JSONValue(t);
    node["expansion"] = expansion;
    if (s.summary.length) node["summary"] = s.summary;
    return node;
}

// Static completion hint as a string; null (→ omitted) for CompletionHint.none.
private string _completionHint(EntrySpec.CompletionHint h) {
    final switch (h) {
        case EntrySpec.CompletionHint.none:      return null;
        case EntrySpec.CompletionHint.file:      return "file";
        case EntrySpec.CompletionHint.directory: return "directory";
        case EntrySpec.CompletionHint.path:      return "path";
    }
}
