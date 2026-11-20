#include <cangjie/CHIR/IR/AttributeInfo.h>
#include <flatbuffers/StdxChirFormat_generated.h>
#include <array>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <vector>

using A = Cangjie::CHIR::Attribute;
namespace F = CHIRFormat;

static void require(bool cond, const char* message) {
    if (!cond) throw std::runtime_error(message);
}
static bool has(uint64_t attrs, A attr) {
    return (attrs & (uint64_t{1} << static_cast<unsigned>(attr))) != 0;
}
static bool named(const flatbuffers::String* s, const char* name) { return s && s->str() == name; }

static void core(const F::CHIRPackage& p) {
    require(named(p.name(), "std.core") && p.exprs() && p.exprs_type(), "missing std.core expressions");
    constexpr std::array tags = {F::IntrinsicKind_CANONICALIZE_STRING_BACKING, F::IntrinsicKind_REFERENCE_INVOKE_FINALIZE,
        F::IntrinsicKind_REFERENCE_WAIT_PENDING, F::IntrinsicKind_REFERENCE_RUNTIME_RUNNING,
        F::IntrinsicKind_REFERENCE_NANO_TIME, F::IntrinsicKind_REGISTER_FINALIZER};
    std::array<unsigned, tags.size()> hits{};
    for (unsigned i=0; i<p.exprs()->size(); ++i) {
        if (p.exprs_type()->Get(i) != F::ExpressionElem_IntrinsicBase) continue;
        const auto* call = static_cast<const F::IntrinsicBase*>(p.exprs()->Get(i));
        for (unsigned j=0; j<tags.size(); ++j) if (call->intrinsicKind() == tags[j]) ++hits[j];
    }
    for (unsigned j=0; j<tags.size(); ++j) {
        require(hits[j] != 0, "missing std.core intrinsic");
        std::cout << F::EnumNameIntrinsicKind(tags[j]) << '=' << hits[j] << '\n';
    }
}
static void local(const F::CHIRPackage& p) {
    require(named(p.name(),"local_consumer") && p.phase()==F::Phase_RAW, "expected source package before canonicalization");
    bool field=false, method=false, control=false;
    for (unsigned i=0; i<p.defs()->size(); ++i) {
        if (p.defs_type()->Get(i)!=F::CustomTypeDefElem_ClassDef) continue;
        const auto* d=static_cast<const F::ClassDef*>(p.defs()->Get(i))->base();
        if (!named(d->srcCodeIdentifier(),"Cell")) continue;
        for (const auto* v : *d->instanceMemberVars()) if (named(v->name(),"payload")) {
            field=has(v->attributes(),A::DEMODE) && !has(v->attributes(),A::EXCLAVE);
        }
        for (auto id : *d->methods()) {
            require(id>0 && id<=p.values()->size() && p.values_type()->Get(id-1)==F::ValueElem_Function, "invalid Cell method");
            const auto* f=static_cast<const F::Function*>(p.values()->Get(id-1))->base();
            auto attrs=f->base()->base()->attributes();
            if (named(f->srcCodeIdentifier(),"wireRead")) method=has(attrs,A::EXCLAVE) && !has(attrs,A::DEMODE);
            if (named(f->srcCodeIdentifier(),"read")) control=!has(attrs,A::EXCLAVE) && !has(attrs,A::DEMODE);
        }
    }
    require(field && method && control, "wrong demode field, exclave method, or ordinary method");
    std::cout << "Cell.payload=demode Cell.wireRead=exclave Cell.read=ordinary\n";
}
int main(int argc,char** argv) {
    if (argc!=3) return 2;
    try {
        std::ifstream in(argv[2],std::ios::binary);
        std::vector<char> b((std::istreambuf_iterator<char>(in)),{});
        require(b.size()>=8,"empty CHIR");
        flatbuffers::Verifier verifier(reinterpret_cast<const uint8_t*>(b.data()),b.size());
        require(F::VerifyCHIRPackageBuffer(verifier),"invalid compiler CHIR identifier or schema");
        const auto& p=*F::GetCHIRPackage(b.data());
        if (std::string(argv[1])=="core") core(p);
        else if (std::string(argv[1])=="local") local(p);
        else return 2;
    } catch(const std::exception& e) { std::cerr << e.what() << '\n'; return 1; }
}
