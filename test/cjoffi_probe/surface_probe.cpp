#include <cstddef>
#include <cstdint>
#include <chrono>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

#include "flatbuffers/ModuleFormat_generated.h"

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
int CJOFPackageViewGetReadSurfaceFingerprint(
    const void *, uint64_t *, uint64_t *, uint64_t *, size_t);
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

    uint8_t U8(int64_t pos, uint8_t defaultValue) const
    {
        return InBounds(pos, 1) ? data_[pos] : defaultValue;
    }

    uint16_t U16(int64_t pos, uint16_t defaultValue) const
    {
        return InBounds(pos, 2) ? ReadU16(pos) : defaultValue;
    }

    uint32_t U32(int64_t pos, uint32_t defaultValue) const
    {
        return InBounds(pos, 4) ? ReadU32(pos) : defaultValue;
    }

    uint64_t U64(int64_t pos, uint64_t defaultValue) const
    {
        return InBounds(pos, 8) ? ReadU64(pos) : defaultValue;
    }

    int8_t I8(int64_t pos, int8_t defaultValue) const
    {
        return InBounds(pos, 1) ? static_cast<int8_t>(data_[pos]) : defaultValue;
    }

    int16_t I16(int64_t pos, int16_t defaultValue) const
    {
        return InBounds(pos, 2) ? static_cast<int16_t>(ReadU16(pos)) : defaultValue;
    }

    int32_t I32(int64_t pos, int32_t defaultValue) const
    {
        return InBounds(pos, 4) ? static_cast<int32_t>(ReadU32(pos)) : defaultValue;
    }

    int64_t I64(int64_t pos, int64_t defaultValue) const
    {
        return InBounds(pos, 8) ? static_cast<int64_t>(ReadU64(pos)) : defaultValue;
    }

    int64_t VectorLength(int64_t vector) const { return InBounds(vector, 4) ? ReadU32(vector) : 0; }

    int64_t VectorOffsetElement(int64_t vector, int64_t index) const
    {
        return Indirect(vector + 4 + index * 4);
    }

    int64_t VectorStructElement(int64_t vector, int64_t index, int64_t width) const
    {
        const int64_t pos = vector + 4 + index * width;
        return InBounds(pos, width) ? pos : -1;
    }

    uint8_t VectorU8(int64_t vector, int64_t index) const { return U8(vector + 4 + index, 0); }
    uint16_t VectorU16(int64_t vector, int64_t index) const { return U16(vector + 4 + index * 2, 0); }
    uint32_t VectorU32(int64_t vector, int64_t index) const { return U32(vector + 4 + index * 4, 0); }
    uint64_t VectorU64(int64_t vector, int64_t index) const { return U64(vector + 4 + index * 8, 0); }
    int8_t VectorI8(int64_t vector, int64_t index) const { return I8(vector + 4 + index, 0); }
    int16_t VectorI16(int64_t vector, int64_t index) const { return I16(vector + 4 + index * 2, 0); }
    int32_t VectorI32(int64_t vector, int64_t index) const { return I32(vector + 4 + index * 4, 0); }
    int64_t VectorI64(int64_t vector, int64_t index) const { return I64(vector + 4 + index * 8, 0); }

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

    uint64_t ReadU64(int64_t pos) const
    {
        if (!InBounds(pos, 8)) return 0;
        uint64_t result = 0;
        for (unsigned int index = 0; index < 8; ++index) {
            result |= static_cast<uint64_t>(data_[pos + index]) << (index * 8);
        }
        return result;
    }

    int64_t ReadI32(int64_t pos) const { return static_cast<int32_t>(ReadU32(pos)); }

    const std::vector<unsigned char> &data_;
};

constexpr size_t READ_SURFACE_FIELD_COUNT = 217;

struct ReadSurfaceFingerprint {
    uint64_t hits[READ_SURFACE_FIELD_COUNT] = {};
    uint64_t fnv[READ_SURFACE_FIELD_COUNT] = {};
    uint64_t mix[READ_SURFACE_FIELD_COUNT] = {};
};

void ReadSurfaceByte(ReadSurfaceFingerprint &out, size_t field, unsigned char byte)
{
    out.fnv[field] ^= byte;
    out.fnv[field] *= 1099511628211ULL;
    out.mix[field] ^= static_cast<uint64_t>(byte) + 0x9eU;
    out.mix[field] *= 0x9e3779b185ebca87ULL;
}

void ReadSurfaceAdd(ReadSurfaceFingerprint &out, size_t field, uint64_t value)
{
    for (unsigned int shift = 0; shift < 64; shift += 8) {
        ReadSurfaceByte(out, field, static_cast<unsigned char>(value >> shift));
    }
}

void ReadSurfaceBegin(ReadSurfaceFingerprint &out, size_t field)
{
    if (out.hits[field]++ == 0) {
        out.fnv[field] = 14695981039346656037ULL;
        out.mix[field] = 0xd6e8feb86659fd93ULL;
    }
    ReadSurfaceAdd(out, field, 0xc10f000000000000ULL | field);
}

void ReadSurfaceString(ReadSurfaceFingerprint &out, size_t field, const std::string &value)
{
    ReadSurfaceAdd(out, field, value.size());
    for (unsigned char byte : value) ReadSurfaceByte(out, field, byte);
}

#include "cjo_read_surface_manual.inc"

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

bool ManualReadSurface(const std::vector<unsigned char> &data, ReadSurfaceFingerprint &out)
{
    if (data.empty() || CJOFVerifyPackageBuffer(data.data(), data.size()) == 0) return false;
    const ManualFlatBuffer reader(data);
    const int64_t root = reader.RootTable();
    if (root < 0) return false;
    WalkManual_Package(reader, root, out);
    return true;
}

bool OfficialReadSurface(const std::vector<unsigned char> &data, ReadSurfaceFingerprint &out)
{
    void *raw = data.empty() ? nullptr : CJOFPackageViewOpen(data.data(), data.size());
    if (raw == nullptr) return false;
    const bool okay = CJOFPackageViewGetReadSurfaceFingerprint(
        raw, out.hits, out.fnv, out.mix, READ_SURFACE_FIELD_COUNT) != 0;
    CJOFPackageViewClose(raw);
    return okay;
}

bool EqualReadSurface(const ReadSurfaceFingerprint &left, const ReadSurfaceFingerprint &right)
{
    for (size_t field = 0; field < READ_SURFACE_FIELD_COUNT; ++field) {
        if (left.hits[field] != right.hits[field] || left.fnv[field] != right.fnv[field] ||
            left.mix[field] != right.mix[field]) return false;
    }
    return true;
}

size_t SurfaceEvents(const ReadSurfaceFingerprint &value)
{
    size_t result = 0;
    for (uint64_t count : value.hits) result += count;
    return result;
}

size_t SurfaceGroups(const ReadSurfaceFingerprint &value)
{
    size_t result = 0;
    for (uint64_t count : value.hits) result += count != 0;
    return result;
}

std::pair<uint64_t, uint64_t> BufferFingerprint(const std::vector<unsigned char> &data)
{
    uint64_t fnv = 14695981039346656037ULL;
    uint64_t mix = 0xd6e8feb86659fd93ULL;
    for (unsigned char byte : data) {
        fnv = (fnv ^ byte) * 1099511628211ULL;
        mix = (mix ^ (static_cast<uint64_t>(byte) + 0x9eU)) * 0x9e3779b185ebca87ULL;
    }
    return {fnv, mix};
}

void DiagnoseDeclDependencies(const std::vector<unsigned char> &data, const ManualFlatBuffer &reader)
{
    const auto *package = PackageFormat::GetPackage(data.data());
    const auto *officialDecls = package->allDecls();
    const int64_t manualDecls = reader.VectorField(reader.RootTable(), 20);
    const size_t count = officialDecls == nullptr ? 0 : officialDecls->size();
    for (size_t index = 0; index < count; ++index) {
        const auto *officialDeps = officialDecls->Get(index)->dependencies();
        const int64_t manualDecl = reader.VectorOffsetElement(manualDecls, index);
        const int64_t manualDeps = reader.VectorField(manualDecl, 40);
        const size_t officialCount = officialDeps == nullptr ? 0 : officialDeps->size();
        const size_t manualCount = reader.VectorLength(manualDeps);
        if ((officialDeps != nullptr) != (manualDeps >= 0) || officialCount != manualCount) {
            std::cout << "DEBUG112\tdecl=" << index << "\tofficial_present=" << (officialDeps != nullptr)
                      << "\tmanual_present=" << (manualDeps >= 0) << "\tofficial_count=" << officialCount
                      << "\tmanual_count=" << manualCount << '\n';
            return;
        }
    }
}

#undef READ_BORROWED

std::vector<unsigned char> ReadFile(const std::string &path)
{
    std::ifstream input(path, std::ios::binary);
    return std::vector<unsigned char>(std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>());
}

char Probe(const std::string &path, ReadSurfaceFingerprint &aggregate)
{
    const auto data = ReadFile(path);
    const auto before = BufferFingerprint(data);
    const auto timeNs = std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
    ReadSurfaceFingerprint official;
    ReadSurfaceFingerprint manual;
    const bool officialOk = OfficialReadSurface(data, official);
    const bool manualOk = ManualReadSurface(data, manual);
    const auto after = BufferFingerprint(data);
    char klass = '?';
    if (officialOk && !manualOk) klass = 'A';
    else if (!officialOk && manualOk) klass = 'C';
    else if (officialOk && manualOk) klass = EqualReadSurface(official, manual) ? 'D' : 'B';

    if (officialOk) {
        for (size_t field = 0; field < READ_SURFACE_FIELD_COUNT; ++field) {
            aggregate.hits[field] += official.hits[field];
            if (aggregate.fnv[field] == 0 && official.hits[field] != 0) aggregate.fnv[field] = 1;
        }
    }
    std::cout << "RESULT\t" << klass << "\tchecks=" << (officialOk ? SurfaceEvents(official) : 0)
              << "\tgroups=" << (officialOk ? SurfaceGroups(official) : 0) << "\t" << path << '\n';
    if (klass == 'B') {
        for (size_t field = 0; field < READ_SURFACE_FIELD_COUNT; ++field) {
            if (official.hits[field] != manual.hits[field] || official.fnv[field] != manual.fnv[field] ||
                official.mix[field] != manual.mix[field]) {
                std::cout << "DIFF\t" << path << "\tfield_id=" << field
                          << "\tofficial_hits=" << official.hits[field]
                          << "\tmanual_hits=" << manual.hits[field]
                          << "\tofficial_fnv=" << official.fnv[field]
                          << "\tmanual_fnv=" << manual.fnv[field]
                          << "\tofficial_mix=" << official.mix[field]
                          << "\tmanual_mix=" << manual.mix[field] << '\n';
                if (field == 112) DiagnoseDeclDependencies(data, ManualFlatBuffer(data));
                break;
            }
        }
    }
    if (before != after || before.first == 0 || before.second == 0 || after.first == 0 || after.second == 0) {
        std::cout << "MEMORY_ALERT\t" << path << "\taddr=" << static_cast<const void *>(data.data())
                  << "\ttime_ns=" << timeNs << "\tbefore_fnv=" << before.first << "\tbefore_mix=" << before.second
                  << "\tafter_fnv=" << after.first << "\tafter_mix=" << after.second << '\n';
    }
    return klass;
}
} // namespace

int main(int argc, char **argv)
{
    if (argc < 2) return 2;
    size_t counts[4] = {};
    size_t unknown = 0;
    ReadSurfaceFingerprint aggregate;
    for (int i = 1; i < argc; ++i) {
        const char klass = Probe(argv[i], aggregate);
        if (klass >= 'A' && klass <= 'D') ++counts[klass - 'A']; else ++unknown;
    }
    std::cout << "SUMMARY\tN=" << (argc - 1) << "\tA=" << counts[0] << "\tB=" << counts[1]
              << "\tC=" << counts[2] << "\tD=" << counts[3] << "\tUNKNOWN=" << unknown
              << "\tFIELD_GROUPS=" << SurfaceGroups(aggregate)
              << "\tCHECKS=" << SurfaceEvents(aggregate) << '\n';
    std::cout << "UNHIT_IDS";
    for (size_t field = 0; field < READ_SURFACE_FIELD_COUNT; ++field) {
        if (aggregate.hits[field] == 0) std::cout << '\t' << field;
    }
    std::cout << '\n';
    return unknown == 0 ? 0 : 2;
}
