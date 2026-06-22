let Words: Array<String> = [
    "item-000", "item-001", "item-002", "item-003", "item-004", "item-005", "item-006", "item-007",
    "item-008", "item-009", "item-010", "item-011", "item-012", "item-013", "item-014", "item-015",
    "item-016", "item-017", "item-018", "item-019", "item-020", "item-021", "item-022", "item-023",
    "item-024", "item-025", "item-026", "item-027", "item-028", "item-029", "item-030", "item-031",
    "item-032", "item-033", "item-034", "item-035", "item-036", "item-037", "item-038", "item-039",
    "item-040", "item-041", "item-042", "item-043", "item-044", "item-045", "item-046", "item-047",
    "item-048", "item-049", "item-050", "item-051", "item-052", "item-053", "item-054", "item-055",
    "item-056", "item-057", "item-058", "item-059", "item-060", "item-061", "item-062", "item-063"
]

main() {
    var total: Int64 = 0
    for (word in Words) {
        total += word.size
    }
    println(Words.size)
    println(total)
}
