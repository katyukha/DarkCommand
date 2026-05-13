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

// Returns all candidates within the suggestion threshold, sorted by distance ascending.
// Threshold: ≤ 3 edits, or distance ≤ half the unknown length (for short tokens).
// If any candidate has `unknown` as a prefix ("sta" → "start"), non-prefix candidates
// are dropped even when they tie on distance ("stop" would otherwise also score 2).
string[] suggestAll(string unknown, string[] candidates) {
    import std.algorithm : any, filter, map, sort;
    import std.array : array;
    import std.string : startsWith;

    struct Hit { string name; size_t dist; bool isPrefix; }
    Hit[] hits;
    foreach (c; candidates) {
        bool   isPrefix = c.startsWith(unknown);
        size_t d        = levenshtein(unknown, c);
        if (isPrefix || d <= 3 || d * 2 <= unknown.length)
            hits ~= Hit(c, d, isPrefix);
    }
    hits.sort!((a, b) => a.dist < b.dist);

    // If any hit is a prefix match, keep only prefix matches.
    // Otherwise, keep only hits at the minimum distance (don't surface worse alternatives
    // when a clearly closer candidate exists, e.g. "sar"→"start" not "sar"→"stop").
    if (hits.any!(h => h.isPrefix))
        hits = hits.filter!(h => h.isPrefix).array;
    else if (hits.length > 0)
        hits = hits.filter!(h => h.dist == hits[0].dist).array;

    return hits.map!(h => h.name).array;
}

// Returns the single closest candidate, or null if nothing is close enough.
string suggest(string unknown, string[] candidates) {
    auto hits = suggestAll(unknown, candidates);
    return hits.length ? hits[0] : null;
}

// Formats a "did you mean X?" / "did you mean X or Y?" hint, or null if no candidates.
string didYouMean(string[] hints) {
    import std.algorithm : map;
    import std.array : join;
    if (hints.length == 0) return null;
    if (hints.length == 1) return "did you mean '" ~ hints[0] ~ "'?";
    return "did you mean " ~
        hints[0 .. $ - 1].map!(h => "'" ~ h ~ "'").join(", ") ~
        " or '" ~ hints[$ - 1] ~ "'?";
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

    // suggestAll: "st" is a prefix of both start and stop → both listed, closest first.
    auto hits = suggestAll("st", ["start", "stop", "status"]);
    assert(hits.length >= 2);
    assert(hits[0] == "stop");   // dist 2
    assert(hits[1] == "start");  // dist 3

    // suggestAll: "sta" is a prefix of "start" only → stop dropped despite equal distance.
    auto hits2 = suggestAll("sta", ["start", "stop"]);
    import std.conv : to;
    assert(hits2 == ["start"], "expected only start, got: " ~ hits2.to!string);

    // suggestAll: "s" is a prefix of both start and stop; start exceeds dist threshold
    // but must still appear because it is a prefix match.
    auto hits3 = suggestAll("s", ["start", "stop"]);
    assert(hits3.length == 2, "expected start and stop, got: " ~ hits3.to!string);
    assert(hits3[0] == "stop",  "stop should come first (dist 3): " ~ hits3.to!string);
    assert(hits3[1] == "start", "start should be second (dist 4): " ~ hits3.to!string);

    // suggestAll: non-prefix, only the minimum-distance candidates are kept.
    // "sar" → start (dist 2), stop (dist 3): stop must not appear.
    auto hits4 = suggestAll("sar", ["start", "stop"]);
    assert(hits4 == ["start"], "expected only start for sar, got: " ~ hits4.to!string);

    // didYouMean formatting.
    assert(didYouMean([])              is null);
    assert(didYouMean(["start"])       == "did you mean 'start'?");
    assert(didYouMean(["stop","start"])== "did you mean 'stop' or 'start'?");
    assert(didYouMean(["a","b","c"])   == "did you mean 'a', 'b' or 'c'?");
}
