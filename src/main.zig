const std = @import("std");
const builtin = @import("builtin");
const print = std.debug.print;
const assert = std.debug.assert;
const expect = std.testing.expect;
const expectError = std.testing.expectError;
const MultiArrayList = std.MultiArrayList;

const get_var_name_value = @import("./helpers/get_var_name_value.zig").get_var_name_value;
const VarNameResult = @import("./helpers/get_var_name_value.zig").VarNameResult;
const css_var_to_camel_case = @import("./helpers/css_var_to_camel_case.zig").css_var_to_camel_case;

const Config = @import("./Config.zig").Config;

// TODO: take these from config
pub const CONFIG_FILE_NAME = "cv2ts.json";
const INPUT_FILE = "./test.scss";
const OUTPUT_DEFAULT_FILE: []const u8 = "cssProperties";
const DEFAULT_FILE_EXTENSION: []const u8 = "ts";

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    const a = gpa.allocator();

    defer {
        const is_leaking = gpa.deinit();

        if (builtin.mode == .Debug) {
            switch (is_leaking) {
                .leak => print("...\n... Leaking ...\n...\n", .{}),
                .ok => print("...\n... No leaks ...\n...\n", .{}),
            }
        }
    }

    var config = try Config.init(a);
    defer config.deinit();

    if (builtin.mode == .Debug) {
        print("Config:\n", .{});
        print("    lib_root: {s}\n", .{config.lib_root});
        print("    target_app_dir: {s}\n", .{config.target_app_dir});
        print("    output: {s}\n", .{config.output});
    }

    const project_container_path = config.target_app_dir;

    if (builtin.mode == .Debug) {
        print("project container: {s}\n", .{project_container_path});
    }

    const file_path = std.fs.path.join(a, &.{ project_container_path, INPUT_FILE }) catch |err| {
        print("Couldn't join parts of the test scss file: {any}", .{err});
        return;
    };
    defer a.free(file_path);

    // CSS File parsing
    const input_file = std.fs.cwd().openFile(file_path, .{ .mode = .read_only }) catch |err| {
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
    defer input_file.close();

    const file_stat = input_file.stat() catch |err| {
        print("Error getting file stats: {any}\n", .{err});
        return;
    };
    const input_file_buffer = a.alloc(u8, file_stat.size) catch |err| {
        print("Couldn't allocate enough memory. Error: {any}\n", .{err});
        return;
    };
    defer a.free(input_file_buffer);

    var r_impl = input_file.reader(input_file_buffer);
    const r = &r_impl.interface;

    var parsing_results = MultiArrayList(VarNameResult){};
    defer parsing_results.deinit(a);

    while (r.takeDelimiterExclusive('\n')) |line| {
        const parse_res = get_var_name_value(line);
        if (parse_res) |_nm| {
            parsing_results.append(a, _nm) catch {};
        } else |_| {
            continue;
        }
    } else |err| {
        if (err == error.EndOfStream) {
            if (builtin.mode == .Debug)
                print("File is read\n", .{});
        } else {
            print("Unkonwn error reading file: {any}\n", .{err});
        }
    }

    // Generate TS file
    const cwd = std.fs.cwd();
    cwd.makeDir(config.output) catch |err| {
        switch (err) {
            std.posix.MakeDirError.PathAlreadyExists => print("Output directory already exists. OK.\n", .{}),
            else => {
                print("Output directory hasn't been created. Error: {any}", .{err});
                return;
            },
        }
    };

    var output_dir: std.fs.Dir = try cwd.openDir(config.output, .{});
    defer output_dir.close();

    var output_file_name: []const u8 = OUTPUT_DEFAULT_FILE;
    defer a.free(output_file_name);

    if (config.file_name) |file_name| {
        output_file_name = try std.mem.join(a, ".", &.{ file_name, DEFAULT_FILE_EXTENSION });
    }

    const outputFile = try output_dir.createFile(output_file_name, .{});
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
        const camelCaseName = css_var_to_camel_case(a, name) catch {
            print("- failed to convert to camel-case \"{s}\". SKIPPED\n", .{name});
            continue;
        };
        out_writer.print("  {s}: '{s}',\n", .{ camelCaseName, value }) catch {};
        a.free(camelCaseName);
    }

    out_writer.print("}} as const;\n", .{}) catch {};

    try out_writer.flush();
}
