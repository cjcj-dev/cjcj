// Diagnostic only: official HRT dumps can contain unresolved pre-forwarding
// references after GC (cjcj#633). A resolved raw-ID chain is not proof of live
// ownership. Qualify the snapshot with fixtures/compiler_heap_graph.cj first.
// Inspect Constant -> ArrayList<BlockGroup> -> RawArray ownership in an
// official Cangjie "CANGJIE PROFILE 1.0.2" heap dump. Constant has no block
// groups (CHIR/IR/Expression/Expression.h; Expression.cj:609-612).
// Primitive size fields are absent: report only fully resolved pointer chains.
// Unresolved records are not guessed to be zero-capacity arrays.
// Format anchors: runtime/src/Inspector/CjHeapData.cpp WriteFixedHeader,
// WriteClass, WriteInstance, WriteObjectArray, WriteStructArray, and
// WritePrimitiveArray.
#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <unordered_map>
#include <vector>

namespace {

constexpr uint8_t TAG_STRING = 0x01;
constexpr uint8_t TAG_HEAP_DUMP = 0x0c;
constexpr uint8_t TAG_ROOT_UNKNOWN = 0xff;
constexpr uint8_t TAG_ROOT_GLOBAL = 0x01;
constexpr uint8_t TAG_ROOT_LOCAL = 0x02;
constexpr uint8_t TAG_ROOT_THREAD_OBJECT = 0x08;
constexpr uint8_t TAG_CLASS_DUMP = 0x20;
constexpr uint8_t TAG_INSTANCE_DUMP = 0x21;
constexpr uint8_t TAG_OBJECT_ARRAY_DUMP = 0x22;
constexpr uint8_t TAG_PRIMITIVE_ARRAY_DUMP = 0x23;
constexpr uint8_t TAG_STRUCT_ARRAY_DUMP = 0x24;
constexpr uint8_t TAG_PINNED_INSTANCE_DUMP = 0x25;
constexpr uint8_t TAG_LARGE_INSTANCE_DUMP = 0x26;
constexpr uint8_t TAG_LARGE_OBJECT_ARRAY_DUMP = 0x27;
constexpr uint8_t TAG_LARGE_PRIMITIVE_ARRAY_DUMP = 0x28;
constexpr uint8_t TAG_LARGE_STRUCT_ARRAY_DUMP = 0x29;
constexpr uint8_t TAG_UNMOVABLE_INSTANCE_DUMP = 0x2a;
constexpr uint8_t TAG_UNMOVABLE_OBJECT_ARRAY_DUMP = 0x2b;
constexpr uint8_t TAG_UNMOVABLE_PRIMITIVE_ARRAY_DUMP = 0x2c;
constexpr uint8_t TAG_UNMOVABLE_STRUCT_ARRAY_DUMP = 0x2d;

struct Reader {
    const uint8_t* data;
    uint64_t size;
    uint64_t pos = 0;

    void Need(uint64_t n) const
    {
        if (n > size - pos) {
            throw std::runtime_error("truncated dump at offset " + std::to_string(pos));
        }
    }

    uint8_t U1()
    {
        Need(1);
        return data[pos++];
    }

    uint32_t U4()
    {
        Need(4);
        uint32_t value = (uint32_t(data[pos]) << 24) | (uint32_t(data[pos + 1]) << 16) |
            (uint32_t(data[pos + 2]) << 8) | uint32_t(data[pos + 3]);
        pos += 4;
        return value;
    }

    uint64_t U8()
    {
        Need(8);
        uint64_t value = 0;
        for (int i = 0; i < 8; ++i) {
            value = (value << 8) | data[pos + i];
        }
        pos += 8;
        return value;
    }

    void Skip(uint64_t n)
    {
        Need(n);
        pos += n;
    }
};

struct ClassInfo {
    uint32_t stringId = 0;
    uint32_t instanceOrComponentSize = 0;
};

} // namespace


#include <unordered_set>
int main(int argc, char** argv) {
 if(argc!=2) { std::cerr << "usage: compiler_heap_owners HEAP.dat\n"; return 2; }
 int fd=open(argv[1],O_RDONLY); struct stat st{}; if(fd<0||fstat(fd,&st))return 2;
 auto data=static_cast<const uint8_t*>(mmap(nullptr,st.st_size,PROT_READ,MAP_PRIVATE,fd,0));
 try {
 Reader r{data,static_cast<uint64_t>(st.st_size)}; const char expected[]="CANGJIE PROFILE 1.0.2";
 r.Need(sizeof(expected)); if(memcmp(data,expected,sizeof(expected)))throw std::runtime_error("header");
 r.Skip(sizeof(expected)); auto idSize=r.U4();r.Skip(8);
 auto id=[&](){return idSize==8?r.U8():uint64_t(r.U4());};
 std::unordered_map<uint32_t,std::string> strings;
 std::unordered_map<uint32_t,ClassInfo> classes;
 uint64_t end=0;
 while(r.pos<r.size){auto tag=r.U1();if(tag==TAG_STRING){auto n=r.U4(),key=r.U4();r.Need(n-4);strings[key]=std::string((const char*)r.data+r.pos,n-4);r.Skip(n-4);}else{auto n=r.U8();if(tag==TAG_HEAP_DUMP){end=r.pos+n;break;}r.Skip(n);}}
 if(!end||end>r.size)throw std::runtime_error("heap boundary");auto begin=r.pos;
 std::unordered_map<uint64_t,std::vector<uint64_t>> constants;
 std::unordered_map<uint64_t,uint32_t> arrays;
 std::unordered_map<uint64_t,std::vector<uint64_t>> lists;
 auto name=[&](uint32_t cls){return strings[classes[cls].stringId];};
 while(r.pos<end){auto tag=r.U1();uint64_t obj=0;uint32_t cls=0,refs=0;
  switch(tag){
   case TAG_ROOT_UNKNOWN:case TAG_ROOT_GLOBAL:id();continue;
   case TAG_ROOT_LOCAL:case TAG_ROOT_THREAD_OBJECT:id();r.Skip(8);continue;
   case TAG_CLASS_DUMP:{auto key=r.U4(),str=r.U4(),size=r.U4();classes[key]={str,size};continue;}
   case TAG_INSTANCE_DUMP:case TAG_PINNED_INSTANCE_DUMP:case TAG_LARGE_INSTANCE_DUMP:case TAG_UNMOVABLE_INSTANCE_DUMP: obj=id();cls=r.U4();refs=r.U4();break;
   case TAG_OBJECT_ARRAY_DUMP:case TAG_LARGE_OBJECT_ARRAY_DUMP:case TAG_UNMOVABLE_OBJECT_ARRAY_DUMP: obj=id();refs=r.U4();cls=r.U4();if(name(cls)=="RawArray<cjcj/chir:BlockGroup>")arrays[obj]=refs;break;
   case TAG_STRUCT_ARRAY_DUMP:case TAG_LARGE_STRUCT_ARRAY_DUMP:case TAG_UNMOVABLE_STRUCT_ARRAY_DUMP: obj=id();r.U4();refs=r.U4();cls=r.U4();break;
   case TAG_PRIMITIVE_ARRAY_DUMP:case TAG_LARGE_PRIMITIVE_ARRAY_DUMP:case TAG_UNMOVABLE_PRIMITIVE_ARRAY_DUMP:id();r.U4();r.U1();continue;
   default:throw std::runtime_error("unknown tag");
  }
  if(name(cls)=="cjcj/chir:Constant")for(uint32_t i=0;i<refs;++i)constants[obj].push_back(id());
  else if(name(cls)=="std.collection:ArrayList<cjcj/chir:BlockGroup>")for(uint32_t i=0;i<refs;++i)lists[obj].push_back(id());
  else r.Skip(uint64_t(refs)*idSize);
 }
 std::unordered_map<uint32_t,uint64_t> counts;
 uint64_t owners=0;
 for(auto& [constant,refs]:constants)for(auto list:refs)if(lists.count(list))for(auto array:lists[list])if(arrays.count(array)){++counts[arrays[array]];++owners;}
 std::cout<<"owners="<<owners<<" constants="<<constants.size()<<" lists="<<lists.size()<<" arrays="<<arrays.size()<<"\n";
 for(auto [capacity,count]:counts)std::cout<<capacity<<"\t"<<count<<"\n";
 }catch(const std::exception&e){std::cerr<<e.what()<<"\n";return 2;}
 munmap((void*)data,st.st_size);close(fd);return 0;
}
