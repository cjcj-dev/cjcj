package cangjie_compiler::basic

import std.collection.*

private const FAITHFUL_UNORDERED_MAP_EMPTY: Int64 = -1
private const FAITHFUL_UNORDERED_MAP_BEFORE_BEGIN: Int64 = -2

private let FAITHFUL_PRIME_REHASH_BUCKETS: Array<Int64> = [
    1, 2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71, 73, 79, 83,
    89, 97, 103, 109, 113, 127, 137, 139, 149, 157, 167, 179, 193, 199, 211, 227, 241, 257, 277,
    293, 313, 337, 359, 383, 409, 439, 467, 503, 541, 577, 619, 661, 709, 761, 823, 887, 953,
    1031, 1109, 1193, 1289, 1381, 1493, 1613, 1741, 1879, 2029, 2179, 2357, 2549, 2753, 2971,
    3209, 3469, 3739, 4027, 4349, 4703, 5087, 5503, 5953, 6427, 6949, 7517, 8123, 8783, 9497,
    10273, 11113, 12011, 12983, 14033, 15173, 16411, 17749, 19183, 20753, 22447, 24281, 26267,
    28411, 30727, 33223, 35933, 38873, 42043, 45481, 49201, 53201, 57557, 62233, 67307, 72817,
    78779, 85229, 92203, 99733, 107897, 116731, 126271, 136607, 147793, 159871, 172933, 187091,
    202409, 218971, 236897, 256279, 277261, 299951, 324503, 351061, 379787, 410857, 444487,
    480881, 520241, 562841, 608903, 658753, 712697, 771049, 834181, 902483, 976369, 1056323,
    1142821, 1236397, 1337629, 1447153, 1565659, 1693859, 1832561, 1982627, 2144977, 2320627,
    2510653, 2716249, 2938679, 3179303, 3439651, 3721303, 4026031, 4355707, 4712381, 5098259,
    5515729, 5967347, 6456007, 6984629, 7556579, 8175383, 8844859, 9569143, 10352717
]

private class FaithfulUnorderedMapNode<V> {
    public let key: String
    public var value: V
    public let hash: UInt64
    public var next: Int64

    public init(key: String, value: V, hash: UInt64, next: Int64) {
        this.key = key
        this.value = value
        this.hash = hash
        this.next = next
    }
}

public class FaithfulUnorderedMap<V> {
    private var buckets: ArrayList<Int64> = FaithfulUnorderedMap<V>.MAllocateBuckets(1)
    private let nodes: ArrayList<FaithfulUnorderedMapNode<V>> = ArrayList<FaithfulUnorderedMapNode<V>>()
    private var beforeBeginNext: Int64 = FAITHFUL_UNORDERED_MAP_EMPTY
    private var bucketCount: Int64 = 1
    private var elementCount: Int64 = 0
    private var nextResize: Int64 = 0

    public init() {}

    public prop size: Int64 {
        get() {
            elementCount
        }
    }

    public func add(key: String, value: V): Unit {
        InsertOrAssign(key, value)
    }

    public func Set(key: String, value: V): Unit {
        InsertOrAssign(key, value)
    }

    public func get(key: String): Option<V> {
        if (let Some(nodeIndex) <- MFindNodeIndex(key)) {
            return Some(nodes[nodeIndex].value)
        }
        return None
    }

    public func contains(key: String): Bool {
        return MFindNodeIndex(key).isSome()
    }

    public func remove(key: String): Unit {
        if (MErase(key)) {
            elementCount--
        }
    }

    public func clear(): Unit {
        buckets = FaithfulUnorderedMap<V>.MAllocateBuckets(bucketCount)
        nodes.clear()
        beforeBeginNext = FAITHFUL_UNORDERED_MAP_EMPTY
        elementCount = 0
    }

    public func keys(): ArrayList<String> {
        let out = ArrayList<String>()
        var nodeIndex = beforeBeginNext
        while (nodeIndex != FAITHFUL_UNORDERED_MAP_EMPTY) {
            let node = nodes[nodeIndex]
            out.add(node.key)
            nodeIndex = node.next
        }
        return out
    }

    public func values(): ArrayList<V> {
        let out = ArrayList<V>()
        var nodeIndex = beforeBeginNext
        while (nodeIndex != FAITHFUL_UNORDERED_MAP_EMPTY) {
            let node = nodes[nodeIndex]
            out.add(node.value)
            nodeIndex = node.next
        }
        return out
    }

    public func BucketCount(): Int64 {
        return bucketCount
    }

    private func InsertOrAssign(key: String, value: V): Unit {
        if (let Some(nodeIndex) <- MFindNodeIndex(key)) {
            nodes[nodeIndex].value = value
            return
        }
        let hash = GetHash(key)
        let newBucketCount = MNeedRehash()
        if (newBucketCount > 0) {
            MRehash(newBucketCount)
        }
        let bucketIndex = MBucketIndex(hash, bucketCount)
        let nodeIndex = nodes.size
        nodes.add(FaithfulUnorderedMapNode<V>(key, value, hash, FAITHFUL_UNORDERED_MAP_EMPTY))
        MInsertBucketBegin(bucketIndex, nodeIndex)
        elementCount++
    }

    private func MNeedRehash(): Int64 {
        let pendingCount = elementCount + 1
        if (pendingCount <= nextResize) {
            return 0
        }
        let minBuckets = if (nextResize == 0) {
            if (pendingCount > 11) {
                pendingCount
            } else {
                11
            }
        } else {
            pendingCount
        }
        if (minBuckets >= bucketCount) {
            let floorMinBucketsPlusOne = minBuckets + 1
            let doubledBucketCount = bucketCount * 2
            let target = if (floorMinBucketsPlusOne > doubledBucketCount) {
                floorMinBucketsPlusOne
            } else {
                doubledBucketCount
            }
            let nextBucketCount = MNextBkt(target)
            nextResize = nextBucketCount
            return nextBucketCount
        }
        nextResize = bucketCount
        return 0
    }

    private static func MNextBkt(n: Int64): Int64 {
        for (bucket in FAITHFUL_PRIME_REHASH_BUCKETS) {
            if (bucket >= n) {
                return bucket
            }
        }
        throw IllegalStateException("faithful _Prime_rehash_policy bucket table exhausted")
    }

    private func MFindNodeIndex(key: String): Option<Int64> {
        let hash = GetHash(key)
        let bucketIndex = MBucketIndex(hash, bucketCount)
        let beforeNode = buckets[bucketIndex]
        if (beforeNode == FAITHFUL_UNORDERED_MAP_EMPTY) {
            return None
        }
        var nodeIndex = MNextOfBefore(beforeNode)
        while (nodeIndex != FAITHFUL_UNORDERED_MAP_EMPTY) {
            let node = nodes[nodeIndex]
            if (MBucketIndex(node.hash, bucketCount) != bucketIndex) {
                return None
            }
            if (node.hash == hash && node.key == key) {
                return Some(nodeIndex)
            }
            nodeIndex = node.next
        }
        return None
    }

    private func MErase(key: String): Bool {
        let hash = GetHash(key)
        var previous = FAITHFUL_UNORDERED_MAP_BEFORE_BEGIN
        var nodeIndex = beforeBeginNext
        while (nodeIndex != FAITHFUL_UNORDERED_MAP_EMPTY) {
            let node = nodes[nodeIndex]
            if (node.hash == hash && node.key == key) {
                MSetNextOfBefore(previous, node.next)
                node.next = FAITHFUL_UNORDERED_MAP_EMPTY
                MRebuildBuckets()
                return true
            }
            previous = nodeIndex
            nodeIndex = node.next
        }
        return false
    }

    private func MInsertBucketBegin(bucketIndex: Int64, nodeIndex: Int64): Unit {
        let beforeNode = buckets[bucketIndex]
        if (beforeNode != FAITHFUL_UNORDERED_MAP_EMPTY) {
            nodes[nodeIndex].next = MNextOfBefore(beforeNode)
            MSetNextOfBefore(beforeNode, nodeIndex)
            return
        }
        nodes[nodeIndex].next = beforeBeginNext
        beforeBeginNext = nodeIndex
        if (nodes[nodeIndex].next != FAITHFUL_UNORDERED_MAP_EMPTY) {
            let nextBucketIndex = MBucketIndex(nodes[nodes[nodeIndex].next].hash, bucketCount)
            buckets[nextBucketIndex] = nodeIndex
        }
        buckets[bucketIndex] = FAITHFUL_UNORDERED_MAP_BEFORE_BEGIN
    }

    private func MRehash(newBucketCount: Int64): Unit {
        let oldBegin = beforeBeginNext
        let newBuckets = FaithfulUnorderedMap<V>.MAllocateBuckets(newBucketCount)
        beforeBeginNext = FAITHFUL_UNORDERED_MAP_EMPTY
        var beforeBeginBucket = 0
        var nodeIndex = oldBegin
        while (nodeIndex != FAITHFUL_UNORDERED_MAP_EMPTY) {
            let nextNode = nodes[nodeIndex].next
            let bucketIndex = MBucketIndex(nodes[nodeIndex].hash, newBucketCount)
            if (newBuckets[bucketIndex] == FAITHFUL_UNORDERED_MAP_EMPTY) {
                nodes[nodeIndex].next = beforeBeginNext
                beforeBeginNext = nodeIndex
                newBuckets[bucketIndex] = FAITHFUL_UNORDERED_MAP_BEFORE_BEGIN
                if (nodes[nodeIndex].next != FAITHFUL_UNORDERED_MAP_EMPTY) {
                    newBuckets[beforeBeginBucket] = nodeIndex
                }
                beforeBeginBucket = bucketIndex
            } else {
                let beforeNode = newBuckets[bucketIndex]
                nodes[nodeIndex].next = MNextOfBeforeWithBuckets(beforeNode, beforeBeginNext)
                if (beforeNode == FAITHFUL_UNORDERED_MAP_BEFORE_BEGIN) {
                    beforeBeginNext = nodeIndex
                } else {
                    nodes[beforeNode].next = nodeIndex
                }
            }
            nodeIndex = nextNode
        }
        buckets = newBuckets
        bucketCount = newBucketCount
    }

    private func MRebuildBuckets(): Unit {
        let rebuiltBuckets = FaithfulUnorderedMap<V>.MAllocateBuckets(bucketCount)
        var previous = FAITHFUL_UNORDERED_MAP_BEFORE_BEGIN
        var nodeIndex = beforeBeginNext
        while (nodeIndex != FAITHFUL_UNORDERED_MAP_EMPTY) {
            let bucketIndex = MBucketIndex(nodes[nodeIndex].hash, bucketCount)
            if (rebuiltBuckets[bucketIndex] == FAITHFUL_UNORDERED_MAP_EMPTY) {
                rebuiltBuckets[bucketIndex] = previous
            }
            previous = nodeIndex
            nodeIndex = nodes[nodeIndex].next
        }
        buckets = rebuiltBuckets
    }

    private func MNextOfBefore(beforeNode: Int64): Int64 {
        if (beforeNode == FAITHFUL_UNORDERED_MAP_BEFORE_BEGIN) {
            return beforeBeginNext
        }
        return nodes[beforeNode].next
    }

    private func MSetNextOfBefore(beforeNode: Int64, nextNode: Int64): Unit {
        if (beforeNode == FAITHFUL_UNORDERED_MAP_BEFORE_BEGIN) {
            beforeBeginNext = nextNode
            return
        }
        nodes[beforeNode].next = nextNode
    }

    private func MNextOfBeforeWithBuckets(beforeNode: Int64, firstNode: Int64): Int64 {
        if (beforeNode == FAITHFUL_UNORDERED_MAP_BEFORE_BEGIN) {
            return firstNode
        }
        return nodes[beforeNode].next
    }

    private static func MAllocateBuckets(count: Int64): ArrayList<Int64> {
        let out = ArrayList<Int64>()
        var index = 0
        while (index < count) {
            out.add(FAITHFUL_UNORDERED_MAP_EMPTY)
            index++
        }
        return out
    }

    private static func MBucketIndex(hash: UInt64, count: Int64): Int64 {
        return Int64(hash % UInt64(count))
    }
}
