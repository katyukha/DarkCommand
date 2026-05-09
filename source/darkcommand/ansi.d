module darkcommand.ansi;

// Returns true when color output should be suppressed (NO_COLOR env var set,
// per https://no-color.org).
bool noColor() {
    import std.process : environment;
    return environment.get("NO_COLOR", "").length > 0;
}

package(darkcommand) bool _colorEnabled() {
    version (Posix) {
        import core.sys.posix.unistd : isatty, STDOUT_FILENO;
        return !noColor() && isatty(STDOUT_FILENO) != 0;
    } else {
        return false;
    }
}

package(darkcommand) bool _stderrColorEnabled() {
    version (Posix) {
        import core.sys.posix.unistd : isatty, STDERR_FILENO;
        return !noColor() && isatty(STDERR_FILENO) != 0;
    } else {
        return false;
    }
}

package(darkcommand) string _bold     (string s, bool c) { return c ? "\x1b[1m"  ~ s ~ "\x1b[0m" : s; }
package(darkcommand) string _dim      (string s, bool c) { return c ? "\x1b[2m"  ~ s ~ "\x1b[0m" : s; }
package(darkcommand) string _underline(string s, bool c) { return c ? "\x1b[4m"  ~ s ~ "\x1b[0m" : s; }
package(darkcommand) string _red      (string s, bool c) { return c ? "\x1b[31m" ~ s ~ "\x1b[0m" : s; }
