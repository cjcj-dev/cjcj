#include <cangjie/CHIR/IR/AttributeInfo.h>
#include <flatbuffers/StdxChirFormat_generated.h>

// The public header and the serializer must expose the same local-mode vocabulary.
auto exclaveAttribute = Cangjie::CHIR::Attribute::EXCLAVE;
auto localSlot(const CHIRFormat::Type& type)
{
    const auto* mode = type.modal();
    return mode && mode->local() == CHIRFormat::Mode_MUST;
}
