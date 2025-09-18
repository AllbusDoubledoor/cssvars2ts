const std = @import("std");
const expect = std.testing.expect;
const expectError = std.testing.expectError;

pub fn get_var_name_value(string: []const u8) VarNameError!VarNameResult {
    var trimmed_string: []const u8 = std.mem.trim(u8, string, " \t\r\n;");
    if (trimmed_string.len == 0) {
        return error.NoLine;
    }

    if (!std.mem.startsWith(u8, trimmed_string, "--")) {
        return error.InvalidLineStart;
    }

    const after_prefix = trimmed_string[2..];

    const colon_i = std.mem.indexOfScalar(u8, after_prefix, ':') orelse return error.NoColon;

    // When "--:"
    if (colon_i == 2) return error.NoName;

    if (colon_i + 2 > after_prefix.len) return error.NoValue;

    const name: []const u8 = std.mem.trimRight(u8, after_prefix[0..colon_i], " \t");
    if (name.len < 1) {
        return error.NoName;
    }

    const value: []const u8 = std.mem.trim(u8, after_prefix[(colon_i + 1)..], " \t");
    if (value.len < 1) {
        return error.NoValue;
    }

    return .{
        .name = name,
        .value = value,
    };
}

const VarNameError = error{
    InvalidLineStart,
    NoLine,
    NoColon,
    NoName,
    NoValue,
};

pub const VarNameResult = struct { name: []const u8, value: []const u8 };

test get_var_name_value {
    try expectError(error.NoLine, get_var_name_value("     "));
    try expectError(error.InvalidLineStart, get_var_name_value("hello: rgba(0, 0, 0, 0);"));
    try expectError(error.NoColon, get_var_name_value("--name somevalue;"));
    try expectError(error.NoName, get_var_name_value("--: somevalue;"));
    try expectError(error.NoValue, get_var_name_value("--color: ;"));
    try expectError(error.NoValue, get_var_name_value("--color:;"));

    {
        const nameValue = try get_var_name_value("--color: red;");
        try expect(std.mem.eql(u8, nameValue.name, "color"));
        try expect(std.mem.eql(u8, nameValue.value, "red"));
    }
}
