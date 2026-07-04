const std = @import("std");
const builtin = @import("builtin");

const DriverContracts = @import("DriverContracts");

pub fn dumpTypeRegistry(registry: DriverContracts.TypeRegister) void {
    std.debug.print("\n=== ДАМП РЕЕСТРА ТИПОВ (Всего строк: {}) ===\n", .{registry._count});

    var i: usize = 0;
    while (i < registry._count) : (i += 1) {
        // 1. Распаковываем маску архетипа через .?
        const mask = registry._archetype.?[i];
        const kind = @as(usize, mask);

        // 2. Безопасно извлекаем имя
        var name_str: []const u8 = "unnamed";
        if (registry.names) |names_ptr| {
            const safe_str = names_ptr[i];
            name_str = safe_str.ptr[0..safe_str.len];
        }

        // Выводим индекс и имя, оставляя строку открытой для тегов архетипа
        std.debug.print("[Индекс {:3}] Имя: '{s:<15}' | Архетип: (", .{ i, name_str });

        // --- ПРЯМАЯ И НАДЁЖНАЯ ПРОВЕРКА БИТОВ АРХЕТИПА ---
        var printed_any = false;

        if ((kind & @intFromEnum(DriverContracts.TypeKind.name)) != 0) {
            std.debug.print("name", .{});
            printed_any = true;
        }
        if ((kind & @intFromEnum(DriverContracts.TypeKind.signed)) != 0) {
            if (printed_any) std.debug.print("+", .{});
            std.debug.print("signed", .{});
            printed_any = true;
        }
        if ((kind & @intFromEnum(DriverContracts.TypeKind.void)) != 0) {
            if (printed_any) std.debug.print("+", .{});
            std.debug.print("void", .{});
            printed_any = true;
        }
        if ((kind & @intFromEnum(DriverContracts.TypeKind.atomic)) != 0) {
            if (printed_any) std.debug.print("+", .{});
            std.debug.print("atomic", .{});
            printed_any = true;
        }
        if ((kind & @intFromEnum(DriverContracts.TypeKind.pointer)) != 0) {
            if (printed_any) std.debug.print("+", .{});
            std.debug.print("pointer", .{});
            printed_any = true;
        }
        if ((kind & @intFromEnum(DriverContracts.TypeKind.field)) != 0) {
            if (printed_any) std.debug.print("+", .{});
            std.debug.print("field", .{});
            printed_any = true;
        }
        if ((kind & @intFromEnum(DriverContracts.TypeKind.@"struct")) != 0) {
            if (printed_any) std.debug.print("+", .{});
            std.debug.print("struct", .{});
            printed_any = true;
        }

        if (!printed_any) std.debug.print("empty", .{});
        std.debug.print(")\n", .{}); // Закрываем скобку архетипа и переходим на новую строку
        // ------------------------------------------------

        // 3. Вывод деталей для атомарных типов
        if ((kind & @intFromEnum(DriverContracts.TypeKind.atomic)) != 0) {
            const size = if (registry.sizes) |p| p[i] else 0;
            const al = if (registry.aligns) |p| p[i] else 0;
            const signed = if (registry.signeds) |p| p[i] else false;
            std.debug.print("      -> Атомарный: size={} байт, align={}, signed={}\n", .{ size, al, signed });
        }

        // 4. Вывод деталей для указателей
        if ((kind & @intFromEnum(DriverContracts.TypeKind.pointer)) != 0) {
            const child = if (registry.child_type_indies) |p| p[i] else 0;
            const is_many = if (registry.manys) |p| p[i] else false;
            const is_const = if (registry.consts) |p| p[i] else false;
            std.debug.print("      -> Указатель: child_idx={}, many={}, const={}\n", .{ child, is_many, is_const });
        }

        // 5. Вывод деталей для структур
        if ((kind & @intFromEnum(DriverContracts.TypeKind.@"struct")) != 0) {
            const start = if (registry.fields_start_indicies) |p| p[i] else 0;
            const count = if (registry.fields_count) |p| p[i] else 0;
            const tail = if (registry.tailings) |p| p[i] else 0;
            std.debug.print("      -> Структура: старт полей={}, полей={}, tailing padding={} байт\n", .{ start, count, tail });
        }

        // 6. Вывод деталей для полей
        if ((kind & @intFromEnum(DriverContracts.TypeKind.field)) != 0) {
            const type_idx = if (registry.field_type_indicies) |p| p[i] else 0;
            const offset = if (registry.field_offsets) |p| p[i] else 0;
            const pad = if (registry.field_paddings) |p| p[i] else 0;
            std.debug.print("      -> Поле структуры: тип=[{}], offset={} байт, padding перед полем={} байт\n", .{ type_idx, offset, pad });
        }
    }
    std.debug.print("============================================\n\n", .{});
}

pub fn dumpFunctionRegistry(func_registry: DriverContracts.FunctionRegister, type_registry: DriverContracts.TypeRegister) void {
    std.debug.print("\n=== ДАМП РЕЕСТРА ФУНКЦИЙ (Всего строк: {}) ===\n", .{func_registry._count});

    var i: usize = 0;
    while (i < func_registry._count) : (i += 1) {
        // 1. Распаковываем маску архетипа функции
        const mask = func_registry._archetype.?[i];
        const kind = @as(usize, mask);

        // 2. Извлекаем имя функции или аргумента
        var name_str: []const u8 = "unnamed";
        if (func_registry.names) |names_ptr| {
            const safe_str = names_ptr[i];
            name_str = safe_str.ptr[0..safe_str.len];
        }

        std.debug.print("[Индекс {:3}] Имя: '{s:<25}' | Архетип: (", .{ i, name_str });

        // --- ПРОВЕРКА БИТОВ АРХЕТИПА ФУНКЦИИ ---
        var printed_any = false;
        if ((kind & @intFromEnum(DriverContracts.FunctionKind.void)) != 0) {
            std.debug.print("void", .{});
            printed_any = true;
        }
        if ((kind & @intFromEnum(DriverContracts.FunctionKind.name)) != 0) {
            if (printed_any) std.debug.print("+", .{});
            std.debug.print("name", .{});
            printed_any = true;
        }
        if ((kind & @intFromEnum(DriverContracts.FunctionKind.function)) != 0) {
            if (printed_any) std.debug.print("+", .{});
            std.debug.print("function", .{});
            printed_any = true;
        }
        if ((kind & @intFromEnum(DriverContracts.FunctionKind.argument)) != 0) {
            if (printed_any) std.debug.print("+", .{});
            std.debug.print("argument", .{});
            printed_any = true;
        }
        if (!printed_any) std.debug.print("empty", .{});
        std.debug.print(")\n", .{});
        // ---------------------------------------

        // 3. Вывод деталей для самих ФУНКЦИЙ
        if ((kind & @intFromEnum(DriverContracts.FunctionKind.function)) != 0) {
            const f_ptr = if (func_registry.ptrs) |p| p[i] else null;
            const ret_idx = if (func_registry.returns_type_idx) |p| p[i] else 0;
            const args_start = if (func_registry.args_start_indicies) |p| p[i] else 0;
            const args_count = if (func_registry.args_count) |p| p[i] else 0;

            // Ищем имя возвращаемого типа в реестре типов для наглядности лога
            var ret_name: []const u8 = "unknown";
            if (type_registry.names) |t_names| {
                if (ret_idx < type_registry._count) {
                    ret_name = t_names[ret_idx].ptr[0..t_names[ret_idx].len];
                }
            }

            std.debug.print("      -> Адрес в памяти: {?*}, Возвращает: [{}] '{s}', Аргументы: старт={}, кол-во={}\n", .{ f_ptr, ret_idx, ret_name, args_start, args_count });
        }

        // 4. Вывод деталей для АРГУМЕНТОВ функций
        if ((kind & @intFromEnum(DriverContracts.FunctionKind.argument)) != 0) {
            const arg_type_idx = if (func_registry.args_type_idx) |p| p[i] else 0;

            // Ищем имя типа аргумента в реестре типов
            var arg_type_name: []const u8 = "unknown";
            if (type_registry.names) |t_names| {
                if (arg_type_idx < type_registry._count) {
                    arg_type_name = t_names[arg_type_idx].ptr[0..t_names[arg_type_idx].len];
                }
            }

            std.debug.print("      -> Тип аргумента ссылается на: РеестрТипов[{}] '{s}'\n", .{ arg_type_idx, arg_type_name });
        }
    }
    std.debug.print("============================================\n\n", .{});
}

extern "kernel32" fn SetConsoleOutputCP(wCodePageID: u32) callconv(.winapi) i32;
extern "kernel32" fn SetConsoleCP(wCodePageID: u32) callconv(.winapi) i32;

const Other = struct {
    other: u64,
};

const Test = struct {
    a: u32,
    b: u32,
    c: [*]const Other,
    d: void,
};

fn calculate_checksum(val: u7, buf: [*]const Other) u64 {
    _ = val;
    _ = buf;
    return 0;
}

pub fn main(_: std.process.Init) !void {
    if (comptime builtin.os.tag == .windows) {
        _ = SetConsoleOutputCP(65001);
        _ = SetConsoleCP(65001);
    }

    const types: DriverContracts.TypeRegister = comptime DriverContracts.TypeRegisterBuilder.init()
        .add(void)
        .add(u7)
        .add(u32)
        .add(u64)
        .add(Test)
        .add(Other)
        .build();
    dumpTypeRegistry(types);

    const functions: DriverContracts.FunctionRegister = comptime DriverContracts.FunctionRegisterBuilder.init(types)
        .add(calculate_checksum)
        .build();
    dumpFunctionRegistry(functions, types);
}
