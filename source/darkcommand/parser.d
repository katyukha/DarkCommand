module darkcommand.parser;

private import darkcommand.command;
private import darkcommand.entry;
private import darkcommand.utils;

// Parses the full command chain starting at root, returns the matched subcommand
// chain (root-level entries are consumed but root itself is not in the returned slice).
// Throws DarkCommandException on any parse error.
Command[] parseChain(Command root, string[] argv) {
    Command[] chain;
    string[]  remaining = argv;
    Command   current   = root;

    while (true) {
        Command next = _parseOne(current, remaining);
        if (next is null)
            break;
        chain    ~= next;
        current   = next;
    }
    return chain;
}

// Parses one command level.  Mutates argv to hold the tokens not yet consumed
// (i.e. those that belong to the matched subcommand).
// Returns the dispatched subcommand, or null if the token stream is exhausted.
private Command _parseOne(Command cmd, ref string[] argv) {
    // Reset all entry state so the same instance can be parsed multiple times.
    cmd.argsRest = null;
    foreach (e; cmd._entries) {
        e.provided = false;
        if (e.writeReset !is null) e.writeReset();
    }

    // Split _entries into flags/options and arguments for quick lookup.
    EntrySpec[] argSpecs;
    foreach (e; cmd._entries)
        if (e.kind == EntrySpec.Kind.argument)
            argSpecs ~= e;

    size_t argIdx  = 0;   // next positional argument spec to fill
    size_t i       = 0;

    while (i < argv.length) {
        string tok = argv[i];

        // ── end-of-options sentinel ──────────────────────────────────────────
        if (tok == "--") {
            cmd.argsRest = argv[i + 1 .. $].dup;
            argv         = [];
            _finalize(cmd, argSpecs, argIdx);
            return null;
        }

        // ── long option / flag  --name  or  --name=value ────────────────────
        if (tok.length > 2 && tok[0 .. 2] == "--") {
            string rest  = tok[2 .. $];
            string name, value;
            bool   hasEq = false;

            import std.string : indexOf;
            ptrdiff_t eq = rest.indexOf('=');
            if (eq >= 0) {
                name  = rest[0 .. eq];
                value = rest[eq + 1 .. $];
                hasEq = true;
            } else {
                name = rest;
            }

            // --help short-circuit
            if (name == "help") {
                import darkcommand.help : printHelp;
                printHelp(cmd);
                throw new DarkCommandExitException(0);
            }

            // --version short-circuit (root Program only)
            if (name == "version") {
                if (auto prog = cast(Program) cmd) if (!prog._noAutoVersion) {
                    import std.stdio : stdout;
                    stdout.writeln(prog.name ~ " " ~ prog._version);
                    throw new DarkCommandExitException(0);
                }
            }

            // --no-X form for negatable bool flags
            if (name.length > 3 && name[0 .. 3] == "no-") {
                EntrySpec negSpec = _findNegatable(cmd, name[3 .. $]);
                if (negSpec !is null) {
                    if (hasEq) throw new DarkCommandException(
                        "--" ~ name ~ " is a flag and does not take a value");
                    negSpec.setFalse();
                    negSpec.provided = true;
                    i++;
                    continue;
                }
            }

            EntrySpec spec = _findLong(cmd, name);
            if (spec is null) {
                if (auto def = _defaultDispatch(cmd, argv, i, argSpecs, argIdx))
                    return def;
                import std.algorithm : map;
                import std.array : array;
                import darkcommand.exceptions : UnknownOptionException;
                string[] longs    = _longNames(cmd);
                string[] rawHints = suggestAll(name, longs);
                string[] hints    = rawHints.map!(h => "--" ~ h).array;
                string   msg      = "unknown option: --" ~ name;
                string   hint     = didYouMean(hints);
                if (hint !is null) msg ~= "; " ~ hint;
                throw new UnknownOptionException("--" ~ name, hints, msg);
            }

            if (spec.isBoolFlag()) {
                if (hasEq) throw new DarkCommandException(
                    "--" ~ name ~ " is a flag and does not take a value");
                if (!spec.negatable && spec.provided) throw new DarkCommandException(
                    "flag --" ~ name ~ " is boolean; specify it at most once");
                spec.setTrue();
                spec.provided = true;
            } else if (spec.isIntFlag()) {
                if (hasEq) throw new DarkCommandException(
                    "--" ~ name ~ " is a flag and does not take a value");
                spec.increment();
                spec.provided = true;
            } else {
                // value-taking option
                if (!hasEq) {
                    if (i + 1 >= argv.length)
                        throw new DarkCommandException(
                            "option --" ~ name ~ " requires a value");
                    value = argv[++i];
                }
                spec.runValidators(value);
                spec.writeValue(value);
                spec.provided = true;
            }
            i++;
            continue;
        }

        // ── short flag(s) / option  -x  -xyz  -x=val ────────────────────────
        if (tok.length >= 2 && tok[0] == '-' && tok[1] != '-') {
            size_t j = 1;
            while (j < tok.length) {
                string shortName = tok[j .. j + 1];
                j++;

                // -h short-circuit
                if (shortName == "h") {
                    import darkcommand.help : printHelp;
                    printHelp(cmd);
                    throw new DarkCommandExitException(0);
                }

                EntrySpec spec = _findShort(cmd, shortName);
                if (spec is null) {
                    if (auto def = _defaultDispatch(cmd, argv, i, argSpecs, argIdx))
                        return def;
                    import std.algorithm : map;
                    import std.array : array;
                    import darkcommand.exceptions : UnknownOptionException;
                    string[] shorts   = _shortNames(cmd);
                    string[] rawHints = suggestAll(shortName, shorts);
                    string[] hints    = rawHints.map!(h => "-" ~ h).array;
                    string   msg      = "unknown flag: -" ~ shortName;
                    string   hint     = didYouMean(hints);
                    if (hint !is null) msg ~= "; " ~ hint;
                    throw new UnknownOptionException("-" ~ shortName, hints, msg);
                }

                if (spec.isBoolFlag()) {
                    if (spec.provided)
                        throw new DarkCommandException(
                            "flag -" ~ shortName ~
                            " is boolean; use an int Flag for counting");
                    spec.setTrue();
                    spec.provided = true;

                } else if (spec.isIntFlag()) {
                    spec.increment();
                    spec.provided = true;

                } else {
                    // value-taking option — must be last in the stack
                    string value;
                    if (j < tok.length) {
                        // remainder of token is the value (with optional '=')
                        value = (tok[j] == '=') ? tok[j + 1 .. $] : tok[j .. $];
                        j = tok.length; // consume rest of stack
                    } else {
                        if (i + 1 >= argv.length)
                            throw new DarkCommandException(
                                "option -" ~ shortName ~ " requires a value");
                        value = argv[++i];
                    }
                    spec.runValidators(value);
                    spec.writeValue(value);
                    spec.provided = true;
                }
            }
            i++;
            continue;
        }

        // ── positional token ─────────────────────────────────────────────────
        // First check if it's a subcommand name.
        Command sub = cmd._findSubcommand(tok);
        if (sub !is null) {
            argv = argv[i + 1 .. $];
            _finalize(cmd, argSpecs, argIdx);
            return sub;
        }

        // Treat as positional argument.
        if (argIdx >= argSpecs.length) {
            // Check for subcommand typo before forwarding to a defaultCommand.
            // If the token resembles a sibling subcommand name, suggest it rather
            // than forwarding blindly (which produces a confusing nested error).
            if (cmd._subcommands.length > 0) {
                import std.algorithm : map;
                import std.array : array;
                string[] names = cmd._subcommands.map!(s => s.name).array;
                if (auto prog = cast(Program) cmd)
                    foreach (s; prog._shortcuts) names ~= s.name;
                string[] hints = suggestAll(tok, names);
                if (hints.length > 0) {
                    // Hook either throws (default) or returns a corrected subcommand name.
                    string corrected = cmd._onUnknownCommand(tok, hints);
                    Command sub2 = cmd._findSubcommand(corrected);
                    if (sub2 is null)
                        throw new DarkCommandException("unknown command '" ~ corrected ~ "'");
                    argv = argv[i + 1 .. $];
                    _finalize(cmd, argSpecs, argIdx);
                    return sub2;
                }
            }
            if (auto def = _defaultDispatch(cmd, argv, i, argSpecs, argIdx))
                return def;
            if (cmd._subcommands.length > 0) {
                import darkcommand.exceptions : UnknownCommandException;
                throw new UnknownCommandException(tok, [], "unknown command '" ~ tok ~ "'");
            }
            throw new DarkCommandException("unexpected argument: " ~ tok);
        }

        EntrySpec aspec = argSpecs[argIdx];
        aspec.runValidators(tok);
        aspec.writeValue(tok);
        aspec.provided = true;
        if (!aspec.isRepeating())
            argIdx++;

        i++;
    }

    argv = [];
    _finalize(cmd, argSpecs, argIdx);

    // All args consumed with no subcommand matched — try defaultCommand.
    if (cmd._defaultCommand.length > 0) {
        Command def = cmd._findSubcommand(cmd._defaultCommand);
        if (def !is null) return def;
    }
    return null;
}

// Check required entries; apply defaults for unprovided ones.
private void _finalize(Command cmd, EntrySpec[] argSpecs, size_t argIdx) {
    foreach (e; cmd._entries) {
        if (!e.provided) {
            // Repeating arguments marked .required() are also required, but the
            // dedicated loop below gives them a clearer "one or more" message.
            if (e.isRequired() && !(e.isArgument() && e.isRepeating())) {
                string kind = e.kind == EntrySpec.Kind.argument ? "argument" : "option";
                throw new DarkCommandException(
                    "missing required " ~ kind ~ ": " ~ e.cliName);
            }
            if (e.hasDefault)
                e.writeDefault();
        }
    }
    // Repeating T[] Arguments are zero-or-more by default; .required() makes them
    // one-or-more. Enforce "at least one value" only when marked required.
    foreach (aspec; argSpecs) {
        if (aspec.isRepeating() && aspec.isRequired() && !aspec.provided)
            throw new DarkCommandException(
                "missing required argument: " ~ aspec.displayName ~
                " (expected one or more values)");
    }
}

// ── Lookup helpers ────────────────────────────────────────────────────────────

private EntrySpec _findLong(Command cmd, string name) {
    foreach (e; cmd._entries)
        if (e.longName == name) return e;
    return null;
}

private EntrySpec _findShort(Command cmd, string name) {
    foreach (e; cmd._entries)
        if (e.shortName == name) return e;
    return null;
}

private EntrySpec _findNegatable(Command cmd, string baseName) {
    foreach (e; cmd._entries)
        if (e.negatable && e.longName == baseName) return e;
    return null;
}

private string[] _longNames(Command cmd) {
    string[] names;
    foreach (e; cmd._entries) {
        if (e.longName.length) {
            names ~= e.longName;
            if (e.negatable) names ~= "no-" ~ e.longName;
        }
    }
    return names;
}

private string[] _shortNames(Command cmd) {
    string[] names;
    foreach (e; cmd._entries)
        if (e.shortName.length) names ~= e.shortName;
    return names;
}

// If cmd has a defaultCommand, set argv to remaining tokens starting at i,
// validate cmd's already-parsed entries, and return the default subcommand.
// Returns null if no defaultCommand is configured.
private Command _defaultDispatch(Command cmd, ref string[] argv, size_t i,
                                  EntrySpec[] argSpecs, size_t argIdx)
{
    if (cmd._defaultCommand.length == 0) return null;
    Command def = cmd._findSubcommand(cmd._defaultCommand);
    if (def is null) return null;
    argv = argv[i .. $];
    _finalize(cmd, argSpecs, argIdx);
    return def;
}
