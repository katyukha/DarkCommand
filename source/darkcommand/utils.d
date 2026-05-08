module darkcommand.utils;

size_t levenshtein(string a, string b) {
    import std.algorithm : min;
    if (a.length == 0) return b.length;
    if (b.length == 0) return a.length;

    auto prev = new size_t[](b.length + 1);
    auto curr = new size_t[](b.length + 1);
    foreach (j; 0 .. b.length + 1)
        prev[j] = j;

    foreach (i; 1 .. a.length + 1) {
        curr[0] = i;
        foreach (j; 1 .. b.length + 1) {
            size_t cost = (a[i - 1] == b[j - 1]) ? 0 : 1;
            curr[j] = min(curr[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost);
        }
        auto tmp = prev; prev = curr; curr = tmp;
    }
    return prev[b.length];
}

// Returns the closest candidate, or null if nothing is close enough.
string suggest(string unknown, string[] candidates) {
    if (candidates.length == 0) return null;
    string best;
    size_t bestDist = size_t.max;
    foreach (c; candidates) {
        size_t d = levenshtein(unknown, c);
        if (d < bestDist) { bestDist = d; best = c; }
    }
    // Suggest only when ≤ 3 edits or within half the unknown length.
    if (bestDist <= 3 || bestDist * 2 <= unknown.length)
        return best;
    return null;
}

unittest {
    assert(levenshtein("kitten", "sitting") == 3);
    assert(levenshtein("",  "abc") == 3);
    assert(levenshtein("abc", "") == 3);
    assert(levenshtein("abc", "abc") == 0);
    assert(levenshtein("a", "b") == 1);

    assert(suggest("installl", ["install", "uninstall", "list"]) == "install");
    assert(suggest("vrebose",  ["verbose", "version"]) == "verbose");
    assert(suggest("xyz",      ["install", "uninstall", "list"]) is null);
    assert(suggest("foo", []) is null);
}
