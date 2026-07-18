package cjcj::chir

import std.collection.*
import std.reflect.TypeInfo
import std.fs.File
import cjcj::basic.Linkage as BasicLinkage
import cjcj::basic.LinkageToInt
import cjcj::flatbuffers.{FlatBufferBuilder, FlatBufferOffset}
import cjcj::utils.{CJC_ABORT, CJC_ASSERT}
import cjcj::utils.OverflowStrategyIndex

private func IntrinsicKindToPackageIntrinsicKind(kind: IntrinsicKind): UInt16 {
    return match (kind) {
        case IntrinsicKind.NOT_INTRINSIC => 0u16
        case IntrinsicKind.NOT_IMPLEMENTED => 1u16
        case IntrinsicKind.ARRAY_INIT => 2u16
        case IntrinsicKind.SIZE_OF => 3u16
        case IntrinsicKind.ALIGN_OF => 4u16
        case IntrinsicKind.ARRAY_ACQUIRE_RAW_DATA => 5u16
        case IntrinsicKind.ARRAY_RELEASE_RAW_DATA => 6u16
        case IntrinsicKind.ARRAY_BUILT_IN_COPY_TO => 7u16
        case IntrinsicKind.ARRAY_GET => 8u16
        case IntrinsicKind.ARRAY_SET => 9u16
        case IntrinsicKind.ARRAY_GET_UNCHECKED => 10u16
        case IntrinsicKind.ARRAY_GET_REF_UNCHECKED => 11u16
        case IntrinsicKind.ARRAY_SET_UNCHECKED => 12u16
        case IntrinsicKind.ARRAY_SIZE => 13u16
        case IntrinsicKind.ARRAY_CLONE => 14u16
        case IntrinsicKind.ARRAY_SLICE_INIT => 15u16
        case IntrinsicKind.ARRAY_SLICE => 16u16
        case IntrinsicKind.ARRAY_SLICE_RAWARRAY => 17u16
        case IntrinsicKind.ARRAY_SLICE_START => 18u16
        case IntrinsicKind.ARRAY_SLICE_SIZE => 19u16
        case IntrinsicKind.ARRAY_SLICE_GET_ELEMENT => 20u16
        case IntrinsicKind.ARRAY_SLICE_GET_ELEMENT_UNCHECKED => 21u16
        case IntrinsicKind.ARRAY_SLICE_SET_ELEMENT => 22u16
        case IntrinsicKind.ARRAY_SLICE_SET_ELEMENT_UNCHECKED => 23u16
        case IntrinsicKind.FILL_IN_STACK_TRACE => 24u16
        case IntrinsicKind.DECODE_STACK_TRACE => 25u16
        case IntrinsicKind.DUMP_CURRENT_THREAD_INFO => 26u16
        case IntrinsicKind.DUMP_ALL_THREADS_INFO => 27u16
        case IntrinsicKind.CHR => 28u16
        case IntrinsicKind.ORD => 29u16
        case IntrinsicKind.CPOINTER_GET_POINTER_ADDRESS => 30u16
        case IntrinsicKind.CPOINTER_INIT0 => 31u16
        case IntrinsicKind.CPOINTER_INIT1 => 32u16
        case IntrinsicKind.CPOINTER_READ => 33u16
        case IntrinsicKind.CPOINTER_WRITE => 34u16
        case IntrinsicKind.CPOINTER_ADD => 35u16
        case IntrinsicKind.CSTRING_INIT => 36u16
        case IntrinsicKind.CSTRING_CONVERT_CSTR_TO_PTR => 37u16
        case IntrinsicKind.INOUT_PARAM => 38u16
        case IntrinsicKind.REGISTER_WATCHED_OBJECT => 39u16
        case IntrinsicKind.OBJECT_REFEQ => 40u16
        case IntrinsicKind.RAW_ARRAY_REFEQ => 41u16
        case IntrinsicKind.FUNC_REFEQ => 42u16
        case IntrinsicKind.OBJECT_ZERO_VALUE => 43u16
        case IntrinsicKind.INVOKE_GC => 44u16
        case IntrinsicKind.SET_GC_THRESHOLD => 45u16
        case IntrinsicKind.DUMP_CJ_HEAP_DATA => 46u16
        case IntrinsicKind.GET_GC_COUNT => 47u16
        case IntrinsicKind.GET_GC_TIME_US => 48u16
        case IntrinsicKind.GET_GC_FREED_SIZE => 49u16
        case IntrinsicKind.START_CJ_CPU_PROFILING => 50u16
        case IntrinsicKind.STOP_CJ_CPU_PROFILING => 51u16
        case IntrinsicKind.BLACK_BOX => 52u16
        case IntrinsicKind.GET_MAX_HEAP_SIZE => 53u16
        case IntrinsicKind.GET_ALLOCATE_HEAP_SIZE => 54u16
        case IntrinsicKind.GET_REAL_HEAP_SIZE => 55u16
        case IntrinsicKind.GET_THREAD_NUMBER => 56u16
        case IntrinsicKind.GET_BLOCKING_THREAD_NUMBER => 57u16
        case IntrinsicKind.GET_NATIVE_THREAD_NUMBER => 58u16
        case IntrinsicKind.VARRAY_SET => 59u16
        case IntrinsicKind.VARRAY_GET => 60u16
        case IntrinsicKind.FUTURE_INIT => 61u16
        case IntrinsicKind.FUTURE_IS_COMPLETE => 62u16
        case IntrinsicKind.FUTURE_WAIT => 63u16
        case IntrinsicKind.FUTURE_NOTIFYALL => 64u16
        case IntrinsicKind.IS_THREAD_OBJECT_INITED => 65u16
        case IntrinsicKind.GET_THREAD_OBJECT => 66u16
        case IntrinsicKind.SET_THREAD_OBJECT => 67u16
        case IntrinsicKind.OVERFLOW_CHECKED_ADD => 68u16
        case IntrinsicKind.OVERFLOW_CHECKED_SUB => 69u16
        case IntrinsicKind.OVERFLOW_CHECKED_MUL => 70u16
        case IntrinsicKind.OVERFLOW_CHECKED_DIV => 71u16
        case IntrinsicKind.OVERFLOW_CHECKED_MOD => 72u16
        case IntrinsicKind.OVERFLOW_CHECKED_POW => 73u16
        case IntrinsicKind.OVERFLOW_CHECKED_INC => 74u16
        case IntrinsicKind.OVERFLOW_CHECKED_DEC => 75u16
        case IntrinsicKind.OVERFLOW_CHECKED_NEG => 76u16
        case IntrinsicKind.OVERFLOW_THROWING_ADD => 77u16
        case IntrinsicKind.OVERFLOW_THROWING_SUB => 78u16
        case IntrinsicKind.OVERFLOW_THROWING_MUL => 79u16
        case IntrinsicKind.OVERFLOW_THROWING_DIV => 80u16
        case IntrinsicKind.OVERFLOW_THROWING_MOD => 81u16
        case IntrinsicKind.OVERFLOW_THROWING_POW => 82u16
        case IntrinsicKind.OVERFLOW_THROWING_INC => 83u16
        case IntrinsicKind.OVERFLOW_THROWING_DEC => 84u16
        case IntrinsicKind.OVERFLOW_THROWING_NEG => 85u16
        case IntrinsicKind.OVERFLOW_SATURATING_ADD => 86u16
        case IntrinsicKind.OVERFLOW_SATURATING_SUB => 87u16
        case IntrinsicKind.OVERFLOW_SATURATING_MUL => 88u16
        case IntrinsicKind.OVERFLOW_SATURATING_DIV => 89u16
        case IntrinsicKind.OVERFLOW_SATURATING_MOD => 90u16
        case IntrinsicKind.OVERFLOW_SATURATING_POW => 91u16
        case IntrinsicKind.OVERFLOW_SATURATING_INC => 92u16
        case IntrinsicKind.OVERFLOW_SATURATING_DEC => 93u16
        case IntrinsicKind.OVERFLOW_SATURATING_NEG => 94u16
        case IntrinsicKind.OVERFLOW_WRAPPING_ADD => 95u16
        case IntrinsicKind.OVERFLOW_WRAPPING_SUB => 96u16
        case IntrinsicKind.OVERFLOW_WRAPPING_MUL => 97u16
        case IntrinsicKind.OVERFLOW_WRAPPING_DIV => 98u16
        case IntrinsicKind.OVERFLOW_WRAPPING_MOD => 99u16
        case IntrinsicKind.OVERFLOW_WRAPPING_POW => 100u16
        case IntrinsicKind.OVERFLOW_WRAPPING_INC => 101u16
        case IntrinsicKind.OVERFLOW_WRAPPING_DEC => 102u16
        case IntrinsicKind.OVERFLOW_WRAPPING_NEG => 103u16
        case IntrinsicKind.VECTOR_COMPARE_32 => 104u16
        case IntrinsicKind.VECTOR_INDEX_BYTE_32 => 105u16
        case IntrinsicKind.CJ_CORE_CAN_USE_SIMD => 106u16
        case IntrinsicKind.CJ_TLS_DYN_SET_SESSION_CALLBACK => 107u16
        case IntrinsicKind.CJ_TLS_DYN_SSL_INIT => 108u16
        case IntrinsicKind.REFLECTION_INTRINSIC_START_FLAG => 109u16
        case IntrinsicKind.IS_INTERFACE => 110u16
        case IntrinsicKind.IS_CLASS => 111u16
        case IntrinsicKind.IS_PRIMITIVE => 112u16
        case IntrinsicKind.IS_STRUCT => 113u16
        case IntrinsicKind.IS_GENERIC => 114u16
        case IntrinsicKind.IS_TUPLE => 115u16
        case IntrinsicKind.IS_FUNCTION => 116u16
        case IntrinsicKind.IS_ENUM => 117u16
        case IntrinsicKind.IS_BOX => 118u16
        case IntrinsicKind.GET_OR_CREATE_TYPEINFO_FOR_REFLECT => 119u16
        case IntrinsicKind.GET_TYPETEMPLATE => 120u16
        case IntrinsicKind.CHECK_METHOD_ACTUAL_ARGS => 121u16
        case IntrinsicKind.METHOD_ENTRYPOINT_IS_NULL => 122u16
        case IntrinsicKind.IS_RELECT_UNSUPPORTED_TYPE => 123u16
        case IntrinsicKind.GET_TYPE_FOR_ANY => 124u16
        case IntrinsicKind.GET_TYPE_BY_MANGLED_NAME => 125u16
        case IntrinsicKind.GET_TYPE_NAME => 126u16
        case IntrinsicKind.GET_TYPE_BY_QUALIFIED_NAME => 127u16
        case IntrinsicKind.GET_TYPE_QUALIFIED_NAME_LENGTH => 128u16
        case IntrinsicKind.GET_TYPE_QUALIFIED_NAME => 129u16
        case IntrinsicKind.GET_NUM_OF_INTERFACE => 130u16
        case IntrinsicKind.GET_INTERFACE => 131u16
        case IntrinsicKind.IS_SUBTYPE => 132u16
        case IntrinsicKind.GET_TYPE_INFO_MODIFIER => 133u16
        case IntrinsicKind.GET_TYPE_INFO_ANNOTATIONS => 134u16
        case IntrinsicKind.GET_OBJ_CLASS => 135u16
        case IntrinsicKind.GET_SUPER_TYPE_INFO => 136u16
        case IntrinsicKind.GET_TYPE_ARGS => 137u16
        case IntrinsicKind.GET_NUM_OF_INSTANCE_METHOD_INFOS => 138u16
        case IntrinsicKind.GET_INSTANCE_METHOD_INFO => 139u16
        case IntrinsicKind.GET_NUM_OF_STATIC_METHOD_INFOS => 140u16
        case IntrinsicKind.GET_STATIC_METHOD_INFO => 141u16
        case IntrinsicKind.GET_METHOD_NAME => 142u16
        case IntrinsicKind.GET_METHOD_RETURN_TYPE => 143u16
        case IntrinsicKind.GET_METHOD_MODIFIER => 144u16
        case IntrinsicKind.GET_METHOD_ANNOTATIONS => 145u16
        case IntrinsicKind.APPLY_CJ_METHOD => 146u16
        case IntrinsicKind.APPLY_CJ_STATIC_METHOD => 147u16
        case IntrinsicKind.APPLY_CJ_GENERIC_METHOD => 148u16
        case IntrinsicKind.APPLY_CJ_GENERIC_STATIC_METHOD => 149u16
        case IntrinsicKind.GET_NUM_OF_ACTUAL_PARAMETERS => 150u16
        case IntrinsicKind.GET_NUM_OF_GENERIC_PARAMETERS => 151u16
        case IntrinsicKind.GET_ACTUAL_PARAMETER_INFO => 152u16
        case IntrinsicKind.GET_GENERIC_PARAMETER_INFO => 153u16
        case IntrinsicKind.GET_NUM_OF_INSTANCE_FIELD_INFOS => 154u16
        case IntrinsicKind.GET_INSTANCE_FIELD_INFO => 155u16
        case IntrinsicKind.GET_NUM_OF_STATIC_FIELD_INFOS => 156u16
        case IntrinsicKind.GET_STATIC_FIELD_INFO => 157u16
        case IntrinsicKind.GET_STATIC_FIELD_NAME => 158u16
        case IntrinsicKind.GET_STATIC_FIELD_TYPE => 159u16
        case IntrinsicKind.GET_STATIC_FIELD_ANNOTATIONS => 160u16
        case IntrinsicKind.GET_INSTANCE_FIELD_NAME => 161u16
        case IntrinsicKind.GET_INSTANCE_FIELD_TYPE => 162u16
        case IntrinsicKind.GET_INSTANCE_FIELD_ANNOTATIONS => 163u16
        case IntrinsicKind.GET_INSTANCE_FIELD_MODIFIER => 164u16
        case IntrinsicKind.GET_STATIC_FIELD_MODIFIER => 165u16
        case IntrinsicKind.GET_FIELD_VALUE => 166u16
        case IntrinsicKind.SET_FIELD_VALUE => 167u16
        case IntrinsicKind.GET_STATIC_FIELD_VALUE => 168u16
        case IntrinsicKind.SET_STATIC_FIELD_VALUE => 169u16
        case IntrinsicKind.GET_FIELD_DECLARING_TYPE => 170u16
        case IntrinsicKind.GET_PARAMETER_INDEX => 171u16
        case IntrinsicKind.GET_PARAMETER_NAME => 172u16
        case IntrinsicKind.GET_PARAMETER_TYPE => 173u16
        case IntrinsicKind.GET_PARAMETER_ANNOTATIONS => 174u16
        case IntrinsicKind.GET_RELATED_PACKAGE_INF => 175u16
        case IntrinsicKind.GET_PACKAGE_NAME => 176u16
        case IntrinsicKind.GET_PACKAGE_NUM_OF_TYPE_INFOS => 177u16
        case IntrinsicKind.GET_PACKAGE_TYPE_INFO => 178u16
        case IntrinsicKind.GET_PACKAGE_NUM_OF_GLOBAL_METHODS => 179u16
        case IntrinsicKind.GET_PACKAGE_GLOBAL_METHOD_INFO => 180u16
        case IntrinsicKind.GET_PACKAGE_NUM_OF_GLOBAL_FIELD_INFOS => 181u16
        case IntrinsicKind.GET_PACKAGE_GLOBAL_FIELD_INFO => 182u16
        case IntrinsicKind.LOAD_PACKAGE => 183u16
        case IntrinsicKind.GET_PACKAGE_BY_QUALIFIEDNAME => 184u16
        case IntrinsicKind.GET_PACKAGE_VERSION => 185u16
        case IntrinsicKind.GET_SUB_PACKAGES => 186u16
        case IntrinsicKind.GET_NUM_OF_FIELD_TYPES => 187u16
        case IntrinsicKind.GET_FIELD_TYPES => 188u16
        case IntrinsicKind.NEW_AND_INIT_OBJECT => 189u16
        case IntrinsicKind.GET_ASSOCIATED_VALUES => 190u16
        case IntrinsicKind.GET_NUM_OF_FUNCTION_SIGNATURETYPES => 191u16
        case IntrinsicKind.GET_FUNCTION_SIGNATURE_TYPES => 192u16
        case IntrinsicKind.GET_NUM_OF_ENUM_CONSTRUCTOR_INFOS => 193u16
        case IntrinsicKind.GET_ENUM_CONSTRUCTOR_INFO => 194u16
        case IntrinsicKind.GET_ENUM_CONSTRUCTOR_NAME => 195u16
        case IntrinsicKind.GET_ENUM_CONSTRUCTOR_INFO_FROM_ANY => 196u16
        case IntrinsicKind.REFLECTION_INTRINSIC_END_FLAG => 197u16
        case IntrinsicKind.SLEEP => 198u16
        case IntrinsicKind.SOURCE_FILE => 199u16
        case IntrinsicKind.SOURCE_LINE => 200u16
        case IntrinsicKind.IDENTITY_HASHCODE => 201u16
        case IntrinsicKind.IDENTITY_HASHCODE_FOR_ARRAY => 202u16
        case IntrinsicKind.ATOMIC_LOAD => 203u16
        case IntrinsicKind.ATOMIC_STORE => 204u16
        case IntrinsicKind.ATOMIC_SWAP => 205u16
        case IntrinsicKind.ATOMIC_COMPARE_AND_SWAP => 206u16
        case IntrinsicKind.ATOMIC_FETCH_ADD => 207u16
        case IntrinsicKind.ATOMIC_FETCH_SUB => 208u16
        case IntrinsicKind.ATOMIC_FETCH_AND => 209u16
        case IntrinsicKind.ATOMIC_FETCH_OR => 210u16
        case IntrinsicKind.ATOMIC_FETCH_XOR => 211u16
        case IntrinsicKind.MUTEX_INIT => 212u16
        case IntrinsicKind.CJ_MUTEX_LOCK => 213u16
        case IntrinsicKind.MUTEX_TRY_LOCK => 214u16
        case IntrinsicKind.MUTEX_CHECK_STATUS => 215u16
        case IntrinsicKind.MUTEX_UNLOCK => 216u16
        case IntrinsicKind.WAITQUEUE_INIT => 217u16
        case IntrinsicKind.MONITOR_INIT => 218u16
        case IntrinsicKind.MOITIOR_WAIT => 219u16
        case IntrinsicKind.MOITIOR_NOTIFY => 220u16
        case IntrinsicKind.MOITIOR_NOTIFY_ALL => 221u16
        case IntrinsicKind.MULTICONDITION_WAIT => 222u16
        case IntrinsicKind.MULTICONDITION_NOTIFY => 223u16
        case IntrinsicKind.MULTICONDITION_NOTIFY_ALL => 224u16
        case IntrinsicKind.CROSS_ACCESS_BARRIER => 225u16
        case IntrinsicKind.CREATE_EXPORT_HANDLE => 226u16
        case IntrinsicKind.GET_EXPORTED_REF => 227u16
        case IntrinsicKind.REMOVE_EXPORTED_REF => 228u16
        case IntrinsicKind.GET_JSLAMBDA_ADDR => 229u16
        case IntrinsicKind.FFI_CJ_AST_LEX => 230u16
        case IntrinsicKind.FFI_CJ_AST_PARSEEXPR => 231u16
        case IntrinsicKind.FFI_CJ_AST_PARSEDECL => 232u16
        case IntrinsicKind.FFI_CJ_AST_PARSE_PROPMEMBERDECL => 233u16
        case IntrinsicKind.FFI_CJ_AST_PARSE_PRICONSTRUCTOR => 234u16
        case IntrinsicKind.FFI_CJ_AST_PARSE_PATTERN => 235u16
        case IntrinsicKind.FFI_CJ_AST_PARSE_TYPE => 236u16
        case IntrinsicKind.FFI_CJ_AST_PARSETOPLEVEL => 237u16
        case IntrinsicKind.FFI_CJ_AST_DIAGREPORT => 238u16
        case IntrinsicKind.FFI_CJ_PARENT_CONTEXT => 239u16
        case IntrinsicKind.FFI_CJ_MACRO_ITEM_INFO => 240u16
        case IntrinsicKind.FFI_CJ_GET_CHILD_MESSAGES => 241u16
        case IntrinsicKind.FFI_CJ_CHECK_ADD_SPACE => 242u16
        case IntrinsicKind.CG_UNSAFE_BEGIN => 243u16
        case IntrinsicKind.CG_UNSAFE_END => 244u16
        case IntrinsicKind.STRLEN => 245u16
        case IntrinsicKind.MEMCPY_S => 246u16
        case IntrinsicKind.MEMSET_S => 247u16
        case IntrinsicKind.FREE => 248u16
        case IntrinsicKind.MALLOC => 249u16
        case IntrinsicKind.STRCMP => 250u16
        case IntrinsicKind.MEMCMP => 251u16
        case IntrinsicKind.STRNCMP => 252u16
        case IntrinsicKind.STRCASECMP => 253u16
        case IntrinsicKind.ATOMIC_INT8_LOAD => 254u16
        case IntrinsicKind.ATOMIC_INT8_STORE => 255u16
        case IntrinsicKind.ATOMIC_INT8_SWAP => 256u16
        case IntrinsicKind.ATOMIC_INT8_CAS => 257u16
        case IntrinsicKind.ATOMIC_INT8_FETCH_ADD => 258u16
        case IntrinsicKind.ATOMIC_INT8_FETCH_SUB => 259u16
        case IntrinsicKind.ATOMIC_INT8_FETCH_AND => 260u16
        case IntrinsicKind.ATOMIC_INT8_FETCH_OR => 261u16
        case IntrinsicKind.ATOMIC_INT8_FETCH_XOR => 262u16
        case IntrinsicKind.ATOMIC_INT16_LOAD => 263u16
        case IntrinsicKind.ATOMIC_INT16_STORE => 264u16
        case IntrinsicKind.ATOMIC_INT16_SWAP => 265u16
        case IntrinsicKind.ATOMIC_INT16_CAS => 266u16
        case IntrinsicKind.ATOMIC_INT16_FETCH_ADD => 267u16
        case IntrinsicKind.ATOMIC_INT16_FETCH_SUB => 268u16
        case IntrinsicKind.ATOMIC_INT16_FETCH_AND => 269u16
        case IntrinsicKind.ATOMIC_INT16_FETCH_OR => 270u16
        case IntrinsicKind.ATOMIC_INT16_FETCH_XOR => 271u16
        case IntrinsicKind.ATOMIC_INT32_LOAD => 272u16
        case IntrinsicKind.ATOMIC_INT32_STORE => 273u16
        case IntrinsicKind.ATOMIC_INT32_SWAP => 274u16
        case IntrinsicKind.ATOMIC_INT32_CAS => 275u16
        case IntrinsicKind.ATOMIC_INT32_FETCH_ADD => 276u16
        case IntrinsicKind.ATOMIC_INT32_FETCH_SUB => 277u16
        case IntrinsicKind.ATOMIC_INT32_FETCH_AND => 278u16
        case IntrinsicKind.ATOMIC_INT32_FETCH_OR => 279u16
        case IntrinsicKind.ATOMIC_INT32_FETCH_XOR => 280u16
        case IntrinsicKind.ATOMIC_INT64_LOAD => 281u16
        case IntrinsicKind.ATOMIC_INT64_STORE => 282u16
        case IntrinsicKind.ATOMIC_INT64_SWAP => 283u16
        case IntrinsicKind.ATOMIC_INT64_CAS => 284u16
        case IntrinsicKind.ATOMIC_INT64_FETCH_ADD => 285u16
        case IntrinsicKind.ATOMIC_INT64_FETCH_SUB => 286u16
        case IntrinsicKind.ATOMIC_INT64_FETCH_AND => 287u16
        case IntrinsicKind.ATOMIC_INT64_FETCH_OR => 288u16
        case IntrinsicKind.ATOMIC_INT64_FETCH_XOR => 289u16
        case IntrinsicKind.ATOMIC_UINT8_LOAD => 290u16
        case IntrinsicKind.ATOMIC_UINT8_STORE => 291u16
        case IntrinsicKind.ATOMIC_UINT8_SWAP => 292u16
        case IntrinsicKind.ATOMIC_UINT8_CAS => 293u16
        case IntrinsicKind.ATOMIC_UINT8_FETCH_ADD => 294u16
        case IntrinsicKind.ATOMIC_UINT8_FETCH_SUB => 295u16
        case IntrinsicKind.ATOMIC_UINT8_FETCH_AND => 296u16
        case IntrinsicKind.ATOMIC_UINT8_FETCH_OR => 297u16
        case IntrinsicKind.ATOMIC_UINT8_FETCH_XOR => 298u16
        case IntrinsicKind.ATOMIC_UINT16_LOAD => 299u16
        case IntrinsicKind.ATOMIC_UINT16_STORE => 300u16
        case IntrinsicKind.ATOMIC_UINT16_SWAP => 301u16
        case IntrinsicKind.ATOMIC_UINT16_CAS => 302u16
        case IntrinsicKind.ATOMIC_UINT16_FETCH_ADD => 303u16
        case IntrinsicKind.ATOMIC_UINT16_FETCH_SUB => 304u16
        case IntrinsicKind.ATOMIC_UINT16_FETCH_AND => 305u16
        case IntrinsicKind.ATOMIC_UINT16_FETCH_OR => 306u16
        case IntrinsicKind.ATOMIC_UINT16_FETCH_XOR => 307u16
        case IntrinsicKind.ATOMIC_UINT32_LOAD => 308u16
        case IntrinsicKind.ATOMIC_UINT32_STORE => 309u16
        case IntrinsicKind.ATOMIC_UINT32_SWAP => 310u16
        case IntrinsicKind.ATOMIC_UINT32_CAS => 311u16
        case IntrinsicKind.ATOMIC_UINT32_FETCH_ADD => 312u16
        case IntrinsicKind.ATOMIC_UINT32_FETCH_SUB => 313u16
        case IntrinsicKind.ATOMIC_UINT32_FETCH_AND => 314u16
        case IntrinsicKind.ATOMIC_UINT32_FETCH_OR => 315u16
        case IntrinsicKind.ATOMIC_UINT32_FETCH_XOR => 316u16
        case IntrinsicKind.ATOMIC_UINT64_LOAD => 317u16
        case IntrinsicKind.ATOMIC_UINT64_STORE => 318u16
        case IntrinsicKind.ATOMIC_UINT64_SWAP => 319u16
        case IntrinsicKind.ATOMIC_UINT64_CAS => 320u16
        case IntrinsicKind.ATOMIC_UINT64_FETCH_ADD => 321u16
        case IntrinsicKind.ATOMIC_UINT64_FETCH_SUB => 322u16
        case IntrinsicKind.ATOMIC_UINT64_FETCH_AND => 323u16
        case IntrinsicKind.ATOMIC_UINT64_FETCH_OR => 324u16
        case IntrinsicKind.ATOMIC_UINT64_FETCH_XOR => 325u16
        case IntrinsicKind.ATOMIC_BOOL_LOAD => 326u16
        case IntrinsicKind.ATOMIC_BOOL_STORE => 327u16
        case IntrinsicKind.ATOMIC_BOOL_SWAP => 328u16
        case IntrinsicKind.ATOMIC_BOOL_CAS => 329u16
        case IntrinsicKind.ATOMIC_REFERENCEBASE_LOAD => 330u16
        case IntrinsicKind.ATOMIC_REFERENCEBASE_STORE => 331u16
        case IntrinsicKind.ATOMIC_REFERENCEBASE_SWAP => 332u16
        case IntrinsicKind.ATOMIC_REFERENCEBASE_CAS => 333u16
        case IntrinsicKind.ATOMIC_OPTIONREFERENCE_LOAD => 334u16
        case IntrinsicKind.ATOMIC_OPTIONREFERENCE_STORE => 335u16
        case IntrinsicKind.ATOMIC_OPTIONREFERENCE_SWAP => 336u16
        case IntrinsicKind.ATOMIC_OPTIONREFERENCE_CAS => 337u16
        case IntrinsicKind.BEGIN_CATCH => 338u16
        case IntrinsicKind.ABS => 339u16
        case IntrinsicKind.FABS => 340u16
        case IntrinsicKind.FLOOR => 341u16
        case IntrinsicKind.CEIL => 342u16
        case IntrinsicKind.TRUNC => 343u16
        case IntrinsicKind.SIN => 344u16
        case IntrinsicKind.COS => 345u16
        case IntrinsicKind.EXP => 346u16
        case IntrinsicKind.EXP2 => 347u16
        case IntrinsicKind.LOG => 348u16
        case IntrinsicKind.LOG2 => 349u16
        case IntrinsicKind.LOG10 => 350u16
        case IntrinsicKind.SQRT => 351u16
        case IntrinsicKind.ROUND => 352u16
        case IntrinsicKind.POW => 353u16
        case IntrinsicKind.POWI => 354u16
        case IntrinsicKind.BIT_CAST => 355u16
        case IntrinsicKind.PREINITIALIZE => 356u16
        case IntrinsicKind.OBJECT_AS => 357u16
        case IntrinsicKind.IS_NULL => 358u16
        case IntrinsicKind.GET_TYPE_FOR_TYPE_PARAMETER => 359u16
        case IntrinsicKind.IS_SUBTYPE_TYPES => 360u16
        case IntrinsicKind.EXCLUSIVE_SCOPE => 361u16

    }
}

private func ToPackageExprKind(expr: Expression): UInt8 {
    return match (expr.GetExprKind()) {
        case ExprKind.GOTO => CHIRFB_CHIR_EXPR_KIND_GOTO
        case ExprKind.BRANCH => CHIRFB_CHIR_EXPR_KIND_BRANCH
        case ExprKind.MULTIBRANCH => CHIRFB_CHIR_EXPR_KIND_MULTI_BRANCH
        case ExprKind.EXIT => CHIRFB_CHIR_EXPR_KIND_EXIT
        case ExprKind.APPLY_WITH_EXCEPTION => CHIRFB_CHIR_EXPR_KIND_TRY_APPLY
        case ExprKind.INVOKE_WITH_EXCEPTION | ExprKind.INVOKESTATIC_WITH_EXCEPTION =>
            CHIRFB_CHIR_EXPR_KIND_TRY_INVOKE
        case ExprKind.RAISE_EXCEPTION => CHIRFB_CHIR_EXPR_KIND_RAISE_EXCEPTION
        case ExprKind.INT_OP_WITH_EXCEPTION =>
            match ((expr as IntOpWithException).getOrThrow().GetOpKind()) {
                case ExprKind.NEG => CHIRFB_CHIR_EXPR_KIND_TRY_NEG
                case ExprKind.ADD => CHIRFB_CHIR_EXPR_KIND_TRY_ADD
                case ExprKind.SUB => CHIRFB_CHIR_EXPR_KIND_TRY_SUB
                case ExprKind.MUL => CHIRFB_CHIR_EXPR_KIND_TRY_MUL
                case ExprKind.DIV => CHIRFB_CHIR_EXPR_KIND_TRY_DIV
                case ExprKind.MOD => CHIRFB_CHIR_EXPR_KIND_TRY_MOD
                case ExprKind.EXP => CHIRFB_CHIR_EXPR_KIND_TRY_EXP
                case ExprKind.LSHIFT => CHIRFB_CHIR_EXPR_KIND_TRY_L_SHIFT
                case ExprKind.RSHIFT => CHIRFB_CHIR_EXPR_KIND_TRY_R_SHIFT
                case _ => CHIRFB_CHIR_EXPR_KIND_INVALID
            }
        case ExprKind.SPAWN_WITH_EXCEPTION => CHIRFB_CHIR_EXPR_KIND_TRY_SPAWN
        case ExprKind.TYPECAST_WITH_EXCEPTION => CHIRFB_CHIR_EXPR_KIND_TRY_NUMERIC_CAST
        case ExprKind.INTRINSIC_WITH_EXCEPTION => CHIRFB_CHIR_EXPR_KIND_TRY_INTRINSIC
        case ExprKind.ALLOCATE_WITH_EXCEPTION => CHIRFB_CHIR_EXPR_KIND_TRY_ALLOCATE
        case ExprKind.RAW_ARRAY_ALLOCATE_WITH_EXCEPTION => CHIRFB_CHIR_EXPR_KIND_TRY_RAW_ARRAY_ALLOCATE
        case ExprKind.NEG => CHIRFB_CHIR_EXPR_KIND_NEG
        case ExprKind.NOT => CHIRFB_CHIR_EXPR_KIND_NOT
        case ExprKind.BITNOT => CHIRFB_CHIR_EXPR_KIND_BIT_NOT
        case ExprKind.ADD => CHIRFB_CHIR_EXPR_KIND_ADD
        case ExprKind.SUB => CHIRFB_CHIR_EXPR_KIND_SUB
        case ExprKind.MUL => CHIRFB_CHIR_EXPR_KIND_MUL
        case ExprKind.DIV => CHIRFB_CHIR_EXPR_KIND_DIV
        case ExprKind.MOD => CHIRFB_CHIR_EXPR_KIND_MOD
        case ExprKind.EXP => CHIRFB_CHIR_EXPR_KIND_EXP
        case ExprKind.LSHIFT => CHIRFB_CHIR_EXPR_KIND_L_SHIFT
        case ExprKind.RSHIFT => CHIRFB_CHIR_EXPR_KIND_R_SHIFT
        case ExprKind.BITAND => CHIRFB_CHIR_EXPR_KIND_BIT_AND
        case ExprKind.BITOR => CHIRFB_CHIR_EXPR_KIND_BIT_OR
        case ExprKind.BITXOR => CHIRFB_CHIR_EXPR_KIND_BIT_XOR
        case ExprKind.LT => CHIRFB_CHIR_EXPR_KIND_LT
        case ExprKind.GT => CHIRFB_CHIR_EXPR_KIND_GT
        case ExprKind.LE => CHIRFB_CHIR_EXPR_KIND_LE
        case ExprKind.GE => CHIRFB_CHIR_EXPR_KIND_GE
        case ExprKind.EQUAL => CHIRFB_CHIR_EXPR_KIND_EQUAL
        case ExprKind.NOTEQUAL => CHIRFB_CHIR_EXPR_KIND_NOT_EQUAL
        case ExprKind.AND => CHIRFB_CHIR_EXPR_KIND_AND
        case ExprKind.OR => CHIRFB_CHIR_EXPR_KIND_OR
        case ExprKind.TYPECAST => CHIRFB_CHIR_EXPR_KIND_NUMERIC_CAST
        case ExprKind.BOX => CHIRFB_CHIR_EXPR_KIND_BOX
        case ExprKind.UNBOX => CHIRFB_CHIR_EXPR_KIND_UNBOX_TO_VALUE
        case ExprKind.UNBOX_TO_REF => CHIRFB_CHIR_EXPR_KIND_UNBOX_TO_REF
        case ExprKind.TRANSFORM_TO_GENERIC => CHIRFB_CHIR_EXPR_KIND_CAST_TO_GENERIC
        case ExprKind.TRANSFORM_TO_CONCRETE => CHIRFB_CHIR_EXPR_KIND_CAST_TO_CONCRETE
        case ExprKind.ALLOCATE => CHIRFB_CHIR_EXPR_KIND_ALLOCATE
        case ExprKind.LOAD => CHIRFB_CHIR_EXPR_KIND_LOAD
        case ExprKind.STORE => CHIRFB_CHIR_EXPR_KIND_STORE
        case ExprKind.GET_ELEMENT_BY_NAME => CHIRFB_CHIR_EXPR_KIND_GET_ELEMENT_BY_NAME
        case ExprKind.GET_ELEMENT_REF => CHIRFB_CHIR_EXPR_KIND_GET_ELEMENT_REF
        case ExprKind.STORE_ELEMENT_BY_NAME => CHIRFB_CHIR_EXPR_KIND_STORE_ELEMENT_BY_NAME
        case ExprKind.STORE_ELEMENT_REF => CHIRFB_CHIR_EXPR_KIND_STORE_ELEMENT_REF
        case ExprKind.FIELD => CHIRFB_CHIR_EXPR_KIND_FIELD
        case ExprKind.FIELD_BY_NAME => CHIRFB_CHIR_EXPR_KIND_FIELD_BY_NAME
        case ExprKind.RAW_ARRAY_ALLOCATE => CHIRFB_CHIR_EXPR_KIND_RAW_ARRAY_ALLOCATE
        case ExprKind.RAW_ARRAY_LITERAL_INIT => CHIRFB_CHIR_EXPR_KIND_RAW_ARRAY_LITERAL_INIT
        case ExprKind.RAW_ARRAY_INIT_BY_VALUE => CHIRFB_CHIR_EXPR_KIND_RAW_ARRAY_INIT_BY_VALUE
        case ExprKind.VARRAY => CHIRFB_CHIR_EXPR_KIND_V_ARRAY_EXPR
        case ExprKind.VARRAY_BUILDER => CHIRFB_CHIR_EXPR_KIND_V_ARRAY_BUILDER
        case ExprKind.CONSTANT => CHIRFB_CHIR_EXPR_KIND_CONSTANT
        case ExprKind.DEBUGEXPR => CHIRFB_CHIR_EXPR_KIND_DEBUG
        case ExprKind.TUPLE => CHIRFB_CHIR_EXPR_KIND_TUPLE
        case ExprKind.INSTANCEOF => CHIRFB_CHIR_EXPR_KIND_INSTANCE_OF
        case ExprKind.GET_EXCEPTION => CHIRFB_CHIR_EXPR_KIND_GET_EXCEPTION
        case ExprKind.SPAWN => CHIRFB_CHIR_EXPR_KIND_SPAWN
        case ExprKind.LAMBDA => CHIRFB_CHIR_EXPR_KIND_LAMBDA
        case ExprKind.GET_INSTANTIATE_VALUE => CHIRFB_CHIR_EXPR_KIND_GET_INSTANTIATE_VALUE
        case ExprKind.APPLY => CHIRFB_CHIR_EXPR_KIND_APPLY
        case ExprKind.INVOKE | ExprKind.INVOKESTATIC => CHIRFB_CHIR_EXPR_KIND_INVOKE
        case ExprKind.INTRINSIC => CHIRFB_CHIR_EXPR_KIND_INTRINSIC
        case ExprKind.GET_RTTI => CHIRFB_CHIR_EXPR_KIND_GET_RTTI
        case ExprKind.GET_RTTI_STATIC => CHIRFB_CHIR_EXPR_KIND_GET_RTTI_STATIC
        case ExprKind.FORIN_RANGE | ExprKind.FORIN_ITER | ExprKind.FORIN_CLOSED_RANGE | ExprKind.INVALID =>
            CHIRFB_CHIR_EXPR_KIND_INVALID
    }
}

class CHIRSerializerImpl {
    private let builder: FlatBufferBuilder = FlatBufferBuilder()
    private var pkg: Option<Package> = None
    private let valueQueue: ArrayList<Value> = ArrayList<Value>()
    private let typeQueue: ArrayList<Type> = ArrayList<Type>()
    private let exprQueue: ArrayList<Expression> = ArrayList<Expression>()
    private let defQueue: ArrayList<CustomTypeDef> = ArrayList<CustomTypeDef>()

    private var typeCount: UInt32 = 0u32
    private var valueCount: UInt32 = 0u32
    private var exprCount: UInt32 = 0u32
    private var defCount: UInt32 = 0u32

    private let type2Id: HashMap<Int64, UInt32> = HashMap<Int64, UInt32>()
    private let value2Id: HashMap<Int64, UInt32> = HashMap<Int64, UInt32>()
    private let expr2Id: HashMap<Int64, UInt32> = HashMap<Int64, UInt32>()
    private let def2Id: HashMap<Int64, UInt32> = HashMap<Int64, UInt32>()

    private let typeKind: ArrayList<UInt8> = ArrayList<UInt8>()
    private let valueKind: ArrayList<UInt8> = ArrayList<UInt8>()
    private let exprKind: ArrayList<UInt8> = ArrayList<UInt8>()
    private let defKind: ArrayList<UInt8> = ArrayList<UInt8>()

    private let allType: ArrayList<FlatBufferOffset> = ArrayList<FlatBufferOffset>()
    private let allValue: ArrayList<FlatBufferOffset> = ArrayList<FlatBufferOffset>()
    private let allExpression: ArrayList<FlatBufferOffset> = ArrayList<FlatBufferOffset>()
    private let allCustomTypeDef: ArrayList<FlatBufferOffset> = ArrayList<FlatBufferOffset>()

    private let serializedBlockGroups: HashSet<Int64> = HashSet<Int64>()
    private let serializedLiteralValues: HashSet<Int64> = HashSet<Int64>()

    private var packageInitFunc: UInt32 = 0u32
    private var packageLiteralInitFunc: UInt32 = 0u32

    public init() {}

    public init(pkg: Package) {
        this.pkg = pkg
    }

    private func GetId(obj: Value): UInt32 {
        if (!value2Id.contains(obj.nodeId)) {
            valueCount++
            value2Id[obj.nodeId] = valueCount
            allValue.add(0u32)
            valueKind.add(0u8)
            valueQueue.add(obj)
        }
        return value2Id[obj.nodeId]
    }

    private func GetId(obj: Type): UInt32 {
        if (!type2Id.contains(obj.objectId)) {
            typeCount++
            type2Id[obj.objectId] = typeCount
            allType.add(0u32)
            typeKind.add(0u8)
            typeQueue.add(obj)
        }
        return type2Id[obj.objectId]
    }

    private func GetId(obj: Expression): UInt32 {
        if (!expr2Id.contains(obj.nodeId)) {
            exprCount++
            expr2Id[obj.nodeId] = exprCount
            allExpression.add(0u32)
            exprKind.add(0u8)
            exprQueue.add(obj)
        }
        return expr2Id[obj.nodeId]
    }

    private func GetId(obj: CustomTypeDef): UInt32 {
        if (!def2Id.contains(obj.nodeId)) {
            defCount++
            def2Id[obj.nodeId] = defCount
            allCustomTypeDef.add(0u32)
            defKind.add(0u8)
            defQueue.add(obj)
        }
        return def2Id[obj.nodeId]
    }

    private func GetId(obj: Option<Value>): UInt32 {
        return if (let Some(value) <- obj) { GetId(value) } else { 0u32 }
    }

    private func GetId(obj: Option<Type>): UInt32 {
        return if (let Some(value) <- obj) { GetId(value) } else { 0u32 }
    }

    private func GetId(obj: Option<Expression>): UInt32 {
        return if (let Some(value) <- obj) { GetId(value) } else { 0u32 }
    }

    private func GetId(obj: Option<CustomTypeDef>): UInt32 {
        return if (let Some(value) <- obj) { GetId(value) } else { 0u32 }
    }

    private func GetId(objs: ArrayList<Type>): ArrayList<UInt32> {
        let indices = ArrayList<UInt32>()
        for (obj in objs) { indices.add(GetId(obj)) }
        return indices
    }

    private func GetId(objs: ArrayList<Value>): ArrayList<UInt32> {
        let indices = ArrayList<UInt32>()
        for (obj in objs) { indices.add(GetId(obj)) }
        return indices
    }

    private func GetId(objs: ArrayList<Expression>): ArrayList<UInt32> {
        let indices = ArrayList<UInt32>()
        for (obj in objs) { indices.add(GetId(obj)) }
        return indices
    }

    private func GetId(objs: ArrayList<CustomTypeDef>): ArrayList<UInt32> {
        let indices = ArrayList<UInt32>()
        for (obj in objs) { indices.add(GetId(obj)) }
        return indices
    }

    private func GetId(objs: HashSet<Value>): ArrayList<UInt32> {
        let indices = ArrayList<UInt32>()
        for (obj in objs) { indices.add(GetId(obj)) }
        return indices
    }

    private func Serialize(obj: DebugLocation): FlatBufferOffset {
        let beginPos = CreatePos(builder, obj.GetBeginPos().line, obj.GetBeginPos().column)
        let endPos = CreatePos(builder, obj.GetEndPos().line, obj.GetEndPos().column)
        let scope = obj.GetScopeInfo()
        return CreateDebugLocationDirect(
            builder, Some(obj.GetAbsPath()), obj.GetFileID(), beginPos, endPos, Some(scope))
    }

    private func Serialize(obj: AnnoInfo): FlatBufferOffset {
        let instances = ArrayList<FlatBufferOffset>()
        for (instance in obj.GetCustomAnnoInstances()) {
            let argStrings = ArrayList<FlatBufferOffset>()
            for (arg in instance.GetArgValues()) {
                argStrings.add(builder.CreateSharedString(arg))
            }
            let location = Serialize(instance.GetDebugLocation())
            instances.add(CreateCustomAnnoInstanceDirect(builder, Some(instance.GetAnnoClassName()),
                if (argStrings.isEmpty()) { None } else { Some(argStrings) }, location))
        }
        return CreateAnnoInfoDirect(builder, Some(obj.GetAnnoFactoryFuncMangledName()),
            if (instances.isEmpty()) { None } else { Some(instances) })
    }

    private func Serialize(obj: Base): FlatBufferOffset {
        let annoTypes = ArrayList<UInt8>()
        let annos = ArrayList<FlatBufferOffset>()
        for ((annotationType, annotation) in obj.GetAnno().GetAnnos()) {
            if (annotationType == TypeInfo.of<NeedCheckArrayBound>()) {
                annoTypes.add(CHIRFB_ANNOTATION_NEED_CHECK_ARRAY_BOUND)
                let value = NeedCheckArrayBound.Extract(
                    (annotation as Annotation<Bool>).getOrThrow())
                annos.add(CreateNeedCheckArrayBound(builder, value))
            } else if (annotationType == TypeInfo.of<NeedCheckCast>()) {
                annoTypes.add(CHIRFB_ANNOTATION_NEED_CHECK_CAST)
                let value = NeedCheckCast.Extract((annotation as Annotation<Bool>).getOrThrow())
                annos.add(CreateNeedCheckCast(builder, value))
            } else if (annotationType == TypeInfo.of<DebugLocationInfoForWarning>()) {
                annoTypes.add(CHIRFB_ANNOTATION_DEBUG_LOCATION_INFO_FOR_WARNING)
                let location = DebugLocationInfoForWarning.Extract(
                    (annotation as Annotation<DebugLocation>).getOrThrow())
                annos.add(Serialize(location))
            } else if (annotationType == TypeInfo.of<LinkTypeInfo>()) {
                annoTypes.add(CHIRFB_ANNOTATION_LINK_TYPE_INFO)
                let linkage = LinkTypeInfo.Extract(
                    (annotation as Annotation<BasicLinkage>).getOrThrow())
                annos.add(CreateLinkTypeInfo(builder, Int16(LinkageToInt(linkage))))
            } else if (annotationType == TypeInfo.of<SkipCheck>()) {
                annoTypes.add(CHIRFB_ANNOTATION_SKIP_CHECK)
                let skipKind = SkipCheck.Extract((annotation as Annotation<SkipKind>).getOrThrow())
                annos.add(CreateSkipCheck(builder, UInt8(SkipKindIndex(skipKind))))
            } else if (annotationType == TypeInfo.of<WrappedRawMethod>()) {
                let rawMethod = WrappedRawMethod.Extract(
                    (annotation as Annotation<Option<Function>>).getOrThrow())
                if (let Some(method) <- rawMethod) {
                    if (method.GetBody().isNone()) { continue }
                }
                annoTypes.add(CHIRFB_ANNOTATION_WRAPPED_RAW_METHOD)
                let rawMethodId = if (let Some(method) <- rawMethod) {
                    GetId((method as Value).getOrThrow())
                } else {
                    0u32
                }
                annos.add(CreateWrappedRawMethod(builder, rawMethodId))
            } else if (annotationType == TypeInfo.of<NeverOverflowInfo>()) {
                annoTypes.add(CHIRFB_ANNOTATION_NEVER_OVERFLOW_INFO)
                let value = NeverOverflowInfo.Extract((annotation as Annotation<Bool>).getOrThrow())
                annos.add(CreateNeverOverflowInfo(builder, value))
            } else if (annotationType == TypeInfo.of<GeneratedFromForIn>()) {
                annoTypes.add(CHIRFB_ANNOTATION_GENERATED_FROM_FOR_IN)
                let value = GeneratedFromForIn.Extract((annotation as Annotation<Bool>).getOrThrow())
                annos.add(CreateGeneratedFromForIn(builder, value))
            } else if (annotationType == TypeInfo.of<IsAutoEnvClass>()) {
                annoTypes.add(CHIRFB_ANNOTATION_IS_AUTO_ENV_CLASS)
                let value = IsAutoEnvClass.Extract((annotation as Annotation<Bool>).getOrThrow())
                annos.add(CreateIsAutoEnvClass(builder, value))
            } else if (annotationType == TypeInfo.of<IsCapturedClassInCC>()) {
                annoTypes.add(CHIRFB_ANNOTATION_IS_CAPTURED_CLASS_IN_CC)
                let value = IsCapturedClassInCC.Extract((annotation as Annotation<Bool>).getOrThrow())
                annos.add(CreateIsCapturedClassInCC(builder, value))
            } else if (annotationType == TypeInfo.of<EnumCaseIndex>()) {
                annoTypes.add(CHIRFB_ANNOTATION_ENUM_CASE_INDEX)
                let index = EnumCaseIndex.Extract(
                    (annotation as Annotation<Option<Int64>>).getOrThrow())
                annos.add(CreateEnumCaseIndex(builder, if (let Some(value) <- index) { value } else { -1 }))
            } else if (annotationType == TypeInfo.of<VirMethodOffset>()) {
                annoTypes.add(CHIRFB_ANNOTATION_VIR_METHOD_OFFSET)
                let offset = VirMethodOffset.Extract(
                    (annotation as Annotation<Option<Int64>>).getOrThrow())
                annos.add(CreateVirMethodOffset(builder, if (let Some(value) <- offset) { value } else { -1 }))
            } else if (annotationType == TypeInfo.of<OverrideSrcFuncType>()) {
                annoTypes.add(CHIRFB_ANNOTATION_OVERRIDE_SRC_FUNC_TYPE)
                let funcType = OverrideSrcFuncType.Extract(
                    (annotation as Annotation<Option<FuncType>>).getOrThrow())
                let typeId = if (let Some(value) <- funcType) {
                    GetId((value as Type).getOrThrow())
                } else {
                    0u32
                }
                annos.add(CreateOverrideSrcFuncType(builder, typeId))
            } else if (annotationType == TypeInfo.of<AnnoFactoryInfo>()) {
                continue
            } else {
                CJC_ABORT()
            }
        }
        let location = Serialize(GetDebugLocation(obj))
        return CreateBaseDirect(builder, Some(annoTypes), Some(annos), location, obj.GetAttributeInfo().GetRawAttrs())
    }

    private func Serialize(obj: MemberVarInfo): FlatBufferOffset {
        let initializerFunc = if (let Some(value) <- obj.initializerFunc) {
            GetId((value as Value).getOrThrow())
        } else {
            0u32
        }
        let outerDef = if (let Some(value) <- obj.outerDef) { GetId(value) } else { 0u32 }
        return CreateMemberVarInfoDirect(builder, Some(obj.name), Some(obj.rawMangledName), GetId(obj.ty),
            obj.attributeInfo.GetRawAttrs(), Serialize(obj.loc), Serialize(obj.annoInfo), initializerFunc, outerDef)
    }

    private func Serialize(obj: EnumCtorInfo): FlatBufferOffset {
        let funcType = if (let Some(value) <- obj.funcType) {
            GetId((value as Type).getOrThrow())
        } else {
            0u32
        }
        return CreateEnumCtorInfoDirect(builder, Some(obj.name), Some(obj.mangledName), funcType, 0u32)
    }

    private func Serialize(obj: Type): FlatBufferOffset {
        let kind = UInt8(TypeKindIndex(obj.GetTypeKind()))
        let argTys = GetId(obj.GetTypeArgs())
        return CreateTypeDirect(builder, kind, if (argTys.isEmpty()) { None } else { Some(argTys) })
    }

    private func Serialize(obj: RawArrayType): FlatBufferOffset {
        let base = Serialize((obj as Type).getOrThrow())
        return CreateRawArrayType(builder, base, UInt32(obj.GetDims()))
    }

    private func Serialize(obj: VArrayType): FlatBufferOffset {
        let base = Serialize((obj as Type).getOrThrow())
        return CreateVArrayType(builder, base, Int64(obj.GetSize()))
    }

    private func Serialize(obj: FuncType): FlatBufferOffset {
        let base = Serialize((obj as Type).getOrThrow())
        return CreateFuncType(builder, base, obj.IsCFunc(), obj.HasVarArg())
    }

    private func Serialize(obj: CustomType): FlatBufferOffset {
        let base = Serialize((obj as Type).getOrThrow())
        return CreateCustomType(builder, base, GetId(obj.GetCustomTypeDef()))
    }

    private func Serialize(obj: GenericType): FlatBufferOffset {
        let base = Serialize((obj as Type).getOrThrow())
        let upperBounds = GetId(obj.GetUpperBounds())
        return CreateGenericTypeDirect(builder, base, Some(obj.GetIdentifier()), Some(obj.GetSrcCodeIdentifier()),
            if (upperBounds.isEmpty()) { None } else { Some(upperBounds) })
    }

    private func Serialize(obj: Value): FlatBufferOffset {
        let base = Serialize((obj as Base).getOrThrow())
        let kind = match (obj.GetValueKind()) {
            case ValueKind.KIND_LITERAL => 0u8
            case ValueKind.KIND_GLOBALVAR => 1u8
            case ValueKind.KIND_PARAMETER => 2u8
            case ValueKind.KIND_LOCALVAR => 3u8
            case ValueKind.KIND_FUNC => 4u8
            case ValueKind.KIND_BLOCK => 5u8
            case ValueKind.KIND_BLOCK_GROUP => 6u8
        }
        return CreateValueDirect(builder, base, GetId(obj.GetType()), Some(obj.GetIdentifier()), kind)
    }

    private func Serialize(obj: Parameter): FlatBufferOffset {
        let base = Serialize((obj as Value).getOrThrow())
        let ownedFunc = if (let Some(value) <- obj.GetOwnerFunc()) {
            GetId((value as Value).getOrThrow())
        } else {
            0u32
        }
        let ownedLambda = if (let Some(value) <- obj.GetOwnerLambda()) {
            GetId((value as Expression).getOrThrow())
        } else {
            0u32
        }
        return CreateParameterDirect(builder, base, ownedFunc, ownedLambda,
            Some(obj.GetSrcCodeIdentifier()), Serialize(obj.GetAnnoInfo()))
    }

    private func Serialize(obj: LocalVar): FlatBufferOffset {
        let base = Serialize((obj as Value).getOrThrow())
        return CreateLocalVarDirect(builder, base, GetId(obj.GetExpr()), obj.IsRetValue(),
            Some(obj.GetSrcCodeIdentifier()))
    }

    private func Serialize(obj: GlobalValue): FlatBufferOffset {
        let base = Serialize((obj as Value).getOrThrow())
        let declaredParent = GetId(obj.GetParentCustomTypeDef())
        let features = ArrayList<FlatBufferOffset>()
        for (name in obj.GetFeatures()) {
            features.add(builder.CreateSharedString(name))
        }
        return CreateGlobalValueDirect(builder, base, Some(obj.GetSrcCodeIdentifier()),
            Some(obj.GetRawMangledName()), Some(obj.GetPackageName()), declaredParent,
            if (features.isEmpty()) { None } else { Some(features) }, Serialize(obj.GetAnnoInfo()))
    }

    private func Serialize(obj: GlobalVar): FlatBufferOffset {
        let base = Serialize((obj as GlobalValue).getOrThrow())
        return CreateGlobalVar(builder, base, GetId(obj.GetInitializerValue()))
    }

    private func Serialize(obj: Block): FlatBufferOffset {
        let base = Serialize((obj as Value).getOrThrow())
        let parentGroup = if (let Some(value) <- obj.GetParentBlockGroup()) {
            GetId((value as Value).getOrThrow())
        } else {
            0u32
        }
        let exprs = GetId(obj.GetExpressions())
        let predecessors = ArrayList<UInt32>()
        for (predecessor in obj.GetPredecessors()) {
            predecessors.add(GetId((predecessor as Value).getOrThrow()))
        }
        let exceptionCatchList = ArrayList<UInt32>()
        if (obj.IsLandingPadBlock()) {
            for (exception in obj.GetExceptions()) {
                exceptionCatchList.add(GetId((exception as Type).getOrThrow()))
            }
        }
        return CreateBlockDirect(builder, base, parentGroup,
            if (exprs.isEmpty()) { None } else { Some(exprs) },
            if (predecessors.isEmpty()) { None } else { Some(predecessors) }, obj.IsLandingPadBlock(),
            if (exceptionCatchList.isEmpty()) { None } else { Some(exceptionCatchList) })
    }

    private func Serialize(obj: BlockGroup): FlatBufferOffset {
        CJC_ASSERT(obj.GetOwnerFunc().isSome() || obj.GetOwnerExpression().isSome())
        let base = Serialize((obj as Value).getOrThrow())
        let entryBlock = if (let Some(value) <- obj.GetEntryBlock()) {
            GetId((value as Value).getOrThrow())
        } else {
            0u32
        }
        let blocks = ArrayList<UInt32>()
        for (block in obj.GetBlocks()) {
            blocks.add(GetId((block as Value).getOrThrow()))
        }
        let ownedFunc = if (let Some(value) <- obj.GetOwnerFunc()) {
            GetId((value as Value).getOrThrow())
        } else {
            0u32
        }
        let ownedExpression = if (let Some(value) <- obj.GetOwnerExpression()) {
            GetId(value)
        } else {
            0u32
        }
        return CreateBlockGroupDirect(builder, base, entryBlock,
            if (blocks.isEmpty()) { None } else { Some(blocks) }, ownedFunc, ownedExpression)
    }

    private func Serialize(obj: Function): FlatBufferOffset {
        let base = Serialize((obj as GlobalValue).getOrThrow())
        var genericDecl = 0u32
        if (let Some(genericFunction) <- obj.GetGenericDecl()) {
            if (genericFunction.IsFuncWithBody()) {
                genericDecl = GetId((genericFunction as Value).getOrThrow())
            }
        }
        var originalLambdaInfo = 0u32
        if (obj.GetFuncKind() == FuncKind.LAMBDA) {
            if (let Some(info) <- obj.originalLambdaInfo) {
                let genericTypeParams = ArrayList<UInt32>()
                for (param in info.genericTypeParams) {
                    genericTypeParams.add(GetId((param as Type).getOrThrow()))
                }
                originalLambdaInfo = CreateFuncSigInfoDirect(builder, Some(info.funcName),
                    GetId((info.funcType as Type).getOrThrow()),
                    if (genericTypeParams.isEmpty()) { None } else { Some(genericTypeParams) })
            }
        }
        let genericTypeParams = ArrayList<UInt32>()
        for (param in obj.GetGenericTypeParams()) {
            genericTypeParams.add(GetId((param as Type).getOrThrow()))
        }
        let paramDftValHostFunc = if (let Some(value) <- obj.GetParamDftValHostFunc()) {
            GetId((value as Value).getOrThrow())
        } else {
            0u32
        }
        var body = 0u32
        let params = ArrayList<UInt32>()
        for (param in obj.GetParams()) {
            params.add(GetId((param as Value).getOrThrow()))
        }
        var retVal = 0u32
        let propLoc = Serialize(obj.GetPropLocation())
        if (obj.IsFuncWithBody()) {
            body = GetId((obj.GetBody().getOrThrow() as Value).getOrThrow())
            if (let Some(value) <- obj.GetReturnValue()) {
                retVal = GetId((value as Value).getOrThrow())
            }
        }
        return CreateFunctionDirect(builder, base, genericDecl, UInt8(FuncKindIndex(obj.GetFuncKind())),
            obj.IsFastNative(), obj.IsCFFIWrapper(), originalLambdaInfo,
            if (genericTypeParams.isEmpty()) { None } else { Some(genericTypeParams) }, paramDftValHostFunc, body,
            if (params.isEmpty()) { None } else { Some(params) }, retVal, propLoc,
            obj.localId, obj.blockId, obj.blockGroupId)
    }

    private func Serialize(obj: LiteralValue): FlatBufferOffset {
        let base = Serialize((obj as Value).getOrThrow())
        let literalKind = match (obj.literalKind) {
            case LiteralKind.BOOL => 0u8
            case LiteralKind.RUNE => 1u8
            case LiteralKind.INT => 2u8
            case LiteralKind.FLOAT => 3u8
            case LiteralKind.STRING => 4u8
            case LiteralKind.UNIT => 5u8
            case LiteralKind.NULL => 6u8
        }
        return CreateLiteralValue(builder, base, literalKind)
    }

    private func Serialize(obj: BoolLiteral): FlatBufferOffset {
        return CreateBoolLiteral(builder, Serialize((obj as LiteralValue).getOrThrow()), obj.GetVal())
    }

    private func Serialize(obj: RuneLiteral): FlatBufferOffset {
        return CreateRuneLiteral(builder, Serialize((obj as LiteralValue).getOrThrow()), UInt32(obj.GetVal()))
    }

    private func Serialize(obj: StringLiteral): FlatBufferOffset {
        let base = Serialize((obj as LiteralValue).getOrThrow())
        return CreateStringLiteral(builder, base, builder.CreateSharedString(obj.GetVal()))
    }

    private func Serialize(obj: IntLiteral): FlatBufferOffset {
        return CreateIntLiteral(builder, Serialize((obj as LiteralValue).getOrThrow()), obj.GetUnsignedVal())
    }

    private func Serialize(obj: FloatLiteral): FlatBufferOffset {
        return CreateFloatLiteral(builder, Serialize((obj as LiteralValue).getOrThrow()), obj.GetVal())
    }

    private func Serialize(obj: UnitLiteral): FlatBufferOffset {
        return CreateUnitLiteral(builder, Serialize((obj as LiteralValue).getOrThrow()))
    }

    private func Serialize(obj: NullLiteral): FlatBufferOffset {
        return CreateNullLiteral(builder, Serialize((obj as LiteralValue).getOrThrow()))
    }

    private func Serialize(obj: Expression): FlatBufferOffset {
        let base = Serialize((obj as Base).getOrThrow())
        let operands = GetId(GetOperands(obj))
        let blockGroups = ArrayList<UInt32>()
        for (group in obj.GetBlockGroups()) {
            blockGroups.add(GetId((group as Value).getOrThrow()))
        }
        let owner = if (let Some(value) <- obj.GetParentBlock()) {
            GetId((value as Value).getOrThrow())
        } else {
            0u32
        }
        let resultLocalVar = if (let Some(value) <- obj.GetResult()) {
            GetId((value as Value).getOrThrow())
        } else {
            0u32
        }
        let resultTy = GetId(obj.GetResultType())
        return CreateExpressionDirect(builder, base, ToPackageExprKind(obj),
            if (operands.isEmpty()) { None } else { Some(operands) },
            if (blockGroups.isEmpty()) { None } else { Some(blockGroups) }, owner, resultLocalVar, resultTy)
    }

    private func Serialize(obj: UnaryExpression): FlatBufferOffset {
        let base = Serialize((obj as Expression).getOrThrow())
        return CreateUnaryExpressionBase(builder, base, UInt8(OverflowStrategyIndex(obj.GetOverflowStrategy())))
    }

    private func Serialize(obj: BinaryExpression): FlatBufferOffset {
        let base = Serialize((obj as Expression).getOrThrow())
        return CreateBinaryExpressionBase(builder, base, UInt8(OverflowStrategyIndex(obj.GetOverflowStrategy())))
    }

    private func Serialize(obj: Allocate): FlatBufferOffset {
        return CreateAllocateBase(builder, Serialize((obj as Expression).getOrThrow()), GetId(obj.GetType()))
    }

    private func Serialize(obj: AllocateWithException): FlatBufferOffset {
        return CreateAllocateBase(builder, Serialize((obj as Expression).getOrThrow()), GetId(obj.GetType()))
    }

    private func Serialize(obj: GetElementRef): FlatBufferOffset {
        let base = Serialize((obj as Expression).getOrThrow())
        let path = obj.GetPath()
        return CreateGetElementRefDirect(builder, base, if (path.isEmpty()) { None } else { Some(path) })
    }

    private func Serialize(obj: GetElementByName): FlatBufferOffset {
        let base = Serialize((obj as Expression).getOrThrow())
        return CreateGetElementByName(builder, base, builder.CreateVectorOfStrings(obj.GetNames()))
    }

    private func Serialize(obj: StoreElementRef): FlatBufferOffset {
        return CreateStoreElementRefDirect(builder, Serialize((obj as Expression).getOrThrow()), Some(obj.GetPath()))
    }

    private func Serialize(obj: StoreElementByName): FlatBufferOffset {
        let base = Serialize((obj as Expression).getOrThrow())
        return CreateStoreElementByName(builder, base, builder.CreateVectorOfStrings(obj.GetNames()))
    }

    private func Serialize(obj: Apply): FlatBufferOffset {
        let expression = Serialize((obj as Expression).getOrThrow())
        let instantiatedTypeArgs = GetId(obj.GetInstantiatedTypeArgs())
        let funcCall = CreateFuncCallDirect(builder, expression,
            if (instantiatedTypeArgs.isEmpty()) { None } else { Some(instantiatedTypeArgs) }, GetId(obj.GetThisType()))
        return CreateApplyBase(builder, funcCall, obj.IsSuperCall())
    }

    private func Serialize(obj: ApplyWithException): FlatBufferOffset {
        let expression = Serialize((obj as Expression).getOrThrow())
        let instantiatedTypeArgs = GetId(obj.GetInstantiatedTypeArgs())
        let funcCall = CreateFuncCallDirect(builder, expression,
            if (instantiatedTypeArgs.isEmpty()) { None } else { Some(instantiatedTypeArgs) }, GetId(obj.GetThisType()))
        return CreateApplyBase(builder, funcCall, false)
    }

    private func Serialize(obj: FuncSigInfo): FlatBufferOffset {
        let genericTypeParams = ArrayList<UInt32>()
        for (param in obj.genericTypeParams) {
            genericTypeParams.add(GetId((param as Type).getOrThrow()))
        }
        return CreateFuncSigInfoDirect(builder, Some(obj.funcName), GetId((obj.funcType as Type).getOrThrow()),
            if (genericTypeParams.isEmpty()) { None } else { Some(genericTypeParams) })
    }

    private func Serialize(obj: Invoke): FlatBufferOffset {
        let expression = Serialize((obj as Expression).getOrThrow())
        let instantiatedTypeArgs = GetId(obj.GetInstantiatedTypeArgs())
        let funcCall = CreateFuncCallDirect(builder, expression,
            if (instantiatedTypeArgs.isEmpty()) { None } else { Some(instantiatedTypeArgs) }, GetId(obj.GetThisType()))
        return CreateInvokeBase(builder, funcCall, Serialize(obj.virMethodCtx))
    }

    private func Serialize(obj: InvokeWithException): FlatBufferOffset {
        let expression = Serialize((obj as Expression).getOrThrow())
        let instantiatedTypeArgs = GetId(obj.GetInstantiatedTypeArgs())
        let funcCall = CreateFuncCallDirect(builder, expression,
            if (instantiatedTypeArgs.isEmpty()) { None } else { Some(instantiatedTypeArgs) }, GetId(obj.GetThisType()))
        return CreateInvokeBase(builder, funcCall, Serialize(obj.virMethodCtx))
    }

    private func Serialize(obj: InvokeStatic): FlatBufferOffset {
        let expression = Serialize((obj as Expression).getOrThrow())
        let instantiatedTypeArgs = GetId(obj.GetInstantiatedTypeArgs())
        let funcCall = CreateFuncCallDirect(builder, expression,
            if (instantiatedTypeArgs.isEmpty()) { None } else { Some(instantiatedTypeArgs) }, GetId(obj.GetThisType()))
        return CreateInvokeBase(builder, funcCall, Serialize(obj.virMethodCtx))
    }

    private func Serialize(obj: InvokeStaticWithException): FlatBufferOffset {
        let expression = Serialize((obj as Expression).getOrThrow())
        let instantiatedTypeArgs = GetId(obj.GetInstantiatedTypeArgs())
        let funcCall = CreateFuncCallDirect(builder, expression,
            if (instantiatedTypeArgs.isEmpty()) { None } else { Some(instantiatedTypeArgs) }, GetId(obj.GetThisType()))
        return CreateInvokeBase(builder, funcCall, Serialize(obj.virMethodCtx))
    }

    private func Serialize(obj: TypeCast): FlatBufferOffset {
        let base = Serialize((obj as Expression).getOrThrow())
        return CreateNumericCastBase(builder, base, UInt8(OverflowStrategyIndex(obj.GetOverflowStrategy())))
    }

    private func Serialize(obj: TypeCastWithException): FlatBufferOffset {
        let base = Serialize((obj as Expression).getOrThrow())
        return CreateNumericCastBase(builder, base, UInt8(OverflowStrategyIndex(obj.GetOverflowStrategy())))
    }

    private func Serialize(obj: InstanceOf): FlatBufferOffset {
        return CreateInstanceOf(builder, Serialize((obj as Expression).getOrThrow()), GetId(obj.GetType()))
    }

    private func Serialize(obj: Branch): FlatBufferOffset {
        return CreateBranch(builder, Serialize((obj as Expression).getOrThrow()), UInt8(SourceExprIndex(obj.GetSourceExpr())))
    }

    private func Serialize(obj: MultiBranch): FlatBufferOffset {
        let base = Serialize((obj as Expression).getOrThrow())
        let caseValues = obj.GetCaseVals()
        return CreateMultiBranchDirect(builder, base, if (caseValues.isEmpty()) { None } else { Some(caseValues) })
    }

    private func Serialize(obj: GetInstantiateValue): FlatBufferOffset {
        let base = Serialize((obj as Expression).getOrThrow())
        let instantiateTypes = GetId(obj.GetInstantiateTypes())
        return CreateGetInstantiateValueDirect(builder, base,
            if (instantiateTypes.isEmpty()) { None } else { Some(instantiateTypes) })
    }

    private func Serialize(obj: GetRTTIStatic): FlatBufferOffset {
        return CreateGetRTTIStatic(builder, Serialize((obj as Expression).getOrThrow()), GetId(obj.GetRTTIType()))
    }

    private func Serialize(obj: Field): FlatBufferOffset {
        let base = Serialize((obj as Expression).getOrThrow())
        let path = obj.GetPath()
        return CreateFieldDirect(builder, base, if (path.isEmpty()) { None } else { Some(path) })
    }

    private func Serialize(obj: FieldByName): FlatBufferOffset {
        let base = Serialize((obj as Expression).getOrThrow())
        return CreateFieldByName(builder, base, builder.CreateVectorOfStrings(obj.GetNames()))
    }

    private func Serialize(obj: RawArrayAllocate): FlatBufferOffset {
        return CreateRawArrayAllocateBase(builder, Serialize((obj as Expression).getOrThrow()), GetId(obj.GetElementType()))
    }

    private func Serialize(obj: RawArrayAllocateWithException): FlatBufferOffset {
        return CreateRawArrayAllocateBase(builder, Serialize((obj as Expression).getOrThrow()), GetId(obj.GetElementType()))
    }

    private func Serialize(obj: Intrinsic): FlatBufferOffset {
        let expression = Serialize((obj as Expression).getOrThrow())
        let instantiatedTypeArgs = GetId(obj.GetInstantiatedTypeArgs())
        let funcCall = CreateFuncCallDirect(builder, expression,
            if (instantiatedTypeArgs.isEmpty()) { None } else { Some(instantiatedTypeArgs) }, 0u32)
        return CreateIntrinsicBase(builder, funcCall, IntrinsicKindToPackageIntrinsicKind(obj.GetIntrinsicKind()))
    }

    private func Serialize(obj: IntrinsicWithException): FlatBufferOffset {
        let expression = Serialize((obj as Expression).getOrThrow())
        let instantiatedTypeArgs = GetId(obj.GetInstantiatedTypeArgs())
        let funcCall = CreateFuncCallDirect(builder, expression,
            if (instantiatedTypeArgs.isEmpty()) { None } else { Some(instantiatedTypeArgs) }, 0u32)
        return CreateIntrinsicBase(builder, funcCall, IntrinsicKindToPackageIntrinsicKind(obj.GetIntrinsicKind()))
    }

    private func Serialize(obj: Debug): FlatBufferOffset {
        CJC_ASSERT(!obj.GetOperands().isEmpty())
        return CreateDebugDirect(builder, Serialize((obj as Expression).getOrThrow()), Some(obj.GetSrcCodeIdentifier()))
    }

    private func Serialize(obj: Spawn): FlatBufferOffset {
        let executeClosure = if (let Some(value) <- obj.GetExecuteClosure()) {
            GetId((value as Value).getOrThrow())
        } else {
            0u32
        }
        return CreateSpawnBase(builder, Serialize((obj as Expression).getOrThrow()), executeClosure)
    }

    private func Serialize(obj: SpawnWithException): FlatBufferOffset {
        let executeClosure = if (let Some(value) <- obj.GetExecuteClosure()) {
            GetId((value as Value).getOrThrow())
        } else {
            0u32
        }
        return CreateSpawnBase(builder, Serialize((obj as Expression).getOrThrow()), executeClosure)
    }

    private func Serialize(obj: Lambda): FlatBufferOffset {
        CJC_ASSERT(obj.GetBlockGroups().size == 1)
        CJC_ASSERT(obj.GetBody().isSome())
        let base = Serialize((obj as Expression).getOrThrow())
        let funcTy = if (let Some(value) <- obj.GetFuncType()) { GetId((value as Type).getOrThrow()) } else { 0u32 }
        let params = ArrayList<UInt32>()
        for (param in obj.GetParams()) { params.add(GetId((param as Value).getOrThrow())) }
        let genericTypeParams = ArrayList<UInt32>()
        for (param in obj.GetGenericTypeParams()) { genericTypeParams.add(GetId((param as Type).getOrThrow())) }
        let body = GetId((obj.GetBody().getOrThrow() as Value).getOrThrow())
        let retVal = if (let Some(value) <- obj.GetReturnValue()) {
            GetId((value as Value).getOrThrow())
        } else {
            0u32
        }
        return CreateLambdaDirect(builder, base, funcTy, obj.IsLocalFunc(), Some(obj.GetIdentifier()),
            Some(obj.GetSrcCodeIdentifier()), if (params.isEmpty()) { None } else { Some(params) },
            if (genericTypeParams.isEmpty()) { None } else { Some(genericTypeParams) }, body, retVal,
            obj.IsCompileTimeValue())
    }

    private func Dispatch(obj: Type): FlatBufferOffset {
        let index = Int64(GetId(obj) - 1u32)
        return match (obj.GetTypeKind()) {
            case TypeKind.TYPE_INT8 | TypeKind.TYPE_INT16 | TypeKind.TYPE_INT32 | TypeKind.TYPE_INT64 |
                TypeKind.TYPE_INT_NATIVE | TypeKind.TYPE_UINT8 | TypeKind.TYPE_UINT16 | TypeKind.TYPE_UINT32 |
                TypeKind.TYPE_UINT64 | TypeKind.TYPE_UINT_NATIVE | TypeKind.TYPE_FLOAT16 | TypeKind.TYPE_FLOAT32 |
                TypeKind.TYPE_FLOAT64 | TypeKind.TYPE_RUNE | TypeKind.TYPE_BOOLEAN | TypeKind.TYPE_UNIT |
                TypeKind.TYPE_NOTHING | TypeKind.TYPE_VOID | TypeKind.TYPE_TUPLE | TypeKind.TYPE_CPOINTER |
                TypeKind.TYPE_CSTRING | TypeKind.TYPE_REFTYPE | TypeKind.TYPE_BOXTYPE | TypeKind.TYPE_THIS =>
                typeKind[index] = CHIRFB_TYPE_ELEM_TYPE
                Serialize(obj)
            case TypeKind.TYPE_STRUCT | TypeKind.TYPE_ENUM | TypeKind.TYPE_CLASS =>
                typeKind[index] = CHIRFB_TYPE_ELEM_CUSTOM_TYPE
                Serialize((obj as CustomType).getOrThrow())
            case TypeKind.TYPE_FUNC =>
                typeKind[index] = CHIRFB_TYPE_ELEM_FUNC_TYPE
                Serialize((obj as FuncType).getOrThrow())
            case TypeKind.TYPE_RAWARRAY =>
                typeKind[index] = CHIRFB_TYPE_ELEM_RAW_ARRAY_TYPE
                Serialize((obj as RawArrayType).getOrThrow())
            case TypeKind.TYPE_VARRAY =>
                typeKind[index] = CHIRFB_TYPE_ELEM_V_ARRAY_TYPE
                Serialize((obj as VArrayType).getOrThrow())
            case TypeKind.TYPE_GENERIC =>
                typeKind[index] = CHIRFB_TYPE_ELEM_GENERIC_TYPE
                Serialize((obj as GenericType).getOrThrow())
            case TypeKind.TYPE_INVALID =>
                CJC_ABORT()
                0u32
        }
    }

    private func Dispatch(obj: LiteralValue): FlatBufferOffset {
        let index = Int64(GetId((obj as Value).getOrThrow()) - 1u32)
        return match (obj.literalKind) {
            case LiteralKind.BOOL =>
                valueKind[index] = CHIRFB_VALUE_ELEM_BOOL_LITERAL
                Serialize((obj as BoolLiteral).getOrThrow())
            case LiteralKind.RUNE =>
                valueKind[index] = CHIRFB_VALUE_ELEM_RUNE_LITERAL
                Serialize((obj as RuneLiteral).getOrThrow())
            case LiteralKind.INT =>
                valueKind[index] = CHIRFB_VALUE_ELEM_INT_LITERAL
                Serialize((obj as IntLiteral).getOrThrow())
            case LiteralKind.FLOAT =>
                valueKind[index] = CHIRFB_VALUE_ELEM_FLOAT_LITERAL
                Serialize((obj as FloatLiteral).getOrThrow())
            case LiteralKind.STRING =>
                valueKind[index] = CHIRFB_VALUE_ELEM_STRING_LITERAL
                Serialize((obj as StringLiteral).getOrThrow())
            case LiteralKind.UNIT =>
                valueKind[index] = CHIRFB_VALUE_ELEM_UNIT_LITERAL
                Serialize((obj as UnitLiteral).getOrThrow())
            case LiteralKind.NULL =>
                valueKind[index] = CHIRFB_VALUE_ELEM_NULL_LITERAL
                Serialize((obj as NullLiteral).getOrThrow())
        }
    }

    private func Dispatch(obj: Value): FlatBufferOffset {
        let index = Int64(GetId(obj) - 1u32)
        return match (obj.GetValueKind()) {
            case ValueKind.KIND_LITERAL => Dispatch((obj as LiteralValue).getOrThrow())
            case ValueKind.KIND_GLOBALVAR =>
                valueKind[index] = CHIRFB_VALUE_ELEM_GLOBAL_VAR
                Serialize((obj as GlobalVar).getOrThrow())
            case ValueKind.KIND_PARAMETER =>
                valueKind[index] = CHIRFB_VALUE_ELEM_PARAMETER
                Serialize((obj as Parameter).getOrThrow())
            case ValueKind.KIND_LOCALVAR =>
                valueKind[index] = CHIRFB_VALUE_ELEM_LOCAL_VAR
                Serialize((obj as LocalVar).getOrThrow())
            case ValueKind.KIND_FUNC =>
                valueKind[index] = CHIRFB_VALUE_ELEM_FUNCTION
                Serialize((obj as Function).getOrThrow())
            case ValueKind.KIND_BLOCK =>
                valueKind[index] = CHIRFB_VALUE_ELEM_BLOCK
                Serialize((obj as Block).getOrThrow())
            case ValueKind.KIND_BLOCK_GROUP =>
                valueKind[index] = CHIRFB_VALUE_ELEM_BLOCK_GROUP
                Serialize((obj as BlockGroup).getOrThrow())
        }
    }

    private func Dispatch(obj: Expression): FlatBufferOffset {
        let index = Int64(GetId(obj) - 1u32)
        return match (obj.GetExprKind()) {
            case ExprKind.ALLOCATE =>
                exprKind[index] = CHIRFB_EXPRESSION_ELEM_ALLOCATE_BASE
                Serialize((obj as Allocate).getOrThrow())
            case ExprKind.ALLOCATE_WITH_EXCEPTION =>
                exprKind[index] = CHIRFB_EXPRESSION_ELEM_ALLOCATE_BASE
                Serialize((obj as AllocateWithException).getOrThrow())
            case ExprKind.APPLY =>
                exprKind[index] = CHIRFB_EXPRESSION_ELEM_APPLY_BASE
                Serialize((obj as Apply).getOrThrow())
            case ExprKind.APPLY_WITH_EXCEPTION =>
                exprKind[index] = CHIRFB_EXPRESSION_ELEM_APPLY_BASE
                Serialize((obj as ApplyWithException).getOrThrow())
            case ExprKind.ADD | ExprKind.SUB | ExprKind.MUL | ExprKind.DIV | ExprKind.MOD | ExprKind.EXP |
                ExprKind.LSHIFT | ExprKind.RSHIFT | ExprKind.BITAND | ExprKind.BITOR | ExprKind.BITXOR |
                ExprKind.LT | ExprKind.GT | ExprKind.LE | ExprKind.GE | ExprKind.EQUAL | ExprKind.NOTEQUAL |
                ExprKind.AND | ExprKind.OR =>
                exprKind[index] = CHIRFB_EXPRESSION_ELEM_BINARY_EXPRESSION_BASE
                Serialize((obj as BinaryExpression).getOrThrow())
            case ExprKind.BRANCH =>
                exprKind[index] = CHIRFB_EXPRESSION_ELEM_BRANCH
                Serialize((obj as Branch).getOrThrow())
            case ExprKind.DEBUGEXPR =>
                exprKind[index] = CHIRFB_EXPRESSION_ELEM_DEBUG
                Serialize((obj as Debug).getOrThrow())
            case ExprKind.FIELD =>
                exprKind[index] = CHIRFB_EXPRESSION_ELEM_FIELD
                Serialize((obj as Field).getOrThrow())
            case ExprKind.FIELD_BY_NAME =>
                exprKind[index] = CHIRFB_EXPRESSION_ELEM_FIELD_BY_NAME
                Serialize((obj as FieldByName).getOrThrow())
            case ExprKind.GET_ELEMENT_BY_NAME =>
                exprKind[index] = CHIRFB_EXPRESSION_ELEM_GET_ELEMENT_BY_NAME
                Serialize((obj as GetElementByName).getOrThrow())
            case ExprKind.GET_ELEMENT_REF =>
                exprKind[index] = CHIRFB_EXPRESSION_ELEM_GET_ELEMENT_REF
                Serialize((obj as GetElementRef).getOrThrow())
            case ExprKind.GET_INSTANTIATE_VALUE =>
                exprKind[index] = CHIRFB_EXPRESSION_ELEM_GET_INSTANTIATE_VALUE
                Serialize((obj as GetInstantiateValue).getOrThrow())
            case ExprKind.GET_RTTI_STATIC =>
                exprKind[index] = CHIRFB_EXPRESSION_ELEM_GET_RTTI_STATIC
                Serialize((obj as GetRTTIStatic).getOrThrow())
            case ExprKind.INSTANCEOF =>
                exprKind[index] = CHIRFB_EXPRESSION_ELEM_INSTANCE_OF
                Serialize((obj as InstanceOf).getOrThrow())
            case ExprKind.INT_OP_WITH_EXCEPTION =>
                let intOp = (obj as IntOpWithException).getOrThrow()
                let base = Serialize(obj)
                let overflow = UInt8(OverflowStrategyIndex(intOp.GetOverflowStrategy()))
                if (ExprKindMajor(intOp.GetOpKind()) == ExprMajorKind.UNARY_EXPR) {
                    exprKind[index] = CHIRFB_EXPRESSION_ELEM_UNARY_EXPRESSION_BASE
                    CreateUnaryExpressionBase(builder, base, overflow)
                } else {
                    exprKind[index] = CHIRFB_EXPRESSION_ELEM_BINARY_EXPRESSION_BASE
                    CreateBinaryExpressionBase(builder, base, overflow)
                }
            case ExprKind.INTRINSIC =>
                exprKind[index] = CHIRFB_EXPRESSION_ELEM_INTRINSIC_BASE
                Serialize((obj as Intrinsic).getOrThrow())
            case ExprKind.INTRINSIC_WITH_EXCEPTION =>
                exprKind[index] = CHIRFB_EXPRESSION_ELEM_INTRINSIC_BASE
                Serialize((obj as IntrinsicWithException).getOrThrow())
            case ExprKind.INVOKE =>
                exprKind[index] = CHIRFB_EXPRESSION_ELEM_INVOKE_BASE
                Serialize((obj as Invoke).getOrThrow())
            case ExprKind.INVOKE_WITH_EXCEPTION =>
                exprKind[index] = CHIRFB_EXPRESSION_ELEM_INVOKE_BASE
                Serialize((obj as InvokeWithException).getOrThrow())
            case ExprKind.INVOKESTATIC =>
                exprKind[index] = CHIRFB_EXPRESSION_ELEM_INVOKE_BASE
                Serialize((obj as InvokeStatic).getOrThrow())
            case ExprKind.INVOKESTATIC_WITH_EXCEPTION =>
                exprKind[index] = CHIRFB_EXPRESSION_ELEM_INVOKE_BASE
                Serialize((obj as InvokeStaticWithException).getOrThrow())
            case ExprKind.LAMBDA =>
                exprKind[index] = CHIRFB_EXPRESSION_ELEM_LAMBDA
                Serialize((obj as Lambda).getOrThrow())
            case ExprKind.MULTIBRANCH =>
                exprKind[index] = CHIRFB_EXPRESSION_ELEM_MULTI_BRANCH
                Serialize((obj as MultiBranch).getOrThrow())
            case ExprKind.TYPECAST =>
                exprKind[index] = CHIRFB_EXPRESSION_ELEM_NUMERIC_CAST_BASE
                Serialize((obj as TypeCast).getOrThrow())
            case ExprKind.TYPECAST_WITH_EXCEPTION =>
                exprKind[index] = CHIRFB_EXPRESSION_ELEM_NUMERIC_CAST_BASE
                Serialize((obj as TypeCastWithException).getOrThrow())
            case ExprKind.RAW_ARRAY_ALLOCATE =>
                exprKind[index] = CHIRFB_EXPRESSION_ELEM_RAW_ARRAY_ALLOCATE_BASE
                Serialize((obj as RawArrayAllocate).getOrThrow())
            case ExprKind.RAW_ARRAY_ALLOCATE_WITH_EXCEPTION =>
                exprKind[index] = CHIRFB_EXPRESSION_ELEM_RAW_ARRAY_ALLOCATE_BASE
                Serialize((obj as RawArrayAllocateWithException).getOrThrow())
            case ExprKind.SPAWN =>
                exprKind[index] = CHIRFB_EXPRESSION_ELEM_SPAWN_BASE
                Serialize((obj as Spawn).getOrThrow())
            case ExprKind.SPAWN_WITH_EXCEPTION =>
                exprKind[index] = CHIRFB_EXPRESSION_ELEM_SPAWN_BASE
                Serialize((obj as SpawnWithException).getOrThrow())
            case ExprKind.STORE_ELEMENT_BY_NAME =>
                exprKind[index] = CHIRFB_EXPRESSION_ELEM_STORE_ELEMENT_BY_NAME
                Serialize((obj as StoreElementByName).getOrThrow())
            case ExprKind.STORE_ELEMENT_REF =>
                exprKind[index] = CHIRFB_EXPRESSION_ELEM_STORE_ELEMENT_REF
                Serialize((obj as StoreElementRef).getOrThrow())
            case ExprKind.NEG | ExprKind.NOT | ExprKind.BITNOT =>
                exprKind[index] = CHIRFB_EXPRESSION_ELEM_UNARY_EXPRESSION_BASE
                Serialize((obj as UnaryExpression).getOrThrow())
            case ExprKind.GOTO | ExprKind.EXIT | ExprKind.RAISE_EXCEPTION | ExprKind.LOAD | ExprKind.STORE |
                ExprKind.CONSTANT | ExprKind.FORIN_RANGE | ExprKind.FORIN_ITER | ExprKind.FORIN_CLOSED_RANGE |
                ExprKind.TUPLE | ExprKind.BOX | ExprKind.UNBOX | ExprKind.GET_EXCEPTION |
                ExprKind.RAW_ARRAY_LITERAL_INIT | ExprKind.RAW_ARRAY_INIT_BY_VALUE | ExprKind.VARRAY |
                ExprKind.VARRAY_BUILDER | ExprKind.TRANSFORM_TO_GENERIC | ExprKind.TRANSFORM_TO_CONCRETE |
                ExprKind.UNBOX_TO_REF | ExprKind.GET_RTTI =>
                exprKind[index] = CHIRFB_EXPRESSION_ELEM_EXPRESSION
                Serialize(obj)
            case ExprKind.INVALID =>
                CJC_ABORT()
                0u32
        }
    }

    private func Serialize(obj: VirtualMethodInfo): FlatBufferOffset {
        let genericTypeParams = ArrayList<UInt32>()
        for (param in obj.GetGenericTypeParams()) {
            genericTypeParams.add(GetId((param as Type).getOrThrow()))
        }
        let instance = if (let Some(value) <- obj.GetVirtualMethod()) {
            GetId((value as Value).getOrThrow())
        } else {
            0u32
        }
        return CreateVirtualMethodInfoDirect(builder, Some(obj.GetMethodName()),
            GetId((obj.GetMethodSigType() as Type).getOrThrow()),
            if (genericTypeParams.isEmpty()) { None } else { Some(genericTypeParams) }, instance,
            obj.GetAttributeInfo().GetRawAttrs(), GetId((obj.GetOriginalFuncType() as Type).getOrThrow()),
            GetId(obj.GetInstParentType()), GetId(obj.GetMethodInstRetType()))
    }

    private func SerializeVTable(obj: VTableInDef, bufferBuilder: FlatBufferBuilder): ArrayList<FlatBufferOffset> {
        let _ = bufferBuilder
        let result = ArrayList<FlatBufferOffset>()
        for (element in obj.GetTypeVTables()) {
            let parentType = if (let Some(value) <- element.GetSrcParentType()) {
                GetId((value as Type).getOrThrow())
            } else {
                0u32
            }
            let virtualMethods = ArrayList<FlatBufferOffset>()
            for (method in element.GetVirtualMethods()) {
                virtualMethods.add(Serialize(method))
            }
            result.add(CreateVTableInTypeDirect(builder, parentType, Some(virtualMethods)))
        }
        return result
    }

    private func Serialize(obj: CustomTypeDef): FlatBufferOffset {
        let base = Serialize((obj as Base).getOrThrow())
        let methods = ArrayList<UInt32>()
        for (method in obj.GetMethods()) { methods.add(GetId((method as Value).getOrThrow())) }
        let implementedInterfaces = ArrayList<UInt32>()
        for (interfaceType in obj.GetImplementedInterfaceTys()) {
            implementedInterfaces.add(GetId((interfaceType as Type).getOrThrow()))
        }
        let instanceMemberVars = ArrayList<FlatBufferOffset>()
        let memberVars = if (obj.GetCustomKind() == CustomDefKind.TYPE_CLASS) {
            (obj as ClassDef).getOrThrow().GetDirectInstanceVars()
        } else {
            obj.GetAllInstanceVars()
        }
        for (memberVar in memberVars) { instanceMemberVars.add(Serialize(memberVar)) }
        let staticMemberVars = ArrayList<UInt32>()
        for (memberVar in obj.GetStaticMemberVars()) {
            staticMemberVars.add(GetId((memberVar as Value).getOrThrow()))
        }
        let vtable = SerializeVTable(obj.GetDefVTable(), builder)
        let varInitializationFunc = if (let Some(value) <- obj.GetVarInitializationFunc()) {
            GetId((value as Value).getOrThrow())
        } else {
            0u32
        }
        return CreateCustomTypeDefDirect(builder, base, UInt8(CustomDefKindIndex(obj.GetCustomKind())), GetId(obj),
            Some(obj.GetSrcCodeIdentifier()), Some(obj.GetIdentifier()), Some(obj.GetPackageName()), GetId(GetType(obj)),
            GetId(obj.GetGenericDecl()), if (methods.isEmpty()) { None } else { Some(methods) },
            if (implementedInterfaces.isEmpty()) { None } else { Some(implementedInterfaces) }, Some(instanceMemberVars),
            if (staticMemberVars.isEmpty()) { None } else { Some(staticMemberVars) }, Serialize(obj.GetAnnoInfo()),
            Some(vtable), varInitializationFunc)
    }

    private func Serialize(obj: EnumDef): FlatBufferOffset {
        let ctors = ArrayList<FlatBufferOffset>()
        for (ctor in obj.GetCtors()) { ctors.add(Serialize(ctor)) }
        return CreateEnumDefDirect(builder, Serialize((obj as CustomTypeDef).getOrThrow()), Some(ctors), !obj.IsExhaustive())
    }

    private func Serialize(obj: StructDef): FlatBufferOffset {
        return CreateStructDef(builder, Serialize((obj as CustomTypeDef).getOrThrow()), obj.IsCStruct())
    }

    private func Serialize(obj: ClassDef): FlatBufferOffset {
        let annotationTargetIds = ArrayList<UInt32>()
        if (obj.IsAnnotation()) {
            for (target in obj.GetAnnotationTargets()) {
                annotationTargetIds.add(GetId((target as Value).getOrThrow()))
            }
        }
        let superClass = if (let Some(value) <- obj.GetSuperClassTy()) {
            GetId((value as Type).getOrThrow())
        } else {
            0u32
        }
        return CreateClassDefDirect(builder, Serialize((obj as CustomTypeDef).getOrThrow()), obj.IsClass(),
            obj.IsAnnotation(), if (obj.IsAnnotation()) { Some(annotationTargetIds) } else { None }, superClass)
    }

    private func Serialize(obj: ExtendDef): FlatBufferOffset {
        let genericParams = ArrayList<UInt32>()
        for (param in obj.GetGenericTypeParams()) { genericParams.add(GetId((param as Type).getOrThrow())) }
        return CreateExtendDefDirect(builder, Serialize((obj as CustomTypeDef).getOrThrow()),
            GetId(obj.GetExtendedType()), if (genericParams.isEmpty()) { None } else { Some(genericParams) })
    }

    private func Dispatch(obj: CustomTypeDef): FlatBufferOffset {
        let index = Int64(GetId(obj) - 1u32)
        return match (obj.GetCustomKind()) {
            case CustomDefKind.TYPE_STRUCT =>
                defKind[index] = CHIRFB_CUSTOM_TYPE_DEF_ELEM_STRUCT_DEF
                Serialize((obj as StructDef).getOrThrow())
            case CustomDefKind.TYPE_ENUM =>
                defKind[index] = CHIRFB_CUSTOM_TYPE_DEF_ELEM_ENUM_DEF
                Serialize((obj as EnumDef).getOrThrow())
            case CustomDefKind.TYPE_CLASS =>
                defKind[index] = CHIRFB_CUSTOM_TYPE_DEF_ELEM_CLASS_DEF
                Serialize((obj as ClassDef).getOrThrow())
            case CustomDefKind.TYPE_EXTEND =>
                defKind[index] = CHIRFB_CUSTOM_TYPE_DEF_ELEM_EXTEND_DEF
                Serialize((obj as ExtendDef).getOrThrow())
        }
    }

    func Dispatch(): Unit {
        while (!(typeQueue.isEmpty() && valueQueue.isEmpty() && exprQueue.isEmpty() && defQueue.isEmpty())) {
            while (!typeQueue.isEmpty()) {
                let value = typeQueue[0]
                allType[Int64(GetId(value) - 1u32)] = Dispatch(value)
                typeQueue.remove(at: 0)
            }
            while (!valueQueue.isEmpty()) {
                let value = valueQueue[0]
                allValue[Int64(GetId(value) - 1u32)] = Dispatch(value)
                valueQueue.remove(at: 0)
            }
            while (!exprQueue.isEmpty()) {
                let value = exprQueue[0]
                allExpression[Int64(GetId(value) - 1u32)] = Dispatch(value)
                exprQueue.remove(at: 0)
            }
            while (!defQueue.isEmpty()) {
                let value = defQueue[0]
                allCustomTypeDef[Int64(GetId(value) - 1u32)] = Dispatch(value)
                defQueue.remove(at: 0)
            }
        }
        let chirPackage = pkg.getOrThrow()
        if (let Some(value) <- chirPackage.GetPackageInitFunc()) {
            packageInitFunc = GetId((value as Value).getOrThrow())
        }
        if (let Some(value) <- chirPackage.GetPackageLiteralInitFunc()) {
            packageLiteralInitFunc = GetId((value as Value).getOrThrow())
        }
    }

    func Save(filename: String, phase: ToCHIRPhase): Unit {
        let chirPackage = pkg.getOrThrow()
        let serializedPackage = CreateCHIRPackageDirect(builder, Some(chirPackage.GetName()), Some(""),
            UInt8(AccessLevelIndex(chirPackage.GetPackageAccessLevel())), Some(typeKind), Some(allType),
            Some(valueKind), Some(allValue), Some(exprKind), Some(allExpression), Some(defKind),
            Some(allCustomTypeDef), packageInitFunc, ToCHIRPhaseIndex(phase), packageLiteralInitFunc)
        try {
            File.writeTo(filename, builder.Finish(serializedPackage))
        } catch (_: Exception) {
            CJC_ASSERT(false)
        }
    }

    func ConvertToMemoryData(): Array<UInt8> {
        let chirPackage = pkg.getOrThrow()
        let serializedPackage = CreateCHIRPackageDirect(builder, Some(chirPackage.GetName()), Some(""),
            UInt8(AccessLevelIndex(chirPackage.GetPackageAccessLevel())), Some(typeKind), Some(allType),
            Some(valueKind), Some(allValue), Some(exprKind), Some(allExpression), Some(defKind),
            Some(allCustomTypeDef), packageInitFunc, ToCHIRPhaseIndex(ToCHIRPhase.RAW), packageLiteralInitFunc)
        return builder.Finish(serializedPackage)
    }

    func Initialize(): Unit {
        let chirPackage = pkg.getOrThrow()
        for (value in chirPackage.GetGlobalVars()) {
            valueQueue.add(value)
        }
        for (value in chirPackage.GetGlobalFunctions()) {
            valueQueue.add(value)
        }
        for (definition in chirPackage.GetAllCustomTypeDef()) {
            defQueue.add(definition)
        }
        for (definition in defQueue) {
            defCount++
            def2Id[definition.nodeId] = defCount
            allCustomTypeDef.add(0u32)
            defKind.add(0u8)
        }
        for (value in valueQueue) {
            valueCount++
            value2Id[value.nodeId] = valueCount
            allValue.add(0u32)
            valueKind.add(0u8)
        }
    }

    public func SerializePackage(pkg: Package): String {
        return serializePackage(pkg, None)
    }

    public func SerializePackage(pkg: Package, context: CHIRContext): String {
        return serializePackage(pkg, context)
    }

    private func serializePackage(pkg: Package, context: Option<CHIRContext>): String {
        let lines = ArrayList<String>()
        lines.add(CHIR_TEXT_HEADER_V2)
        appendPackage(lines, pkg)
        if (let Some(chirContext) <- context) {
            appendSourceFiles(lines, chirContext)
        }
        appendCustomDefs(lines, "local", pkg.GetStructs(), pkg.GetClasses(), pkg.GetEnums(), pkg.GetExtends())
        appendCustomDefs(lines, "import", pkg.GetImportedStructs(), pkg.GetImportedClasses(), pkg.GetImportedEnums(),
            pkg.GetImportedExtends())
        if (let Some(chirContext) <- context) {
            for (value in chirContext.GetAllocatedValues()) {
                if (let Some(literal) <- (value as LiteralValue)) {
                    Dispatch(lines, literal)
                }
            }
        }
        for (globalVar in pkg.GetGlobalVars()) {
            if (let Some(literal) <- globalVar.GetInitializer()) {
                Dispatch(lines, literal)
            }
        }
        for (globalVar in pkg.GetGlobalVars()) {
            appendGlobalVar(lines, globalVar)
        }
        for (fn in pkg.GetGlobalFunctions(includePureAbstract: true)) {
            appendFunction(lines, fn)
        }
        for (fnBody in pkg.GetGlobalFunctions(includePureAbstract: true)) {
            if (let Some(body) <- fnBody.GetBody()) {
                appendBlockGroup(lines, body)
            }
        }
        return JoinStrings(lines, "\n")
    }

    private func appendSourceFiles(lines: ArrayList<String>, context: CHIRContext): Unit {
        let fileIds = ArrayList<UInt32>()
        let fileNameMap = context.GetFileNameMap()
        for ((fileId, _) in fileNameMap) {
            insertSortedFileId(fileIds, fileId)
        }
        for (fileId in fileIds) {
            let fields = CHIRLineFields("sourceFile")
            fields.add(fileId.toString())
            fields.add(fileNameMap[fileId])
            lines.add(CHIRWireJoinFields(fields))
        }
    }

    private func insertSortedFileId(fileIds: ArrayList<UInt32>, fileId: UInt32): Unit {
        var idx: Int64 = 0
        while (idx < fileIds.size) {
            if (fileIds[idx] == fileId) {
                return
            }
            if (fileId < fileIds[idx]) {
                fileIds.add(fileId, at: idx)
                return
            }
            idx++
        }
        fileIds.add(fileId)
    }

    private func appendPackage(lines: ArrayList<String>, pkg: Package): Unit {
        let fields = CHIRLineFields("package")
        fields.add(pkg.GetName())
        fields.add(AccessLevelIndex(pkg.GetPackageAccessLevel()).toString())
        fields.add(if (let Some(initFn) <- pkg.GetPackageInitFunc()) { CHIRValueId(initFn) } else { "" })
        fields.add(if (let Some(literalInitFn) <- pkg.GetPackageLiteralInitFunc()) {
            CHIRValueId(literalInitFn)
        } else {
            ""
        })
        lines.add(CHIRWireJoinFields(fields))
    }

    private func appendCustomDefs(lines: ArrayList<String>, scope: String, structs: ArrayList<StructDef>,
        classes: ArrayList<ClassDef>, enums: ArrayList<EnumDef>, extends: ArrayList<ExtendDef>): Unit {
        for (def in structs) {
            appendCustomDef(lines, scope, def)
        }
        for (def in classes) {
            appendCustomDef(lines, scope, def)
        }
        for (def in enums) {
            appendCustomDef(lines, scope, def)
        }
        for (def in extends) {
            appendCustomDef(lines, scope, def)
        }
    }

    private func appendCustomDef(lines: ArrayList<String>, scope: String, def: CustomTypeDef): Unit {
        let fields = CHIRLineFields("custom")
        fields.add(CHIRBaseId(def))
        fields.add(CHIRCustomTypeKindName(def))
        fields.add(scope)
        fields.add(def.GetPackageName())
        fields.add(def.GetIdentifier())
        fields.add(serializeGenericParams(def.genericTypeParams))
        fields.add(serializeMemberVars(def.GetDirectInstanceVars()))
        fields.add(serializeFunctionRefs(def.GetMethods()))
        fields.add(serializeEnumCtors(def))
        fields.add(serializeSuperClass(def))
        fields.add(serializeInterfaces(def))
        fields.add(serializeExtends(def.GetExtends()))
        fields.add(serializeExtendedType(def))
        fields.add(CHIRSerializeDebugLocation(def.GetDebugLocation()))
        fields.add(CHIRSerializeAttributes(def))
        fields.add(CHIRSerializeBaseAnnotations(def))
        fields.add(def.GetSrcCodeIdentifier())
        fields.add(CHIRSerializeAnnoInfo(def.GetAnnoInfo()))
        fields.add(serializeGlobalVarRefs(def.GetStaticMemberVars()))
        fields.add(if (let Some(initFn) <- def.GetVarInitializationFunc()) { CHIRValueId(initFn) } else { "" })
        fields.add(if (let Some(genericDecl) <- def.GetGenericDecl()) { CHIRBaseId(genericDecl) } else { "" })
        fields.add(serializeInterfaceTypes(def))
        fields.add(serializeSuperClassType(def))
        fields.add(if (let Some(structDef) <- (def as StructDef)) { CHIRBoolToWire(structDef.IsCStruct()) } else { "" })
        fields.add(if (let Some(enumDef) <- (def as EnumDef)) { CHIRBoolToWire(!enumDef.IsExhaustive()) } else { "" })
        fields.add(SerializeVTable(def.GetDefVTable()))
        fields.add(if (let Some(ty) <- def.GetType()) { CHIRSerializeType(ty) } else { "" })
        lines.add(CHIRWireJoinFields(fields))
    }

    private func Dispatch(lines: ArrayList<String>, literal: LiteralValue): Unit {
        if (serializedLiteralValues.contains(literal.nodeId)) {
            return
        }
        serializedLiteralValues.add(literal.nodeId)
        Serialize(lines, literal)
    }

    private func Serialize(lines: ArrayList<String>, literal: LiteralValue): Unit {
        let fields = CHIRLineFields("literal")
        fields.add(CHIRValueId(literal))
        fields.add(if (let Some(ty) <- literal.GetType()) { CHIRSerializeType(ty) } else { "" })
        fields.add(LiteralKindIndex(literal.literalKind).toString())
        var payload = ""
        if (let Some(boolLit) <- (literal as BoolLiteral)) {
            payload = CHIRBoolToWire(boolLit.GetVal())
        }
        if (let Some(intLit) <- (literal as IntLiteral)) {
            payload = intLit.GetUnsignedVal().toString()
        }
        if (let Some(floatLit) <- (literal as FloatLiteral)) {
            payload = floatLit.GetVal().toString()
        }
        if (let Some(runeLit) <- (literal as RuneLiteral)) {
            payload = runeLit.GetVal().toString()
        }
        if (let Some(stringLit) <- (literal as StringLiteral)) {
            payload = stringLit.GetVal()
        }
        fields.add(payload)
        fields.add(CHIRSerializeDebugLocation(literal.GetDebugLocation()))
        fields.add(CHIRSerializeAttributes(literal))
        fields.add(CHIRSerializeBaseAnnotations(literal))
        lines.add(CHIRWireJoinFields(fields))
    }

    private func appendGlobalVar(lines: ArrayList<String>, globalVar: GlobalVar): Unit {
        let fields = CHIRLineFields("global")
        fields.add(CHIRValueId(globalVar))
        fields.add(globalVar.GetIdentifier())
        fields.add(globalVar.GetSrcCodeIdentifier())
        fields.add(globalVar.GetRawMangledName())
        fields.add(globalVar.GetPackageName())
        fields.add(if (let Some(ty) <- globalVar.GetType()) { CHIRSerializeType(ty) } else { "" })
        fields.add(if (let Some(initValue) <- globalVar.GetInitializerValue()) {
            CHIRValueId(initValue)
        } else if (let Some(initFunc) <- globalVar.GetInitFunc()) {
            CHIRValueId(initFunc)
        } else {
            ""
        })
        fields.add(CHIRWireJoinList(globalVar.GetFeatures()))
        fields.add(if (let Some(parentDef) <- globalVar.GetParentCustomTypeDef()) { CHIRBaseId(parentDef) } else { "" })
        fields.add(CHIRSerializeAnnoInfo(globalVar.GetAnnoInfo()))
        fields.add(CHIRSerializeDebugLocation(globalVar.GetDebugLocation()))
        fields.add(CHIRSerializeAttributes(globalVar))
        fields.add(CHIRSerializeBaseAnnotations(globalVar))
        lines.add(CHIRWireJoinFields(fields))
    }

    private func appendFunction(lines: ArrayList<String>, fn: Function): Unit {
        let fields = CHIRLineFields("function")
        fields.add(CHIRValueId(fn))
        fields.add(fn.GetIdentifier())
        fields.add(fn.GetSrcCodeIdentifier())
        fields.add(fn.GetRawMangledName())
        fields.add(fn.GetPackageName())
        fields.add(FuncKindIndex(fn.GetFuncKind()).toString())
        fields.add(if (let Some(funcTy) <- fn.GetFuncType()) { CHIRSerializeType(funcTy) } else { "" })
        fields.add(serializeParameters(fn.GetParams()))
        fields.add(if (let Some(body) <- fn.GetBody()) { CHIRValueId(body) } else { "" })
        fields.add(if (let Some(ret) <- fn.GetReturnValue()) { CHIRValueId(ret) } else { "" })
        fields.add(if (let Some(parentDef) <- fn.GetParentCustomTypeDef()) { CHIRBaseId(parentDef) } else { "" })
        fields.add(CHIRWireJoinList(fn.GetFeatures()))
        fields.add(if (let Some(genericDecl) <- fn.GetGenericDecl()) { CHIRValueId(genericDecl) } else { "" })
        fields.add(if (let Some(hostFunc) <- fn.GetParamDftValHostFunc()) { CHIRValueId(hostFunc) } else { "" })
        fields.add(CHIRSerializeDebugLocation(fn.GetPropLocation()))
        fields.add(CHIRSerializeAnnoInfo(fn.GetAnnoInfo()))
        fields.add(CHIRSerializeDebugLocation(fn.GetDebugLocation()))
        fields.add(CHIRSerializeAttributes(fn))
        fields.add(CHIRSerializeBaseAnnotations(fn))
        fields.add(if (let Some(rawMethod) <- fn.GetWrappedRawMethod()) {
            if (rawMethod.GetBody().isSome()) { CHIRValueId(rawMethod) } else { "" }
        } else {
            ""
        })
        fields.add(if (let Some(funcTy) <- fn.GetOverrideSrcFuncType()) { CHIRSerializeType(funcTy) } else { "" })
        fields.add(LinkTypeInfo(fn.GetLinkTypeInfo()).ToString())
        fields.add(CHIRBoolToWire(fn.IsCFFIWrapper()))
        lines.add(CHIRWireJoinFields(fields))
    }

    private func appendBlockGroup(lines: ArrayList<String>, group: BlockGroup): Unit {
        if (serializedBlockGroups.contains(group.nodeId)) {
            return
        }
        serializedBlockGroups.add(group.nodeId)
        let fields = CHIRLineFields("blockGroup")
        fields.add(CHIRValueId(group))
        fields.add(group.GetIdentifier())
        fields.add(if (let Some(ownerFn) <- group.GetOwnerFunc()) { CHIRValueId(ownerFn) } else { "" })
        fields.add(if (let Some(ownerExpr) <- group.GetOwnerExpression()) { CHIRBaseId(ownerExpr) } else { "" })
        fields.add(if (let Some(entry) <- group.GetEntryBlock()) { CHIRValueId(entry) } else { "" })
        fields.add(serializeBlockRefs(group.GetBlocks()))
        fields.add(CHIRSerializeDebugLocation(group.GetDebugLocation()))
        fields.add(CHIRSerializeAttributes(group))
        fields.add(CHIRSerializeBaseAnnotations(group))
        lines.add(CHIRWireJoinFields(fields))
        for (block in group.GetBlocks()) {
            appendBlock(lines, group, block)
        }
    }

    private func appendBlock(lines: ArrayList<String>, group: BlockGroup, block: Block): Unit {
        let fields = CHIRLineFields("block")
        fields.add(CHIRValueId(block))
        fields.add(CHIRValueId(group))
        fields.add(block.GetIdentifier())
        fields.add(serializeClassTypes(block.GetExceptions()))
        fields.add(CHIRSerializeDebugLocation(block.GetDebugLocation()))
        fields.add(CHIRSerializeAttributes(block))
        fields.add(serializeBlockRefs(block.GetPredecessors()))
        fields.add(CHIRSerializeBaseAnnotations(block))
        lines.add(CHIRWireJoinFields(fields))
        var index: Int64 = 0
        for (expr in block.GetExpressions()) {
            appendExpression(lines, block, index, expr)
            index++
        }
    }

    private func appendExpression(lines: ArrayList<String>, block: Block, index: Int64, expr: Expression): Unit {
        let fields = CHIRLineFields("expression")
        fields.add(CHIRBaseId(expr))
        fields.add(CHIRValueId(block))
        fields.add(index.toString())
        fields.add(ExprKindIndex(expr.GetExprKind()).toString())
        fields.add(if (let Some(result) <- expr.GetResult()) { CHIRValueId(result) } else { "" })
        fields.add(if (let Some(result) <- expr.GetResult()) { result.GetIdentifier() } else { "" })
        fields.add(if (let Some(resultTy) <- expr.GetResultType()) { CHIRSerializeType(resultTy) } else { "" })
        fields.add(serializeValueRefs(expr.GetOperands()))
        fields.add(serializeBlockRefs(if (let Some(term) <- expr.AsTerminator()) {
            term.GetSuccessors()
        } else {
            ArrayList<Block>()
        }))
        fields.add(serializeLiteral(expr))
        fields.add(CHIRSerializeDebugLocation(expr.GetDebugLocation()))
        fields.add(CHIRSerializeAttributes(expr))
        fields.add(serializeBlockGroupRefs(expr.GetBlockGroups()))
        fields.add(CHIRSerializeBaseAnnotations(expr))
        fields.add(serializeResultSrcCodeIdentifier(expr))
        fields.add(serializeResultIsRetValue(expr))
        fields.add(serializeResultDebugLocation(expr))
        fields.add(serializeResultAttributes(expr))
        fields.add(serializeResultBaseAnnotations(expr))
        fields.add(serializeLambdaParams(expr))
        fields.add(serializeExpressionPayload(expr))
        lines.add(CHIRWireJoinFields(fields))
        for (group in expr.GetBlockGroups()) {
            appendBlockGroup(lines, group)
        }
    }

    private func serializeGenericParams(params: ArrayList<GenericType>): String {
        let out = ArrayList<String>()
        for (param in params) {
            out.add(CHIRSerializeType(param))
        }
        return CHIRWireJoinList(out)
    }

    private func serializeMemberVars(vars: ArrayList<MemberVarInfo>): String {
        let out = ArrayList<String>()
        for (memberVar in vars) {
            let fields = ArrayList<String>()
            fields.add(memberVar.name)
            fields.add(CHIRSerializeType(memberVar.ty))
            fields.add(CHIRBoolToWire(memberVar.isStatic))
            fields.add(CHIRBoolToWire(memberVar.isReadOnly))
            fields.add(memberVar.rawMangledName)
            fields.add(CHIRSerializeAttributeInfo(memberVar.attributeInfo))
            fields.add(CHIRSerializeDebugLocation(memberVar.loc))
            fields.add(CHIRSerializeAnnoInfo(memberVar.annoInfo))
            fields.add(if (let Some(initFn) <- memberVar.initializerFunc) { CHIRValueId(initFn) } else { "" })
            fields.add(if (let Some(outerDef) <- memberVar.outerDef) { CHIRBaseId(outerDef) } else { "" })
            out.add(CHIRWireJoinFields(fields))
        }
        return CHIRWireJoinList(out)
    }

    private func serializeFunctionRefs(values: ArrayList<Function>): String {
        let out = ArrayList<String>()
        for (value in values) {
            out.add(CHIRValueId(value))
        }
        return CHIRWireJoinList(out)
    }

    private func SerializeVTable(vtable: VTableInDef): String {
        let out = ArrayList<String>()
        for (vtableInType in vtable.GetTypeVTables()) {
            let srcParentType = vtableInType.GetSrcParentType() ?? continue
            let fields = ArrayList<String>()
            fields.add(CHIRSerializeType(srcParentType))
            let virtualMethods = ArrayList<String>()
            for (info in vtableInType.GetVirtualMethods()) {
                let methodFields = ArrayList<String>()
                methodFields.add(info.GetMethodName())
                methodFields.add(CHIRSerializeType(info.GetMethodSigType()))
                methodFields.add(CHIRSerializeGenericTypeList(info.GetGenericTypeParams()))
                methodFields.add(if (let Some(fn) <- info.GetVirtualMethod()) { CHIRValueId(fn) } else { "" })
                methodFields.add(CHIRSerializeAttributeInfo(info.GetAttributeInfo()))
                methodFields.add(CHIRSerializeType(info.GetOriginalFuncType()))
                methodFields.add(CHIRSerializeType(info.GetInstParentType()))
                methodFields.add(CHIRSerializeType(info.GetMethodInstRetType()))
                virtualMethods.add(CHIRWireJoinFields(methodFields))
            }
            fields.add(CHIRWireJoinList(virtualMethods))
            out.add(CHIRWireJoinFields(fields))
        }
        return CHIRWireJoinList(out)
    }

    private func serializeGlobalVarRefs(values: ArrayList<GlobalVar>): String {
        let out = ArrayList<String>()
        for (value in values) {
            out.add(CHIRValueId(value))
        }
        return CHIRWireJoinList(out)
    }

    private func serializeBlockRefs(values: ArrayList<Block>): String {
        let out = ArrayList<String>()
        for (value in values) {
            out.add(CHIRValueId(value))
        }
        return CHIRWireJoinList(out)
    }

    private func serializeBlockGroupRefs(values: ArrayList<BlockGroup>): String {
        let out = ArrayList<String>()
        for (value in values) {
            out.add(CHIRValueId(value))
        }
        return CHIRWireJoinList(out)
    }

    private func serializeResultSrcCodeIdentifier(expr: Expression): String {
        if (let Some(result) <- expr.GetResult()) {
            return result.GetSrcCodeIdentifier()
        }
        return ""
    }

    private func serializeResultIsRetValue(expr: Expression): String {
        if (let Some(result) <- expr.GetResult()) {
            return CHIRBoolToWire(result.IsRetValue())
        }
        return ""
    }

    private func serializeResultDebugLocation(expr: Expression): String {
        if (let Some(result) <- expr.GetResult()) {
            return CHIRSerializeDebugLocation(result.GetDebugLocation())
        }
        return ""
    }

    private func serializeResultAttributes(expr: Expression): String {
        if (let Some(result) <- expr.GetResult()) {
            return CHIRSerializeAttributes(result)
        }
        return ""
    }

    private func serializeResultBaseAnnotations(expr: Expression): String {
        if (let Some(result) <- expr.GetResult()) {
            return CHIRSerializeBaseAnnotations(result)
        }
        return ""
    }

    private func serializeLambdaParams(expr: Expression): String {
        if (let Some(lambdaExpr) <- (expr as Lambda)) {
            return serializeParameterRecords(lambdaExpr.GetParams())
        }
        return ""
    }

    private func serializeValueRefs(values: ArrayList<Value>): String {
        let out = ArrayList<String>()
        for (value in values) {
            out.add(CHIRValueId(value))
        }
        return CHIRWireJoinList(out)
    }

    private func serializeClassTypes(types: ArrayList<ClassType>): String {
        let out = ArrayList<String>()
        for (ty in types) {
            out.add(CHIRSerializeType(ty))
        }
        return CHIRWireJoinList(out)
    }

    private func serializeEnumCtors(def: CustomTypeDef): String {
        let out = ArrayList<String>()
        if (let Some(enumDef) <- (def as EnumDef)) {
            for (ctor in enumDef.GetCtors()) {
                let fields = ArrayList<String>()
                fields.add(ctor.name)
                let payloadTypes = ArrayList<String>()
                for (payloadTy in ctor.payloadTypes) {
                    payloadTypes.add(CHIRSerializeType(payloadTy))
                }
                fields.add(CHIRWireJoinList(payloadTypes))
                out.add(CHIRWireJoinFields(fields))
            }
        }
        return CHIRWireJoinList(out)
    }

    private func serializeSuperClass(def: CustomTypeDef): String {
        if (let Some(classDef) <- (def as ClassDef)) {
            if (let Some(superDef) <- classDef.GetSuperClassDef()) {
                return CHIRBaseId(superDef)
            }
        }
        return ""
    }

    private func serializeInterfaces(def: CustomTypeDef): String {
        let out = ArrayList<String>()
        if (let Some(classDef) <- (def as ClassDef)) {
            for (interfaceDef in classDef.GetImplementedInterfaceDefs()) {
                out.add(CHIRBaseId(interfaceDef))
            }
        }
        return CHIRWireJoinList(out)
    }

    private func serializeInterfaceTypes(def: CustomTypeDef): String {
        let out = ArrayList<String>()
        for (interfaceTy in def.GetImplementedInterfaceTys()) {
            out.add(CHIRSerializeType(interfaceTy))
        }
        return CHIRWireJoinList(out)
    }

    private func serializeSuperClassType(def: CustomTypeDef): String {
        if (let Some(classDef) <- (def as ClassDef)) {
            if (let Some(superTy) <- classDef.GetSuperClassTy()) {
                return CHIRSerializeType(superTy)
            }
        }
        return ""
    }

    private func serializeExtends(extends: ArrayList<ExtendDef>): String {
        let out = ArrayList<String>()
        for (extendDef in extends) {
            out.add(CHIRBaseId(extendDef))
        }
        return CHIRWireJoinList(out)
    }

    private func serializeExtendedType(def: CustomTypeDef): String {
        if (let Some(extendDef) <- (def as ExtendDef)) {
            if (let Some(extendedTy) <- extendDef.extendedType) {
                return CHIRSerializeType(extendedTy)
            }
        }
        return ""
    }

    private func serializeParameters(params: ArrayList<Parameter>): String {
        return serializeParameterRecords(params)
    }

    private func serializeParameterRecords(params: ArrayList<Parameter>): String {
        let out = ArrayList<String>()
        for (param in params) {
            out.add(serializeParameterRecord(param))
        }
        return CHIRWireJoinList(out)
    }

    private func serializeParameterRecord(param: Parameter): String {
        let fields = ArrayList<String>()
        fields.add(CHIRValueId(param))
        fields.add(param.GetIdentifier())
        fields.add(param.GetSrcCodeIdentifier())
        fields.add(if (let Some(ty) <- param.GetType()) { CHIRSerializeType(ty) } else { "" })
        fields.add(CHIRSerializeAnnoInfo(param.GetAnnoInfo()))
        fields.add(CHIRSerializeDebugLocation(param.GetDebugLocation()))
        fields.add(CHIRSerializeAttributes(param))
        fields.add(CHIRSerializeBaseAnnotations(param))
        return CHIRWireJoinFields(fields)
    }

    private func serializeLiteral(expr: Expression): String {
        if (let Some(constant) <- (expr as Constant)) {
            let fields = ArrayList<String>()
            let literal = constant.literal
            fields.add(LiteralKindIndex(literal.literalKind).toString())
            if (let Some(boolLit) <- (literal as BoolLiteral)) {
                fields.add(CHIRBoolToWire(boolLit.GetVal()))
            } else if (let Some(intLit) <- (literal as IntLiteral)) {
                fields.add(intLit.GetUnsignedVal().toString())
            } else if (let Some(floatLit) <- (literal as FloatLiteral)) {
                fields.add(floatLit.GetVal().toString())
            } else if (let Some(runeLit) <- (literal as RuneLiteral)) {
                fields.add(runeLit.GetVal().toString())
            } else if (let Some(stringLit) <- (literal as StringLiteral)) {
                fields.add(stringLit.GetVal())
            } else {
                fields.add("")
            }
            return CHIRWireJoinFields(fields)
        }
        return ""
    }

    private func serializeExpressionPayload(expr: Expression): String {
        if (let Some(branch) <- (expr as Branch)) {
            return expressionPayload("branch", [SourceExprIndex(branch.GetSourceExpr()).toString()])
        }
        if (let Some(multiBranch) <- (expr as MultiBranch)) {
            return expressionPayload("multiBranch", [CHIRSerializeUInt64List(multiBranch.GetCaseVals())])
        }
        if (let Some(intOp) <- (expr as IntOpWithException)) {
            return expressionPayload("intOpWithException", [ExprKindIndex(intOp.GetOpKind()).toString()])
        }
        if (let Some(allocateWithException) <- (expr as AllocateWithException)) {
            return expressionPayload("allocate", [CHIRSerializeType(allocateWithException.GetType())])
        }
        if (let Some(allocate) <- (expr as Allocate)) {
            return expressionPayload("allocate", [CHIRSerializeType(allocate.GetType())])
        }
        if (let Some(getElementRef) <- (expr as GetElementRef)) {
            return expressionPayload("indexPath", [CHIRSerializeUInt64List(getElementRef.GetPath())])
        }
        if (let Some(getElementByName) <- (expr as GetElementByName)) {
            return expressionPayload("namePath", [CHIRWireJoinList(getElementByName.GetNames())])
        }
        if (let Some(storeElementRef) <- (expr as StoreElementRef)) {
            return expressionPayload("indexPath", [CHIRSerializeUInt64List(storeElementRef.GetPath())])
        }
        if (let Some(storeElementByName) <- (expr as StoreElementByName)) {
            return expressionPayload("namePath", [CHIRWireJoinList(storeElementByName.GetNames())])
        }
        if (let Some(applyWithException) <- (expr as ApplyWithException)) {
            return serializeFuncCallPayload("apply", applyWithException.GetInstantiatedTypeArgs(),
                applyWithException.GetThisType(), false)
        }
        if (let Some(apply) <- (expr as Apply)) {
            return serializeFuncCallPayload("apply", apply.GetInstantiatedTypeArgs(), apply.GetThisType(),
                apply.IsSuperCall())
        }
        if (let Some(invokeStaticWithException) <- (expr as InvokeStaticWithException)) {
            return serializeInvokePayload(invokeStaticWithException.GetInstantiatedTypeArgs(),
                invokeStaticWithException.GetThisType(), invokeStaticWithException.GetMethodName(),
                invokeStaticWithException.GetMethodType(), invokeStaticWithException.GetGenericTypeParams(),
                invokeStaticWithException.GetVirtualMethodOffset())
        }
        if (let Some(invokeWithException) <- (expr as InvokeWithException)) {
            return serializeInvokePayload(invokeWithException.GetInstantiatedTypeArgs(),
                invokeWithException.GetThisType(), invokeWithException.GetMethodName(),
                invokeWithException.GetMethodType(), invokeWithException.GetGenericTypeParams(),
                invokeWithException.GetVirtualMethodOffset())
        }
        if (let Some(invokeStatic) <- (expr as InvokeStatic)) {
            return serializeInvokePayload(invokeStatic.GetInstantiatedTypeArgs(), invokeStatic.GetThisType(),
                invokeStatic.GetMethodName(), invokeStatic.GetMethodType(), invokeStatic.GetGenericTypeParams(),
                invokeStatic.GetVirtualMethodOffset())
        }
        if (let Some(invoke) <- (expr as Invoke)) {
            return serializeInvokePayload(invoke.GetInstantiatedTypeArgs(), invoke.GetThisType(),
                invoke.GetMethodName(), invoke.GetMethodType(), invoke.GetGenericTypeParams(),
                invoke.GetVirtualMethodOffset())
        }
        if (let Some(instanceOf) <- (expr as InstanceOf)) {
            return expressionPayload("instanceOf", [CHIRSerializeType(instanceOf.GetType())])
        }
        if (let Some(getInstantiateValue) <- (expr as GetInstantiateValue)) {
            return expressionPayload("instantiate", [CHIRSerializeTypeList(getInstantiateValue.GetInstantiateTypes())])
        }
        if (let Some(getRTTIStatic) <- (expr as GetRTTIStatic)) {
            return expressionPayload("rttiStatic", [CHIRSerializeType(getRTTIStatic.GetRTTIType())])
        }
        if (let Some(field) <- (expr as Field)) {
            return expressionPayload("indexPath", [CHIRSerializeUInt64List(field.GetPath())])
        }
        if (let Some(fieldByName) <- (expr as FieldByName)) {
            return expressionPayload("namePath", [CHIRWireJoinList(fieldByName.GetNames())])
        }
        if (let Some(rawArrayAllocateWithException) <- (expr as RawArrayAllocateWithException)) {
            return expressionPayload("rawArrayAllocate", [CHIRSerializeType(rawArrayAllocateWithException.GetElementType())])
        }
        if (let Some(rawArrayAllocate) <- (expr as RawArrayAllocate)) {
            return expressionPayload("rawArrayAllocate", [CHIRSerializeType(rawArrayAllocate.GetElementType())])
        }
        if (let Some(intrinsicWithException) <- (expr as IntrinsicWithException)) {
            return expressionPayload("intrinsic", [IntrinsicKindName(intrinsicWithException.GetIntrinsicKind()),
                CHIRSerializeTypeList(intrinsicWithException.GetInstantiatedTypeArgs())])
        }
        if (let Some(intrinsic) <- (expr as Intrinsic)) {
            return expressionPayload("intrinsic", [IntrinsicKindName(intrinsic.GetIntrinsicKind()),
                CHIRSerializeTypeList(intrinsic.GetInstantiatedTypeArgs())])
        }
        if (let Some(debugExpr) <- (expr as Debug)) {
            return expressionPayload("debug", [debugExpr.GetSrcCodeIdentifier()])
        }
        if (let Some(spawnWithException) <- (expr as SpawnWithException)) {
            return expressionPayload("spawn", [if (let Some(fn) <- spawnWithException.GetExecuteClosure()) {
                CHIRValueId(fn)
            } else {
                ""
            }])
        }
        if (let Some(spawnExpr) <- (expr as Spawn)) {
            return expressionPayload("spawn", [if (let Some(fn) <- spawnExpr.GetExecuteClosure()) {
                CHIRValueId(fn)
            } else {
                ""
            }])
        }
        if (let Some(lambdaExpr) <- (expr as Lambda)) {
            return serializeLambdaPayload(lambdaExpr)
        }
        return ""
    }

    private func serializeFuncCallPayload(tag: String, instTypeArgs: ArrayList<Type>, thisType: Option<Type>,
        isSuperCall: Bool): String {
        let fields = ArrayList<String>()
        fields.add(CHIRSerializeTypeList(instTypeArgs))
        fields.add(if (let Some(ty) <- thisType) { CHIRSerializeType(ty) } else { "" })
        fields.add(CHIRBoolToWire(isSuperCall))
        return expressionPayload(tag, fields)
    }

    private func serializeInvokePayload(instTypeArgs: ArrayList<Type>, thisType: Option<Type>, methodName: String,
        methodType: FuncType, genericTypeParams: ArrayList<GenericType>, virtualMethodOffset: Option<UInt64>): String {
        let fields = ArrayList<String>()
        fields.add(CHIRSerializeTypeList(instTypeArgs))
        fields.add(if (let Some(ty) <- thisType) { CHIRSerializeType(ty) } else { "" })
        fields.add(methodName)
        fields.add(CHIRSerializeType(methodType))
        fields.add(CHIRSerializeGenericTypeList(genericTypeParams))
        fields.add(if (let Some(offset) <- virtualMethodOffset) { offset.toString() } else { "" })
        return expressionPayload("invoke", fields)
    }

    private func serializeLambdaPayload(lambdaExpr: Lambda): String {
        let fields = ArrayList<String>()
        fields.add(if (let Some(funcTy) <- lambdaExpr.GetFuncType()) { CHIRSerializeType(funcTy) } else { "" })
        fields.add(CHIRBoolToWire(lambdaExpr.IsLocalFunc()))
        fields.add(lambdaExpr.GetIdentifier())
        fields.add(lambdaExpr.GetSrcCodeIdentifier())
        fields.add(CHIRSerializeGenericTypeList(lambdaExpr.GetGenericTypeParams()))
        fields.add(if (let Some(retValue) <- lambdaExpr.GetReturnValue()) { CHIRValueId(retValue) } else { "" })
        fields.add(CHIRBoolToWire(lambdaExpr.IsCompileTimeValue()))
        fields.add(if (let Some(hostFunc) <- lambdaExpr.GetParamDftValHostFunc()) {
            CHIRBaseId(hostFunc)
        } else {
            ""
        })
        return expressionPayload("lambda", fields)
    }

    private func expressionPayload(tag: String, values: ArrayList<String>): String {
        let fields = CHIRLineFields(tag)
        for (value in values) {
            fields.add(value)
        }
        return CHIRWireJoinFields(fields)
    }

    private func expressionPayload(tag: String, values: Array<String>): String {
        let fields = CHIRLineFields(tag)
        for (value in values) {
            fields.add(value)
        }
        return CHIRWireJoinFields(fields)
    }
}
