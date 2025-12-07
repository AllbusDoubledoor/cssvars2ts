const std = @import("std");
const print = std.debug.print;

const CONFIG_FILE_NAME = @import("./main.zig").CONFIG_FILE_NAME;

arena: std.heap.ArenaAllocator,

/// Root of the built library which is "zig-out" directory
lib_root: []const u8,
/// Directory of the project where the lib is being used
target_app_dir: []const u8,

output: []const u8,
file_name: ?[]const u8 = null,
output_object_name: ?[]const u8 = null,

pub fn init(a: std.mem.Allocator) !@This() {
    var arena = std.heap.ArenaAllocator.init(a);
    var allocator = arena.allocator();

    const bin = try std.fs.selfExeDirPathAlloc(a);
    defer a.free(bin);

    if (!try config_exists(a)) {
        print("Config file wasn't found. Make sure it is in the current working directory.", .{});
        return Error.ConfigNotFound;
    }

    const zig_out = std.fs.path.dirname(bin) orelse bin;
    const lib_root_buffer = try allocator.alloc(u8, zig_out.len);
    @memmove(lib_root_buffer, zig_out);

    const dir_containing_config = try get_app_root_path(zig_out);
    const target_app_dir_buffer = try allocator.alloc(u8, dir_containing_config.len);
    @memmove(target_app_dir_buffer, dir_containing_config);

    const config_path: []u8 = try std.fs.path.join(a, &.{ target_app_dir_buffer, CONFIG_FILE_NAME });
    defer a.free(config_path);

    const config_file = try std.fs.cwd().readFileAlloc(a, config_path, 4048);
    defer a.free(config_file);

    const config_json: std.json.Parsed(ConfigStructure) = try std.json.parseFromSlice(ConfigStructure, a, config_file, .{ .ignore_unknown_fields = true });
    defer config_json.deinit();

    const output_buffer = try allocator.alloc(u8, config_json.value.output.len);
    @memmove(output_buffer, config_json.value.output);

    const file_name_buffer = try allocator.alloc(u8, config_json.value.fileName.len);
    @memmove(file_name_buffer, config_json.value.fileName);

    const output_object_name_buffer = try allocator.alloc(u8, config_json.value.outputObjectName.len);
    @memmove(output_object_name_buffer, config_json.value.outputObjectName);

    return .{
        .arena = arena,
        .lib_root = lib_root_buffer,
        .target_app_dir = target_app_dir_buffer,
        .output = output_buffer,
        .file_name = file_name_buffer,
        .output_object_name = output_object_name_buffer,
    };
}

pub fn deinit(self: *@This()) void {
    self.arena.deinit();
}

// TODO: consider some other stopping indicators, maybe .git file or node_modules
fn get_app_root_path(start: []const u8) ![]const u8 {
    var cur_path = start[0..];

    outer: while (cur_path.len != 0) {
        var cur_dir = try std.fs.cwd().openDir(cur_path, .{ .iterate = true });
        defer cur_dir.close();

        var iter = cur_dir.iterate();
        while (try iter.next()) |entry| {
            if (std.mem.eql(u8, entry.name, CONFIG_FILE_NAME)) {
                break :outer;
            }
        }

        cur_path = std.fs.path.dirname(cur_path) orelse return Error.AppRootNotFound;
    }

    return cur_path;
}

fn config_exists(a: std.mem.Allocator) !bool {
    const cwd = try std.fs.cwd().openDir(".", .{ .iterate = true });

    var cwdWalker = try cwd.walk(a);
    defer cwdWalker.deinit();

    while (try cwdWalker.next()) |entry| {
        if (entry.kind != .file) continue;

        if (std.mem.eql(u8, entry.basename, CONFIG_FILE_NAME)) {
            return true;
        }
    }

    return false;
}

pub const Error = error{
    AppRootNotFound,
    ConfigNotFound,
};

const ConfigStructure = struct {
    output: []u8,
    fileName: []u8,
    outputObjectName: []u8,
};
