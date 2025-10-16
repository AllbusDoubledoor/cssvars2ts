const std = @import("std");

pub const Config = struct {
    a: std.mem.Allocator,

    lib_root: []const u8,
    target_app_dir: []const u8,

    pub fn init(a: std.mem.Allocator) !@This() {
        const bin = try std.fs.selfExeDirPathAlloc(a);
        defer a.free(bin);

        const zig_out = std.fs.path.dirname(bin) orelse bin;
        const lib_root_buffer = try a.alloc(u8, zig_out.len);
        @memmove(lib_root_buffer, zig_out);

        const dir_containing_config = try get_app_root_path(zig_out);
        const target_app_dir_buffer = try a.alloc(u8, dir_containing_config.len);
        @memmove(target_app_dir_buffer, dir_containing_config);

        return .{
            .a = a,
            .lib_root = lib_root_buffer,
            .target_app_dir = target_app_dir_buffer,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.a.free(self.lib_root);
        self.a.free(self.target_app_dir);
    }

    // TODO: consider some other stopping indicators, maybe .git file or node_modules
    fn get_app_root_path(start: []const u8) ![]const u8 {
        var cur_path = start[0..];

        outer: while (cur_path.len != 0) {
            var cur_dir = try std.fs.cwd().openDir(cur_path, .{ .iterate = true });
            defer cur_dir.close();

            var iter = cur_dir.iterate();
            while (try iter.next()) |entry| {
                if (std.mem.eql(u8, entry.name, "cv2ts.json")) {
                    break :outer;
                }
            }

            cur_path = std.fs.path.dirname(cur_path) orelse return Error.AppRootNotFound;
        }

        return cur_path;
    }

    pub const Error = error{
        AppRootNotFound,
    };
};
