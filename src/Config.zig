const std = @import("std");
const print = std.debug.print;

const CONFIG_FILE_NAME = @import("./main.zig").CONFIG_FILE_NAME;

arena: std.heap.ArenaAllocator,

input: []const u8,
output: []const u8,
file_name: ?[]const u8 = null,
output_object_name: ?[]const u8 = null,

pub fn init(a: std.mem.Allocator) !@This() {
    var arena = std.heap.ArenaAllocator.init(a);
    var arena_a = arena.allocator();

    const bin = try std.fs.selfExeDirPathAlloc(a);
    defer a.free(bin);

    const config_path = try get_config_file_path(arena_a);

    const config_file = try std.fs.cwd().readFileAlloc(a, config_path, 4048);
    defer a.free(config_file);

    const config_json: std.json.Parsed(ConfigStructure) = try std.json.parseFromSlice(ConfigStructure, a, config_file, .{ .ignore_unknown_fields = true });
    defer config_json.deinit();

    const input_buffer = try arena_a.alloc(u8, config_json.value.input.len);
    @memmove(input_buffer, config_json.value.input);

    const output_buffer = try arena_a.alloc(u8, config_json.value.output.len);
    @memmove(output_buffer, config_json.value.output);

    const file_name_buffer = try arena_a.alloc(u8, config_json.value.fileName.len);
    @memmove(file_name_buffer, config_json.value.fileName);

    const output_object_name_buffer = try arena_a.alloc(u8, config_json.value.outputObjectName.len);
    @memmove(output_object_name_buffer, config_json.value.outputObjectName);

    return .{
        .arena = arena,
        .input = input_buffer,
        .output = output_buffer,
        .file_name = file_name_buffer,
        .output_object_name = output_object_name_buffer,
    };
}

pub fn deinit(self: *@This()) void {
    self.arena.deinit();
}

fn get_config_file_path(a: std.mem.Allocator) ![]const u8 {
    const cwd = try std.fs.cwd().openDir(".", .{ .iterate = true });

    var cwdWalker = try cwd.walk(a);
    defer cwdWalker.deinit();

    while (try cwdWalker.next()) |entry| {
        if (entry.kind != .file) continue;

        if (std.mem.eql(u8, entry.basename, CONFIG_FILE_NAME)) {
            const path_buffer = try a.alloc(u8, entry.path.len);
            @memmove(path_buffer, entry.path);
            return path_buffer;
        }
    }

    print("Config file wasn't found. Make sure it is in the current working directory.", .{});
    return Error.ConfigNotFound;
}

pub const Error = error{
    AppRootNotFound,
    ConfigNotFound,
};

const ConfigStructure = struct {
    input: []u8,
    output: []u8,
    fileName: []u8,
    outputObjectName: []u8,
};
