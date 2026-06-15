package cangjie_compiler::utils

public class Caster {
    public static func Is<T>(value: Any): Bool {
        return value is T
    }

    public static func As<T>(value: Any): Option<T> {
        if (value is T) {
            return value as T
        }
        return None
    }
}
