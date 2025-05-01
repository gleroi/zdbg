const std = @import("std");

pub fn contains(comptime T: type, haystack: [*:0]const T, needle: [*:0]const T) bool {
    const needle_len = std.mem.len(needle);

    var haystack_len = std.mem.len(haystack);
    var haystack_start: usize = 0;
    prefix_search: while (haystack_len >= needle_len) {
        const sub_haystack = haystack[haystack_start..];

        for (0..needle_len) |i| {
            if (sub_haystack[i] != needle[i]) {
                haystack_start += 1;
                haystack_len -= 1;
                continue :prefix_search;
            }
        }
        return true;
    }
    return false;
}

test "contains basic tests" {
    const expect = std.testing.expect;

    try expect(contains(u8, "identical", "identical"));
    try expect(contains(u8, "identical", "dentical"));
    try expect(contains(u8, "identical", "identica"));
    try expect(contains(u8, "identical", "ent"));
    try expect(contains(u8, "identical", ""));

    try expect(!contains(u8, "identical", "lac"));
    try expect(!contains(u8, "identical", "entw"));
    try expect(!contains(u8, "identical", "identicalidentical"));
}
