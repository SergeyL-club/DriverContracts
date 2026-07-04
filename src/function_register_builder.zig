const std = @import("std");
const root = @import("types.zig"); // Import FunctionRegister, FunctionKind, TypeRegister, SafeString

pub fn FunctionRegisterBuilder(comptime type_registry: ?root.TypeRegister, comptime funcs_tuple: anytype) type {
    return struct {
        const Self = @This();

        // Store the type registry and current functions in the builder namespace
        pub const baked_types = type_registry;
        pub const current_funcs = funcs_tuple;

        // Initialize the builder, binding it tightly to a specific type registry
        pub fn init(comptime registry: root.TypeRegister) FunctionRegisterBuilder(registry, .{}) {
            return .{};
        }

        // Add a function. Returns a NEW builder type with an extended function tuple
        pub fn add(self: Self, comptime func: anytype) FunctionRegisterBuilder(baked_types, current_funcs ++ .{func}) {
            _ = self;
            return .{};
        }

        // Final build method. It is now pure and requires no arguments!
        pub fn build(self: Self) root.FunctionRegister {
            _ = self;
            @setEvalBranchQuota(100000);

            const Funcs = current_funcs;
            const registry = baked_types;

            // 1. Count the total number of rows in the function SoA table (functions + arguments)
            const total_soa_rows = comptime blk: {
                var rows: usize = 0;
                for (Funcs) |func_val| {
                    rows += 1;
                    const f_info = @typeInfo(@TypeOf(func_val)).@"fn";
                    rows += f_info.params.len;
                }
                break :blk rows;
            };

            // 2. Bake all data into a constant container via static constants
            const Storage = comptime blk: {
                var archetypes: [total_soa_rows]usize = std.mem.zeroes([total_soa_rows]usize);
                var names: [total_soa_rows]root.SafeString = undefined;
                var ptrs: [total_soa_rows]?*const anyopaque = std.mem.zeroes([total_soa_rows]?*const anyopaque);
                var returns_type_idx: [total_soa_rows]usize = std.mem.zeroes([total_soa_rows]usize);
                var args_start_indicies: [total_soa_rows]usize = std.mem.zeroes([total_soa_rows]usize);
                var args_count: [total_soa_rows]usize = std.mem.zeroes([total_soa_rows]usize);
                var args_type_idx: [total_soa_rows]usize = std.mem.zeroes([total_soa_rows]usize);

                var current_row: usize = 0;
                const total_funcs_count = Funcs.len;
                var current_arg_row = total_funcs_count; // Arguments come immediately after all functions

                for (Funcs) |func_val| {
                    const T = @TypeOf(func_val);
                    const f_info = @typeInfo(T).@"fn";

                    // Bake the function name
                    const f_name_literal = @typeName(T);
                    const static_name = blk_name: {
                        const bytes: [f_name_literal.len]u8 = f_name_literal[0..f_name_literal.len].*;
                        break :blk_name bytes;
                    };

                    archetypes[current_row] = @intFromEnum(root.FunctionKind.function) | @intFromEnum(root.FunctionKind.name);
                    names[current_row] = .{ .ptr = &static_name, .len = f_name_literal.len };
                    ptrs[current_row] = @as(?*const anyopaque, @ptrCast(&func_val));

                    // Find the function return type in the bound type registry
                    const ret_type = f_info.return_type orelse void;
                    if (findTypeIndexInRegistry(registry.?, ret_type)) |t_idx| {
                        returns_type_idx[current_row] = t_idx;
                    } else {
                        @compileError("Function Linker Error: Function '" ++ @typeName(T) ++
                            "' returns type '" ++ @typeName(ret_type) ++ "', which is NOT registered in TypeRegister!");
                    }

                    // Bind the function to its argument range
                    args_start_indicies[current_row] = current_arg_row;
                    args_count[current_row] = f_info.params.len;

                    // Fill in the arguments for this function
                    for (f_info.params, 0..) |param, p_idx| {
                        const arg_type = param.type.?;

                        // Generate the argument name "arg0", "arg1" ...
                        const arg_name_literal = std.fmt.comptimePrint("arg{}", .{p_idx});
                        const static_arg_name = blk_aname: {
                            const bytes: [arg_name_literal.len]u8 = arg_name_literal[0..arg_name_literal.len].*;
                            break :blk_aname bytes;
                        };

                        archetypes[current_arg_row] = @intFromEnum(root.FunctionKind.argument) | @intFromEnum(root.FunctionKind.name);
                        names[current_arg_row] = .{ .ptr = &static_arg_name, .len = arg_name_literal.len };

                        // Find the argument type in the bound type registry
                        if (findTypeIndexInRegistry(registry.?, arg_type)) |t_idx| {
                            args_type_idx[current_arg_row] = t_idx;
                        } else {
                            @compileError("Function Linker Error: Function '" ++ @typeName(T) ++
                                "' requires argument #" ++ std.fmt.comptimePrint("{}", .{p_idx}) ++
                                " of type '" ++ @typeName(arg_type) ++ "', which is NOT registered in TypeRegister!");
                        }

                        current_arg_row += 1;
                    }

                    current_row += 1;
                }

                // Convert var arrays into a named static container
                break :blk struct {
                    pub const archetypes_final = archetypes;
                    pub const names_final = names;
                    pub const ptrs_final = ptrs;
                    pub const returns_type_idx_final = returns_type_idx;
                    pub const args_start_indicies_final = args_start_indicies;
                    pub const args_count_final = args_count;
                    pub const args_type_idx_final = args_type_idx;
                };
            };

            // 3. Return the populated FunctionRegister, referencing stable Storage constants
            return root.FunctionRegister{
                ._archetype = &Storage.archetypes_final,
                ._count = total_soa_rows,
                .names = &Storage.names_final,
                .ptrs = &Storage.ptrs_final,
                .returns_type_idx = &Storage.returns_type_idx_final,
                .args_start_indicies = &Storage.args_start_indicies_final,
                .args_count = &Storage.args_count_final,
                .args_type_idx = &Storage.args_type_idx_final,
            };
        }
    };
}

fn findTypeIndexInRegistry(comptime registry: root.TypeRegister, comptime T: type) ?usize {
    const target_name = @typeName(T);
    var i: usize = 0;
    while (i < registry._count) : (i += 1) {
        const reg_name = registry.names.?[i];
        const reg_slice = reg_name.ptr[0..reg_name.len];
        if (std.mem.eql(u8, reg_slice, target_name)) {
            return i;
        }
    }
    return null;
}
