const std = @import("std");
const print = std.debug.print;

pub fn css_var_to_camel_case(a: std.mem.Allocator, variable_name: []const u8) ![]const u8 {
    var variable_name_iter = std.mem.splitScalar(u8, variable_name, '-');
    const dashes_count = std.mem.count(u8, variable_name, "-");
    const camel_cased_name = try a.alloc(u8, variable_name.len - dashes_count);

    const first_part = variable_name_iter.first();
    @memcpy(camel_cased_name[0..first_part.len], first_part[0..]);

    var insert_i: usize = @intCast(first_part.len);
    while (variable_name_iter.next()) |name_part| {
        var buf: [1]u8 = undefined;
        buf[0] = std.ascii.toUpper(name_part[0]);
        @memcpy(
            camel_cased_name[insert_i .. insert_i + 1],
            buf[0..],
        );
        insert_i += 1;

        if (name_part.len > 1) {
            @memcpy(
                camel_cased_name[insert_i .. insert_i + name_part.len - 1],
                name_part[1..name_part.len],
            );
            insert_i += name_part.len - 1;
        }
    }

    return camel_cased_name;
}

const CssVarToCamelCaseError = error{
    Empty,
};
