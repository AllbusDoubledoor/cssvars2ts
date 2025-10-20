const std = @import("std");
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
const OUTPUT_DIR_PATH = "./output";
const OUTPUT_FILE = "cssProperties.ts";

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    const a = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(a);
    const aa = arena.allocator();

    defer {
        arena.deinit();
        const is_leaking = gpa.deinit();
        switch (is_leaking) {
            .leak => print("...\n... Leaking ...\n...\n", .{}),
            .ok => print("...\n... No leaks ...\n...\n", .{}),
        }
    }

    var config = try Config.init(a);
    defer config.deinit();

    print("Config:\n", .{});
    print("    lib_root: {s}\n", .{config.lib_root});
    print("    target_app_dir: {s}\n", .{config.target_app_dir});
    print("    output: {s}\n", .{config.output});

    const project_container_path = config.target_app_dir;

    print("project container: {s}\n", .{project_container_path});

    const file_path = std.fs.path.join(aa, &.{ project_container_path, INPUT_FILE }) catch |err| {
        print("Couldn't join parts of the test scss file: {any}", .{err});
        return;
    };

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
    const buffer = aa.alloc(u8, file_stat.size) catch |err| {
        print("Couldn't allocate enough memory. Error: {any}\n", .{err});
        return;
    };

    var r_impl = input_file.reader(buffer);
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
