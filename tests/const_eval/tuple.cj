// Compile with --no-prelude --emit-chir=opt --output-type=staticlib.
// Literal globals supply interpreter values without relying on local literal
// expression lowering. The tuple forces recursive ConvertToChir consumption.
package std.core
public open class Object {}
public interface CType {}
public const base: Int64 = 41
public const pair: (Int64, Int64) = (base, base)
