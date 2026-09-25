package std.core
public open class Object {}
public interface CType {}
public enum Choice { A | B | C }
public const chosen: Choice = Choice.B
public const pair: (Choice, Choice) = (chosen, chosen)
