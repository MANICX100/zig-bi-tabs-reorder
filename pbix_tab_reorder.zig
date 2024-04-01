const std = @import("std");
const gamekit = @import("gamekit");
const gk = gamekit.gk;

var selected_file: ?[]const u8 = null;
var tab_entries = std.ArrayList([]const u8).init(std.heap.page_allocator);

pub fn main() !void {
    try gamekit.run(.{
        .init = init,
        .update = update,
        .deinit = deinit,
    }, .{});
}

fn init(ctx: *gamekit.Context) anyerror!void {
    _ = ctx;
}

fn update(ctx: *gamekit.Context) anyerror!void {
    if (gk.io.dropFile()) |path| {
        selected_file = path;
        try loadTabEntries(path);
    }

    gk.graphics.clear(gk.Color.rgb(255, 255, 255));

    if (selected_file) |file| {
        gk.graphics.drawText(file, .{
            .x = 10,
            .y = 10,
            .color = gk.Color.rgb(0, 0, 0),
        });

        var y: f32 = 50;
        for (tab_entries.items) |tab_entry, i| {
            gk.graphics.drawText(tab_entry, .{
                .x = 10,
                .y = y,
                .color = gk.Color.rgb(0, 0, 0),
            });

            if (gk.io.mouseDown(.left) and gk.math.pointInRect(gk.io.mousePos(), .{
                .x = 10,
                .y = y - 10,
                .width = 200,
                .height = 20,
            })) {
                const dragged_item = tab_entries.orderedRemove(i);
                const drop_index = @floatToInt(usize, (gk.io.mousePos().y - 50) / 20);
                try tab_entries.insert(drop_index, dragged_item);
            }

            y += 20;
        }

        if (gk.io.buttonPressed(.space)) {
            try reorderTabs(selected_file.?);
        }
    } else {
        gk.graphics.drawText("Drop a .pbix file to reorder its tabs", .{
            .x = 10,
            .y = 10,
            .color = gk.Color.rgb(0, 0, 0),
        });
    }

    gk.graphics.commit();

    if (gk.io.buttonPressed(.escape)) {
        ctx.close();
    }
}

fn deinit(_: *gamekit.Context) void {
    tab_entries.deinit();
}

fn loadTabEntries(file_path: []const u8) !void {
    tab_entries.clearRetainingCapacity();

    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const buffer = try file.readToEndAlloc(std.heap.page_allocator, file_size);
    defer std.heap.page_allocator.free(buffer);

    const tab_order_start = std.mem.indexOf(u8, buffer, "<tabOrder>");
    const tab_order_end = std.mem.indexOf(u8, buffer[tab_order_start.?..], "</tabOrder>");
    const tab_order_section = buffer[tab_order_start.?..tab_order_start.? + tab_order_end.? + 11];

    var tab_iter = std.mem.split(u8, tab_order_section, "<tab");
    while (tab_iter.next()) |tab_entry| {
        try tab_entries.append(tab_entry);
    }
}

fn reorderTabs(file_path: []const u8) !void {
    const file = try std.fs.cwd().openFile(file_path, .{ .mode = .read_write });
    defer file.close();

    const file_size = try file.getEndPos();
    const buffer = try file.readToEndAlloc(std.heap.page_allocator, file_size);
    defer std.heap.page_allocator.free(buffer);

    const tab_order_start = std.mem.indexOf(u8, buffer, "<tabOrder>");
    const tab_order_end = std.mem.indexOf(u8, buffer[tab_order_start.?..], "</tabOrder>");
    const tab_order_section = buffer[tab_order_start.?..tab_order_start.? + tab_order_end.? + 11];

    var new_tab_order_section = std.ArrayList(u8).init(std.heap.page_allocator);
    defer new_tab_order_section.deinit();

    try new_tab_order_section.appendSlice("<tabOrder>\n");
    for (tab_entries.items) |tab_entry| {
        try new_tab_order_section.appendSlice("<tab");
        try new_tab_order_section.appendSlice(tab_entry);
        try new_tab_order_section.appendSlice("\n");
    }
    try new_tab_order_section.appendSlice("</tabOrder>");

    const new_buffer = try std.heap.page_allocator.alloc(u8, buffer.len - tab_order_section.len + new_tab_order_section.items.len);
    defer std.heap.page_allocator.free(new_buffer);

    std.mem.copy(u8, new_buffer[0..tab_order_start.?], buffer[0..tab_order_start.?]);
    std.mem.copy(u8, new_buffer[tab_order_start.?..], new_tab_order_section.items);
    std.mem.copy(u8, new_buffer[tab_order_start.? + new_tab_order_section.items.len..], buffer[tab_order_start.? + tab_order_section.len..]);

    try file.seekTo(0);
    try file.writeAll(new_buffer);
    try file.setEndPos(new_buffer.len);
}