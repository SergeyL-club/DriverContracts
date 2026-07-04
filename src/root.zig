const types = @import("types.zig");

pub const TypeKind = types.TypeKind;
pub const TypeRegister = types.TypeRegister;

pub const FunctionKind = types.FunctionKind;
pub const FunctionRegister = types.FunctionRegister;

pub const TypeRegisterBuilder = @import("type_register_builder.zig").TypeRegisterBuilder(.{});
pub const FunctionRegisterBuilder = @import("function_register_builder.zig").FunctionRegisterBuilder(null, .{});
