#include <cstdint>
#include <cstdio>
#include <vector>

#include "flatbuffers/flatbuffer_builder.h"

namespace {
struct Payload {};
struct Item {};
struct Root {};

flatbuffers::Offset<Payload> CreatePayload(flatbuffers::FlatBufferBuilder &builder, int64_t value) {
  const auto start = builder.StartTable();
  builder.AddElement<int64_t>(flatbuffers::FieldIndexToOffset(0), value, 0);
  return flatbuffers::Offset<Payload>(builder.EndTable(start));
}

flatbuffers::Offset<Item> CreateItem(
    flatbuffers::FlatBufferBuilder &builder,
    flatbuffers::Offset<flatbuffers::String> name,
    flatbuffers::Offset<flatbuffers::Vector<uint32_t>> values,
    uint8_t payload_type,
    flatbuffers::Offset<Payload> payload) {
  const auto start = builder.StartTable();
  builder.AddOffset(flatbuffers::FieldIndexToOffset(3), payload);
  builder.AddElement<uint8_t>(flatbuffers::FieldIndexToOffset(2), payload_type, 0);
  builder.AddOffset(flatbuffers::FieldIndexToOffset(1), values);
  builder.AddOffset(flatbuffers::FieldIndexToOffset(0), name);
  return flatbuffers::Offset<Item>(builder.EndTable(start));
}

flatbuffers::Offset<Root> CreateRoot(
    flatbuffers::FlatBufferBuilder &builder,
    flatbuffers::Offset<flatbuffers::String> title,
    flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<Item>>> items) {
  const auto start = builder.StartTable();
  builder.AddOffset(flatbuffers::FieldIndexToOffset(1), items);
  builder.AddOffset(flatbuffers::FieldIndexToOffset(0), title);
  return flatbuffers::Offset<Root>(builder.EndTable(start));
}
}  // namespace

int main() {
  flatbuffers::FlatBufferBuilder builder;
  const auto title = builder.CreateSharedString("same");
  const auto name = builder.CreateSharedString("same");
  const std::vector<uint32_t> first_values = {1, 2, 3};
  const std::vector<uint32_t> second_values = {4, 5};
  const auto first_vector = builder.CreateVector(first_values);
  const auto second_vector = builder.CreateVector(second_values);
  const auto first_payload = CreatePayload(builder, 42);
  const auto second_payload = CreatePayload(builder, -7);
  const auto first_item = CreateItem(builder, name, first_vector, 1, first_payload);
  const auto second_item = CreateItem(builder, name, second_vector, 1, second_payload);
  const std::vector<flatbuffers::Offset<Item>> item_offsets = {first_item, second_item};
  const auto items = builder.CreateVector(item_offsets);
  const auto root = CreateRoot(builder, title, items);
  builder.Finish(root, "FBWT");
  for (size_t i = 0; i < builder.GetSize(); ++i) {
    std::printf("%s%u", i == 0 ? "" : ",", builder.GetBufferPointer()[i]);
  }
  std::printf("\nSIZE=%u\n", builder.GetSize());
}
