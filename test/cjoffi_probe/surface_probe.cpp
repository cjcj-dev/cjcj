#include <cstddef>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

extern "C" {
void *CJOFPackageViewOpen(const unsigned char *, size_t);
void CJOFPackageViewClose(void *);
int CJOFVerifyPackageBuffer(const unsigned char *, size_t);
const unsigned char *CJOFPackageViewGetFullPkgName(const void *, size_t *);
const unsigned char *CJOFPackageViewGetPkgDepInfo(const void *, size_t *);
size_t CJOFPackageViewGetImportCount(const void *);
const unsigned char *CJOFPackageViewGetImportName(const void *, size_t, size_t *);
size_t CJOFPackageViewGetAllFileCount(const void *);
const unsigned char *CJOFPackageViewGetAllFileName(const void *, size_t, size_t *);
size_t CJOFPackageViewGetAllFileImportCount(const void *);
size_t CJOFPackageViewGetAllTypeCount(const void *);
size_t CJOFPackageViewGetAllDeclCount(const void *);
size_t CJOFPackageViewGetAllExprCount(const void *);
unsigned char CJOFPackageViewGetKind(const void *);
unsigned char CJOFPackageViewGetAccess(const void *);
size_t CJOFPackageViewGetAllFileInfoCount(const void *);
size_t CJOFPackageViewGetDependentStdPkgCount(const void *);
const unsigned char *CJOFPackageViewGetDependentStdPkgName(const void *, size_t, size_t *);
unsigned short CJOFPackageViewGetDeclKind(const void *, size_t);
unsigned char CJOFPackageViewGetDeclIsTopLevel(const void *, size_t);
const unsigned char *CJOFPackageViewGetDeclIdentifier(const void *, size_t, size_t *);
const unsigned char *CJOFPackageViewGetDeclFullPkgName(const void *, size_t, size_t *);
const unsigned char *CJOFPackageViewGetDeclExportId(const void *, size_t, size_t *);
const unsigned char *CJOFPackageViewGetDeclMangledName(const void *, size_t, size_t *);
const unsigned char *CJOFPackageViewGetDeclMangledBeforeSema(const void *, size_t, size_t *);
size_t CJOFPackageViewGetDeclGenericArity(const void *, size_t);
unsigned int CJOFPackageViewGetDeclType(const void *, size_t);
unsigned char CJOFPackageViewGetDeclInfoType(const void *, size_t);
}

namespace {
using Field = std::pair<std::string, std::string>;
using Surface = std::vector<Field>;

class ManualFlatBuffer {
public:
    explicit ManualFlatBuffer(const std::vector<unsigned char> &data) : data_(data) {}

    int64_t RootTable() const
    {
        if (data_.size() < 8 || data_[4] != 'C' || data_[5] != 'J' || data_[6] != 'O' || data_[7] != 'F') {
            return -1;
        }
        const int64_t root = ReadU32(0);
        return InBounds(root, 4) ? root : -1;
    }

    int64_t TableField(int64_t table, int64_t slot) const
    {
        if (!InBounds(table, 4)) return -1;
        const int64_t vtable = table - ReadI32(table);
        if (!InBounds(vtable, 4)) return -1;
        const int64_t vtableSize = ReadU16(vtable);
        if (slot < 0 || slot + 2 > vtableSize) return -1;
        const int64_t fieldOffset = ReadU16(vtable + slot);
        if (fieldOffset == 0) return -1;
        const int64_t fieldPos = table + fieldOffset;
        return InBounds(fieldPos, 1) ? fieldPos : -1;
    }

    int64_t OffsetField(int64_t table, int64_t slot) const { return Indirect(TableField(table, slot)); }

    int64_t VectorField(int64_t table, int64_t slot) const
    {
        const int64_t target = OffsetField(table, slot);
        return InBounds(target, 4) ? target : -1;
    }

    std::string StringField(int64_t table, int64_t slot) const { return StringAt(OffsetField(table, slot)); }

    uint8_t U8Field(int64_t table, int64_t slot, uint8_t defaultValue) const
    {
        const int64_t pos = TableField(table, slot);
        return pos >= 0 && InBounds(pos, 1) ? data_[pos] : defaultValue;
    }

    uint16_t U16Field(int64_t table, int64_t slot, uint16_t defaultValue) const
    {
        const int64_t pos = TableField(table, slot);
        return pos >= 0 ? ReadU16(pos) : defaultValue;
    }

    uint32_t U32Field(int64_t table, int64_t slot, uint32_t defaultValue) const
    {
        const int64_t pos = TableField(table, slot);
        return pos >= 0 ? ReadU32(pos) : defaultValue;
    }

    int64_t VectorLength(int64_t vector) const { return InBounds(vector, 4) ? ReadU32(vector) : 0; }

    int64_t VectorOffsetElement(int64_t vector, int64_t index) const
    {
        return Indirect(vector + 4 + index * 4);
    }

    std::string StringAt(int64_t pos) const
    {
        if (!InBounds(pos, 4)) return {};
        const int64_t len = ReadU32(pos);
        const int64_t start = pos + 4;
        if (len < 0 || !InBounds(start, len)) return {};
        return std::string(reinterpret_cast<const char *>(data_.data() + start), static_cast<size_t>(len));
    }

private:
    bool InBounds(int64_t pos, int64_t width) const
    {
        return pos >= 0 && width >= 0 && static_cast<uint64_t>(pos) + static_cast<uint64_t>(width) <= data_.size();
    }

    int64_t Indirect(int64_t pos) const
    {
        if (!InBounds(pos, 4)) return -1;
        const int64_t target = pos + ReadU32(pos);
        return InBounds(target, 1) ? target : -1;
    }

    uint16_t ReadU16(int64_t pos) const
    {
        if (!InBounds(pos, 2)) return 0;
        return static_cast<uint16_t>(data_[pos]) | static_cast<uint16_t>(data_[pos + 1]) << 8;
    }

    uint32_t ReadU32(int64_t pos) const
    {
        if (!InBounds(pos, 4)) return 0;
        return static_cast<uint32_t>(data_[pos]) | static_cast<uint32_t>(data_[pos + 1]) << 8 |
            static_cast<uint32_t>(data_[pos + 2]) << 16 | static_cast<uint32_t>(data_[pos + 3]) << 24;
    }

    int64_t ReadI32(int64_t pos) const { return static_cast<int32_t>(ReadU32(pos)); }

    const std::vector<unsigned char> &data_;
};

std::string Bytes(const unsigned char *value, size_t length)
{
    return value == nullptr ? std::string("<NULL>")
                            : std::string(reinterpret_cast<const char *>(value), length);
}

#define READ_BORROWED(Call) ([&]() { \
    size_t borrowedLength = 0; \
    const unsigned char *borrowedValue = (Call); \
    return Bytes(borrowedValue, borrowedLength); \
}())

std::string Hex(const std::string &value)
{
    std::ostringstream out;
    out << std::hex << std::setfill('0');
    for (unsigned char byte : value) out << std::setw(2) << static_cast<unsigned int>(byte);
    return out.str();
}

void Add(Surface &surface, std::string name, std::string value)
{
    surface.emplace_back(std::move(name), std::move(value));
}

template <typename T> void AddNumber(Surface &surface, std::string name, T value)
{
    Add(surface, std::move(name), std::to_string(value));
}

bool ManualSurface(const std::vector<unsigned char> &data, Surface &values)
{
    if (data.empty() || CJOFVerifyPackageBuffer(data.data(), data.size()) == 0) return false;
    const ManualFlatBuffer reader(data);
    const int64_t root = reader.RootTable();
    if (root < 0) return false;
    Add(values, "pkg.fullPkgName", reader.StringField(root, 8));
    Add(values, "pkg.pkgDepInfo", reader.StringField(root, 10));

    const int64_t imports = reader.VectorField(root, 12);
    const int64_t importCount = reader.VectorLength(imports);
    AddNumber(values, "pkg.imports.count", importCount);
    for (int64_t i = 0; i < importCount; ++i) {
        Add(values, "pkg.imports[" + std::to_string(i) + "]", reader.StringAt(reader.VectorOffsetElement(imports, i)));
    }

    const int64_t allFiles = reader.VectorField(root, 14);
    const int64_t allFileCount = reader.VectorLength(allFiles);
    AddNumber(values, "pkg.allFiles.count", allFileCount);
    for (int64_t i = 0; i < allFileCount; ++i) {
        Add(values, "pkg.allFiles[" + std::to_string(i) + "]", reader.StringAt(reader.VectorOffsetElement(allFiles, i)));
    }

    AddNumber(values, "pkg.allFileImports.count", reader.VectorLength(reader.VectorField(root, 16)));
    AddNumber(values, "pkg.allTypes.count", reader.VectorLength(reader.VectorField(root, 18)));
    const int64_t allDecls = reader.VectorField(root, 20);
    const int64_t declCount = reader.VectorLength(allDecls);
    AddNumber(values, "pkg.allDecls.count", declCount);
    AddNumber(values, "pkg.allExprs.count", reader.VectorLength(reader.VectorField(root, 22)));
    AddNumber(values, "pkg.kind", reader.U8Field(root, 26, 0));
    AddNumber(values, "pkg.access", reader.U8Field(root, 28, 0));
    AddNumber(values, "pkg.allFileInfo.count", reader.VectorLength(reader.VectorField(root, 32)));

    const int64_t stdPkgs = reader.VectorField(root, 34);
    const int64_t stdPkgCount = reader.VectorLength(stdPkgs);
    AddNumber(values, "pkg.allDependentStdPkgs.count", stdPkgCount);
    for (int64_t i = 0; i < stdPkgCount; ++i) {
        Add(values, "pkg.allDependentStdPkgs[" + std::to_string(i) + "]",
            reader.StringAt(reader.VectorOffsetElement(stdPkgs, i)));
    }

    for (int64_t i = 0; i < declCount; ++i) {
        const int64_t decl = reader.VectorOffsetElement(allDecls, i);
        const std::string prefix = "decl[" + std::to_string(i) + "].";
        AddNumber(values, prefix + "kind", reader.U16Field(decl, 4, 0));
        AddNumber(values, prefix + "isTopLevel", reader.U8Field(decl, 6, 0));
        Add(values, prefix + "identifier", reader.StringField(decl, 18));
        Add(values, prefix + "fullPkgName", reader.StringField(decl, 8));
        Add(values, prefix + "exportId", reader.StringField(decl, 30));
        Add(values, prefix + "mangledName", reader.StringField(decl, 28));
        Add(values, prefix + "mangledBeforeSema", reader.StringField(decl, 32));
        const int64_t generic = reader.OffsetField(decl, 12);
        AddNumber(values, prefix + "genericArity",
            generic >= 0 ? reader.VectorLength(reader.VectorField(generic, 4)) : 0);
        AddNumber(values, prefix + "type", reader.U32Field(decl, 26, 0));
        AddNumber(values, prefix + "infoType", reader.U8Field(decl, 36, 0));
    }
    return true;
}

bool OfficialSurface(const std::vector<unsigned char> &data, Surface &values)
{
    void *raw = data.empty() ? nullptr : CJOFPackageViewOpen(data.data(), data.size());
    if (raw == nullptr) return false;
    Add(values, "pkg.fullPkgName", READ_BORROWED(CJOFPackageViewGetFullPkgName(raw, &borrowedLength)));
    Add(values, "pkg.pkgDepInfo", READ_BORROWED(CJOFPackageViewGetPkgDepInfo(raw, &borrowedLength)));

    const size_t importCount = CJOFPackageViewGetImportCount(raw);
    AddNumber(values, "pkg.imports.count", importCount);
    for (size_t i = 0; i < importCount; ++i) {
        Add(values, "pkg.imports[" + std::to_string(i) + "]",
            READ_BORROWED(CJOFPackageViewGetImportName(raw, i, &borrowedLength)));
    }

    const size_t allFileCount = CJOFPackageViewGetAllFileCount(raw);
    AddNumber(values, "pkg.allFiles.count", allFileCount);
    for (size_t i = 0; i < allFileCount; ++i) {
        Add(values, "pkg.allFiles[" + std::to_string(i) + "]",
            READ_BORROWED(CJOFPackageViewGetAllFileName(raw, i, &borrowedLength)));
    }

    AddNumber(values, "pkg.allFileImports.count", CJOFPackageViewGetAllFileImportCount(raw));
    AddNumber(values, "pkg.allTypes.count", CJOFPackageViewGetAllTypeCount(raw));
    const size_t declCount = CJOFPackageViewGetAllDeclCount(raw);
    AddNumber(values, "pkg.allDecls.count", declCount);
    AddNumber(values, "pkg.allExprs.count", CJOFPackageViewGetAllExprCount(raw));
    AddNumber(values, "pkg.kind", CJOFPackageViewGetKind(raw));
    AddNumber(values, "pkg.access", CJOFPackageViewGetAccess(raw));
    AddNumber(values, "pkg.allFileInfo.count", CJOFPackageViewGetAllFileInfoCount(raw));

    const size_t stdPkgCount = CJOFPackageViewGetDependentStdPkgCount(raw);
    AddNumber(values, "pkg.allDependentStdPkgs.count", stdPkgCount);
    for (size_t i = 0; i < stdPkgCount; ++i) {
        Add(values, "pkg.allDependentStdPkgs[" + std::to_string(i) + "]",
            READ_BORROWED(CJOFPackageViewGetDependentStdPkgName(raw, i, &borrowedLength)));
    }

    for (size_t i = 0; i < declCount; ++i) {
        const std::string prefix = "decl[" + std::to_string(i) + "].";
        AddNumber(values, prefix + "kind", CJOFPackageViewGetDeclKind(raw, i));
        AddNumber(values, prefix + "isTopLevel", CJOFPackageViewGetDeclIsTopLevel(raw, i));
        Add(values, prefix + "identifier",
            READ_BORROWED(CJOFPackageViewGetDeclIdentifier(raw, i, &borrowedLength)));
        Add(values, prefix + "fullPkgName",
            READ_BORROWED(CJOFPackageViewGetDeclFullPkgName(raw, i, &borrowedLength)));
        Add(values, prefix + "exportId",
            READ_BORROWED(CJOFPackageViewGetDeclExportId(raw, i, &borrowedLength)));
        Add(values, prefix + "mangledName",
            READ_BORROWED(CJOFPackageViewGetDeclMangledName(raw, i, &borrowedLength)));
        Add(values, prefix + "mangledBeforeSema",
            READ_BORROWED(CJOFPackageViewGetDeclMangledBeforeSema(raw, i, &borrowedLength)));
        AddNumber(values, prefix + "genericArity", CJOFPackageViewGetDeclGenericArity(raw, i));
        AddNumber(values, prefix + "type", CJOFPackageViewGetDeclType(raw, i));
        AddNumber(values, prefix + "infoType", CJOFPackageViewGetDeclInfoType(raw, i));
    }
    CJOFPackageViewClose(raw);
    return true;
}

#undef READ_BORROWED

std::vector<unsigned char> ReadFile(const std::string &path)
{
    std::ifstream input(path, std::ios::binary);
    return std::vector<unsigned char>(std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>());
}

int Probe(const std::string &path)
{
    const auto data = ReadFile(path);
    Surface official;
    Surface manual;
    const bool officialOk = OfficialSurface(data, official);
    const bool manualOk = ManualSurface(data, manual);
    char klass = '?';
    if (officialOk && !manualOk) klass = 'A';
    else if (!officialOk && manualOk) klass = 'C';
    else if (officialOk && manualOk) klass = official == manual ? 'D' : 'B';

    std::cout << "RESULT\t" << klass << "\tchecks=" << (officialOk ? official.size() : 0) << "\t" << path << '\n';
    if (klass == 'B') {
        const size_t common = std::min(official.size(), manual.size());
        size_t index = 0;
        while (index < common && official[index] == manual[index]) ++index;
        if (index < common) {
            std::cout << "DIFF\t" << path << "\tfield=" << official[index].first
                      << "\tofficial_hex=" << Hex(official[index].second)
                      << "\tmanual_hex=" << Hex(manual[index].second) << '\n';
        } else {
            std::cout << "DIFF\t" << path << "\tsize_official=" << official.size()
                      << "\tsize_manual=" << manual.size() << '\n';
        }
    }
    return klass == '?' ? 2 : 0;
}
} // namespace

int main(int argc, char **argv)
{
    if (argc < 2) return 2;
    int result = 0;
    for (int i = 1; i < argc; ++i) result |= Probe(argv[i]);
    return result;
}
