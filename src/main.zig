const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;
const expect = std.testing.expect;
const expectError = std.testing.expectError;
const MultiArrayList = std.MultiArrayList;

const get_var_name_value = @import("./helpers/get_var_name_value.zig").get_var_name_value;
const VarNameResult = @import("./helpers/get_var_name_value.zig").VarNameResult;
const css_var_to_camel_case = @import("./helpers/css_var_to_camel_case.zig").css_var_to_camel_case;

const OUTPUT_DIR_PATH = "./output";
const OUTPUT_FILE = "cssProperties.ts";

pub fn main() !void {
    // Allocator
    var gpa = std.heap.DebugAllocator(.{}){};
    const a = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(a);
    const aa = arena.allocator();

    defer {
        arena.deinit();
        const is_leaking = gpa.deinit();
        switch (is_leaking) {
            .leak => print("... Leaking ...\n", .{}),
            .ok => print("... No leaks ...\n", .{}),
        }
    }

    const exe_dir = try std.fs.selfExeDirPathAlloc(a);
    defer a.free(exe_dir);

    const zig_out = std.fs.path.dirname(exe_dir) orelse exe_dir;

    const file_path = std.fs.path.join(aa, &.{ zig_out, "test/assets/test_css.scss" }) catch |err| {
        print("Couldn't join parts of the test scss file: {any}", .{err});
        return;
    };

    // CSS File parsing
    const file = std.fs.cwd().openFile(file_path, .{ .mode = .read_only }) catch |err| {
        switch (err) {
            error.FileNotFound => {
                print("Could not find the file\n", .{});
            },
            else => |_e| {
                print("Some error: {any}\n", .{_e});
            },
        }
        return;
    };
    defer file.close();

    const file_stat = file.stat() catch |err| {
        print("Error getting file stats: {any}\n", .{err});
        return;
    };
    const buffer = aa.alloc(u8, file_stat.size) catch |err| {
        print("Couldn't allocate enough memory. Error: {any}\n", .{err});
        return;
    };
    print("Allocated buffer is {} bytes\n", .{buffer.len});
    var r_impl = file.reader(buffer);
    const r = &r_impl.interface;

    var parsing_results = MultiArrayList(VarNameResult){};
    defer parsing_results.deinit(aa);

    while (r.takeDelimiterExclusive('\n')) |line| {
        const parse_res = get_var_name_value(line);
        if (parse_res) |_nm| {
            parsing_results.append(aa, _nm) catch {};
        } else |_| {
            continue;
        }
    } else |err| {
        if (err == error.EndOfStream) {
            print("File is read\n", .{});
        } else {
            print("Unkonwn error reading file: {any}\n", .{err});
        }
    }

    // Debug output
    // {
    //     print("Parsed results:\n", .{});
    //     var li: usize = 0;
    //     while (li < parsing_results.len) : (li += 1) {
    //         const res = parsing_results.get(li);
    //         print("{any}. {s} = {s}\n", .{ li + 1, res.name, res.value });
    //     }
    // }

    // Generate TS file
    const cwd = std.fs.cwd();
    cwd.makeDir(OUTPUT_DIR_PATH) catch |err| {
        switch (err) {
            std.posix.MakeDirError.PathAlreadyExists => print("Output directory already exists. OK.\n", .{}),
            else => {
                print("Output directory hasn't been created. Error: {any}", .{err});
                return;
            },
        }
    };

    var output_dir: std.fs.Dir = try cwd.openDir(OUTPUT_DIR_PATH, .{});
    defer output_dir.close();

    const outputFile = try output_dir.createFile(OUTPUT_FILE, .{});
    defer outputFile.close();

    var out_writer_buf: [512]u8 = undefined;
    var out_writer_impl = outputFile.writer(&out_writer_buf);
    var out_writer = &out_writer_impl.interface;

    out_writer.print("export const CssVariables = {{\n", .{}) catch |err| {
        print("Error writing to the output file: {any}\n", .{err});
    };

    for (
        parsing_results.items(.name),
        parsing_results.items(.value),
    ) |name, value| {
        const camelCaseName = css_var_to_camel_case(aa, name) catch {
            print("- failed to convert to camel-case \"{s}\". SKIPPED\n", .{name});
            continue;
        };
        out_writer.print("  {s}: '{s}',\n", .{ camelCaseName, value }) catch {};
    }

    out_writer.print("}} as const;\n", .{}) catch {};

    try out_writer.flush();
}
