pub const TypeKind = enum(usize) {
    // always type
    name = 1 << 0,

    // integer type
    signed = 1 << 1,

    // basic types
    void = 1 << 2,
    atomic = 1 << 3,
    pointer = 1 << 4,
    field = 1 << 5, // field in struct
    @"struct" = 1 << 6,
};

pub const SafeString = extern struct { ptr: [*]const u8, len: usize };

const VoidInterface = extern struct {};
const SignedInterface = extern struct { signeds: bool };
const NameInterface = extern struct { names: SafeString };
const AtomicInterface = extern struct { sizes: usize, aligns: usize };
const PointerInterface = extern struct { child_type_indies: usize, manys: bool, consts: bool };
const FieldInterface = extern struct { field_type_indicies: usize, field_offsets: usize, field_paddings: usize };
const StructInterface = extern struct { fields_start_indicies: usize, fields_count: usize, tailings: usize };

pub const TypeRegister = MergeToTable(.{ VoidInterface, SignedInterface, NameInterface, AtomicInterface, PointerInterface, FieldInterface, StructInterface });

pub const FunctionKind = enum(usize) {
    void = 1 << 0,
    name = 1 << 1,
    function = 1 << 2,
    argument = 1 << 3,
};

const FunctionInterface = extern struct { ptrs: ?*const anyopaque, returns_type_idx: usize, args_start_indicies: usize, args_count: usize };
const ArgumentInterface = extern struct { args_type_idx: usize };

pub const FunctionRegister = MergeToTable(.{ VoidInterface, NameInterface, FunctionInterface, ArgumentInterface });

// helper merge - combine all interfaces into one structure with a set of arrays
pub fn MergeToTable(comptime Interfaces: anytype) type {
    comptime {
        // Извлекаем поля самого кортежа
        const interfaces_fields = switch (@typeInfo(@TypeOf(Interfaces))) {
            .@"struct" => |s| s.fields,
            else => |any| any.fields,
        };

        // 1. Считаем общее количество полей во всех переданных интерфейсах
        var user_fields_count: usize = 0;
        for (interfaces_fields) |f| {
            const TargetInterface = @field(Interfaces, f.name);
            const fields = switch (@typeInfo(TargetInterface)) {
                .@"struct" => |s| s.fields,
                else => @compileError("Интерфейс " ++ @typeName(TargetInterface) ++ " должен быть структурой!"),
            };
            user_fields_count += fields.len;
        }

        // Заголовок содержит ровно 2 встроенные колонки: _archetype и _count
        const builtins_count = 2;
        const final_fields_count = user_fields_count + builtins_count;

        var field_names: [final_fields_count][]const u8 = undefined;
        var field_types: [final_fields_count]type = undefined;

        // --- Динамический поиск типов метаданных в Zig 0.16 ---
        const dummy_struct_info = @typeInfo(struct { a: u8 }).@"struct";
        const Attrs = @TypeOf(dummy_struct_info.fields[0]).Attributes;

        const dummy_ptr_info = @typeInfo(*u8).pointer;
        const PtrAttrs = @TypeOf(dummy_ptr_info).Attributes;
        // -----------------------------------------------------

        var field_attrs: [final_fields_count]Attrs = undefined;

        // 2. Встроенный фиксированный заголовок таблицы
        field_names[0] = "_archetype";
        field_types[0] = ?@Pointer(.many, PtrAttrs{
            .@"const" = true,
            .@"volatile" = false,
            .@"allowzero" = false,
            .@"addrspace" = .generic,
            .@"align" = @alignOf(usize),
        }, usize, null);
        field_attrs[0] = .{ .@"align" = @alignOf(field_types[0]), .default_value_ptr = null, .@"comptime" = false };

        field_names[1] = "_count";
        field_types[1] = usize;
        field_attrs[1] = .{ .@"align" = @alignOf(usize), .default_value_ptr = null, .@"comptime" = false };

        // 3. Заполнение пользовательских колонок (начиная с индекса 2)
        var current_idx: usize = builtins_count;

        for (interfaces_fields) |f| {
            const TargetInterface = @field(Interfaces, f.name);
            const interface_fields = switch (@typeInfo(TargetInterface)) {
                .@"struct" => |s| s.fields,
                else => unreachable,
            };

            for (interface_fields) |field| {
                field_names[current_idx] = field.name;

                const many_const_ptr = @Pointer(.many, PtrAttrs{
                    .@"const" = true,
                    .@"volatile" = false,
                    .@"allowzero" = false,
                    .@"addrspace" = .generic,
                    .@"align" = @alignOf(field.type),
                }, field.type, null);

                field_types[current_idx] = ?many_const_ptr;
                field_attrs[current_idx] = .{ .@"align" = @alignOf(field_types[current_idx]), .default_value_ptr = null, .@"comptime" = false };
                current_idx += 1;
            }
        }

        return @Struct(.@"extern", null, &field_names, &field_types, &field_attrs);
    }
}
