const std = @import("std");
const root = @import("types.zig"); // Import TypeRegister, TypeKind, SafeString

pub fn TypeRegisterBuilder(comptime types_tuple: anytype) type {
    return struct {
        const Self = @This();
        pub const current_types = types_tuple;

        pub fn init() TypeRegisterBuilder(.{}) {
            return .{};
        }

        pub fn add(self: Self, comptime T: type) TypeRegisterBuilder(current_types ++ .{T}) {
            _ = self;
            return .{};
        }

        /// Final build method. Bakes the data into binary constant memory
        pub fn build(self: Self) root.TypeRegister {
            _ = self;
            @setEvalBranchQuota(200000);

            const UserTypes = current_types;

            // --- STEP 1: COMPTIME LINKING (Return a clean array of types!) ---
            const LinkerTypes = comptime blk: {
                // 1. First count the EXACT number of types (explicit + hidden pointers)
                const total_count = blk_count: {
                    var count: usize = UserTypes.len;
                    for (UserTypes) |T| {
                        if (@typeInfo(T) == .@"struct") {
                            for (@typeInfo(T).@"struct".fields) |field| {
                                if (@typeInfo(field.type) == .pointer) {
                                    var found = false;
                                    for (UserTypes) |existing| {
                                        if (existing == field.type) found = true;
                                    }
                                    if (!found) count += 1;
                                }
                            }
                        }
                    }
                    break :blk_count count;
                };

                // 2. Fill the array with the EXACT final size
                var list: [total_count]type = undefined;
                var idx: usize = 0;

                // Copy explicit types
                for (UserTypes) |T| {
                    list[idx] = T;
                    idx += 1;
                }

                // Append hidden pointer types
                for (UserTypes) |T| {
                    if (@typeInfo(T) == .@"struct") {
                        for (@typeInfo(T).@"struct".fields) |field| {
                            if (@typeInfo(field.type) == .pointer) {
                                var found = false;
                                for (list[0..idx]) |existing| {
                                    if (existing == field.type) found = true;
                                }
                                if (!found) {
                                    list[idx] = field.type;
                                    idx += 1;
                                }
                            }
                        }
                    }
                }

                // Simply return the completed array of types!
                break :blk list;
            };
            // -----------------------------------------------------------------------

            // 2. Count the total number of rows in the SoA table (types + their fields)
            const total_soa_rows = comptime blk: {
                var rows: usize = 0;
                for (LinkerTypes) |T| {
                    rows += 1;
                    switch (@typeInfo(T)) {
                        .@"struct" => |s| rows += s.fields.len,
                        else => {},
                    }
                }
                break :blk rows;
            };

            // 3. Bake all data into a constant container via static constants
            const Storage = comptime blk: {
                var archetypes: [total_soa_rows]usize = std.mem.zeroes([total_soa_rows]usize);
                var signeds: [total_soa_rows]bool = std.mem.zeroes([total_soa_rows]bool);
                var names: [total_soa_rows]root.SafeString = undefined;
                var sizes: [total_soa_rows]usize = std.mem.zeroes([total_soa_rows]usize);
                var aligns: [total_soa_rows]usize = std.mem.zeroes([total_soa_rows]usize);
                var child_type_indies: [total_soa_rows]usize = std.mem.zeroes([total_soa_rows]usize);
                var manys: [total_soa_rows]bool = std.mem.zeroes([total_soa_rows]bool);
                var consts: [total_soa_rows]bool = std.mem.zeroes([total_soa_rows]bool);
                var fields_start_indicies: [total_soa_rows]usize = std.mem.zeroes([total_soa_rows]usize);
                var fields_count: [total_soa_rows]usize = std.mem.zeroes([total_soa_rows]usize);
                var field_type_indicies: [total_soa_rows]usize = std.mem.zeroes([total_soa_rows]usize);
                var field_offsets: [total_soa_rows]usize = std.mem.zeroes([total_soa_rows]usize);
                var field_paddings: [total_soa_rows]usize = std.mem.zeroes([total_soa_rows]usize);
                var tailings: [total_soa_rows]usize = std.mem.zeroes([total_soa_rows]usize);

                var current_row: usize = 0;

                for (LinkerTypes) |T| {
                    const info = @typeInfo(T);
                    var mask: usize = @intFromEnum(root.TypeKind.name);

                    const name = @typeName(T);
                    const static_name = blk_name: {
                        const bytes: [name.len]u8 = name[0..name.len].*;
                        break :blk_name bytes;
                    };
                    names[current_row] = .{ .ptr = &static_name, .len = name.len };

                    switch (info) {
                        .void => mask |= @intFromEnum(root.TypeKind.void),
                        .int => |i| {
                            mask |= @intFromEnum(root.TypeKind.atomic);
                            if (i.signedness == .signed) mask |= @intFromEnum(root.TypeKind.signed);
                            sizes[current_row] = @sizeOf(T);
                            aligns[current_row] = @alignOf(T);
                            signeds[current_row] = (i.signedness == .signed);
                        },
                        .float, .bool => {
                            mask |= @intFromEnum(root.TypeKind.atomic);
                            sizes[current_row] = @sizeOf(T);
                            aligns[current_row] = @alignOf(T);
                        },
                        .pointer => |ptr| {
                            mask |= @intFromEnum(root.TypeKind.pointer);
                            sizes[current_row] = @sizeOf(T);
                            aligns[current_row] = @alignOf(T);

                            child_type_indies[current_row] = findRuntimeTypeIdx(LinkerTypes, ptr.child) orelse @compileError("ABI Linker Error: Pointer refers to type '" ++ @typeName(ptr.child) ++
                                "' which is NOT registered in TypeRegister via .add()!");
                            manys[current_row] = (ptr.size == .many);
                            consts[current_row] = ptr.is_const;
                        },
                        .@"struct" => |s| {
                            mask |= @intFromEnum(root.TypeKind.@"struct");
                            sizes[current_row] = @sizeOf(T);
                            aligns[current_row] = @alignOf(T);
                            fields_count[current_row] = s.fields.len;

                            if (s.fields.len > 0) {
                                const last_field = s.fields[s.fields.len - 1];
                                const last_offset = @offsetOf(T, last_field.name);
                                const last_size = @sizeOf(last_field.type);
                                tailings[current_row] = @sizeOf(T) - (last_offset + last_size);
                            }
                        },
                        else => {},
                    }

                    archetypes[current_row] = mask;
                    current_row += 1;

                    switch (info) {
                        .@"struct" => |s| {
                            fields_start_indicies[current_row - 1] = current_row;
                            for (s.fields) |field| {
                                const f_name = field.name;
                                const static_field_name = blk_fname: {
                                    const bytes: [f_name.len]u8 = f_name[0..f_name.len].*;
                                    break :blk_fname bytes;
                                };

                                archetypes[current_row] = @intFromEnum(root.TypeKind.field) | @intFromEnum(root.TypeKind.name);
                                names[current_row] = .{ .ptr = &static_field_name, .len = f_name.len };

                                const field_idx = findRuntimeTypeIdx(LinkerTypes, field.type) orelse unreachable;
                                field_type_indicies[current_row] = field_idx;

                                const actual_offset = @offsetOf(T, field.name);
                                field_offsets[current_row] = actual_offset;

                                if (actual_offset == 0) {
                                    field_paddings[current_row] = 0;
                                } else {
                                    var closest_prev_offset: usize = 0;
                                    var closest_prev_size: usize = 0;
                                    for (s.fields) |prev_field| {
                                        const p_offset = @offsetOf(T, prev_field.name);
                                        if (p_offset < actual_offset and p_offset >= closest_prev_offset) {
                                            closest_prev_offset = p_offset;
                                            closest_prev_size = @sizeOf(prev_field.type);
                                        }
                                    }
                                    field_paddings[current_row] = actual_offset - (closest_prev_offset + closest_prev_size);
                                }
                                current_row += 1;
                            }
                        },
                        else => {},
                    }
                }
                break :blk struct {
                    pub const archetypes_final = archetypes;
                    pub const signeds_final = signeds;
                    pub const names_final = names;
                    pub const sizes_final = sizes;
                    pub const aligns_final = aligns;
                    pub const child_type_indies_final = child_type_indies;
                    pub const manys_final = manys;
                    pub const consts_final = consts;
                    pub const fields_start_indicies_final = fields_start_indicies;
                    pub const fields_count_final = fields_count;
                    pub const field_type_indicies_final = field_type_indicies;
                    pub const field_offsets_final = field_offsets;
                    pub const field_paddings_final = field_paddings;
                    pub const tailings_final = tailings;
                };
            };
            return root.TypeRegister{
                ._archetype = &Storage.archetypes_final,
                ._count = total_soa_rows,
                .signeds = &Storage.signeds_final,
                .names = &Storage.names_final,
                .sizes = &Storage.sizes_final,
                .aligns = &Storage.aligns_final,
                .child_type_indies = &Storage.child_type_indies_final,
                .manys = &Storage.manys_final,
                .consts = &Storage.consts_final,
                .fields_start_indicies = &Storage.fields_start_indicies_final,
                .fields_count = &Storage.fields_count_final,
                .field_type_indicies = &Storage.field_type_indicies_final,
                .field_offsets = &Storage.field_offsets_final,
                .field_paddings = &Storage.field_paddings_final,
                .tailings = &Storage.tailings_final,
            };
        }
    };
}
fn findRuntimeTypeIdx(comptime tuple: anytype, comptime TargetT: type) ?usize {
    var current_soa_row: usize = 0;
    for (tuple) |T| {
        if (T == TargetT) return current_soa_row;
        current_soa_row += 1;
        switch (@typeInfo(T)) {
            .@"struct" => |s| current_soa_row += s.fields.len,
            else => {},
        }
    }
    return null;
}
