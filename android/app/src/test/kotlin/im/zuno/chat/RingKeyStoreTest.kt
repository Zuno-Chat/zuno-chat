package im.zuno.chat

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RingKeyStoreTest {
    private class MemoryVault : RingKeyVault {
        var stored: ByteArray? = null
        var failing = false
        var refusing = false
        var undeletable = false
        var deletes = 0

        override fun read(): RingVaultRead {
            val bytes = stored ?: return RingVaultRead.Missing
            return if (failing) RingVaultRead.Failed else RingVaultRead.Found(bytes)
        }

        override fun write(bytes: ByteArray): Boolean {
            if (refusing) return false
            stored = bytes
            failing = false
            return true
        }

        override fun delete(): Boolean {
            deletes++
            if (undeletable) return false
            stored = null
            failing = false
            return true
        }
    }

    private val vault = MemoryVault()

    private fun store(vararg kids: Long): RingKeyStore {
        val queue = ArrayDeque(kids.toList())
        var keyByte = 0
        return RingKeyStore(
            vault,
            newKid = { queue.removeFirst() },
            newKey = { ByteArray(32) { (++keyByte).toByte() } },
        )
    }

    private fun unreadable(vararg kids: Long): RingKeyStore {
        val keys = store(1, *kids)
        keys.current()
        vault.failing = true
        return keys
    }

    private fun ready(read: RingKeysRead): RingKeys = (read as RingKeysRead.Ready).keys

    @Test
    fun `the first read creates a key and keeps it`() {
        val keys = ready(store(7).current())

        assertEquals(7L, keys.kid)
        assertEquals(32, keys.key.size)
        assertNotNull(vault.stored)
        assertArrayEquals(keys.key, ready(store().load()).key)
    }

    @Test
    fun `the default key is 32 random bytes under a random kid`() {
        val first = ready(RingKeyStore(MemoryVault()).current())
        val second = ready(RingKeyStore(MemoryVault()).current())

        assertEquals(32, first.key.size)
        assertTrue(first.kid in 1L..0xFFFF_FFFFL)
        assertTrue(!first.key.contentEquals(second.key))
    }

    @Test
    fun `a zero kid is never used`() {
        assertEquals(9L, ready(store(0, 0, 9).current()).kid)
    }

    @Test
    fun `rotation keeps the previous key until the new one is acknowledged`() {
        val keys = store(1, 1, 2)
        val first = ready(keys.current())

        val rotated = keys.rotate()!!

        assertEquals(2L, rotated.kid)
        assertEquals(1L, rotated.prevKid)
        assertArrayEquals(first.key, rotated.prevKey)
        assertNull(rotated.prevUntilMs)
        assertArrayEquals(first.key, rotated.keyFor(1, Long.MAX_VALUE - 1))
        assertArrayEquals(rotated.key, ready(keys.load()).keyFor(2, 0))
    }

    @Test
    fun `an acknowledgement gives the previous key twenty-four more hours`() {
        val keys = store(1, 2)
        keys.current()
        keys.rotate()

        val acknowledged = keys.acknowledge(kid = 2, nowMs = 1_000)!!

        assertEquals(1_000 + 86_400_000L, acknowledged.prevUntilMs)
        assertNotNull(acknowledged.keyFor(1, 86_400_999))
        assertNull(acknowledged.keyFor(1, 86_401_000))
        assertEquals(acknowledged.prevUntilMs, ready(keys.load()).prevUntilMs)
    }

    @Test
    fun `acknowledging again never extends the grace`() {
        val keys = store(1, 2)
        keys.current()
        keys.rotate()
        keys.acknowledge(kid = 2, nowMs = 1_000)

        val again = keys.acknowledge(kid = 2, nowMs = 50_000)!!

        assertEquals(1_000 + 86_400_000L, again.prevUntilMs)
    }

    @Test
    fun `an acknowledgement for another kid changes nothing`() {
        val keys = store(1, 2)
        keys.current()
        keys.rotate()

        assertNull(keys.acknowledge(kid = 1, nowMs = 1_000))
        assertNull(ready(keys.load()).prevUntilMs)
    }

    @Test
    fun `acknowledging a key that never rotated keeps it as it is`() {
        val keys = store(5)
        keys.current()

        val acknowledged = keys.acknowledge(kid = 5, nowMs = 1_000)!!

        assertNull(acknowledged.prevKid)
        assertNull(acknowledged.prevUntilMs)
    }

    @Test
    fun `an unknown kid has no key`() {
        val keys = store(1, 2)
        keys.current()

        assertNull(keys.rotate()!!.keyFor(6, 0))
    }

    @Test
    fun `a second rotation drops the oldest key`() {
        val keys = store(1, 2, 3)
        keys.current()
        keys.rotate()

        val rotated = keys.rotate()!!

        assertEquals(2L, rotated.prevKid)
        assertNull(rotated.keyFor(1, 0))
    }

    @Test
    fun `an unreadable key during a push stays unavailable and is not deleted`() {
        val keys = unreadable()
        val kept = vault.stored

        assertEquals(RingKeysRead.Unavailable, keys.load())
        assertNull(keys.acknowledge(kid = 1, nowMs = 0))
        assertTrue(kept.contentEquals(vault.stored))
        assertEquals(0, vault.deletes)
    }

    @Test
    fun `an unreadable key is replaced by a fresh one when the app asks for the current key`() {
        val keys = unreadable(2)

        assertEquals(2L, ready(keys.current()).kid)
        assertEquals(1, vault.deletes)
        assertEquals(2L, ready(keys.load()).kid)
    }

    @Test
    fun `rotating an unreadable key starts from a fresh one`() {
        val keys = unreadable(2, 3)

        val rotated = keys.rotate()!!

        assertEquals(3L, rotated.kid)
        assertEquals(2L, rotated.prevKid)
    }

    @Test
    fun `a replacement goes ahead even when the old key will not delete`() {
        val keys = unreadable(2)
        vault.undeletable = true

        assertEquals(2L, ready(keys.current()).kid)
        assertEquals(2L, ready(keys.load()).kid)
    }

    @Test
    fun `a replacement whose write fails is unavailable`() {
        val keys = unreadable(2, 3)
        vault.refusing = true

        assertEquals(RingKeysRead.Unavailable, keys.current())
        assertNull(keys.rotate())
    }

    @Test
    fun `an unreadable record is unavailable to a push and replaced when the app asks`() {
        vault.stored = "garbage".toByteArray()
        val keys = store(4)

        assertEquals(RingKeysRead.Unavailable, keys.load())
        assertEquals(4L, ready(keys.current()).kid)
    }

    @Test
    fun `a record whose key is not 32 bytes is unreadable`() {
        vault.stored = "{\"kid\":3,\"key\":\"AAEC\"}".toByteArray()

        assertEquals(RingKeysRead.Unavailable, store().load())
    }

    @Test
    fun `a key the vault refuses to keep is unavailable`() {
        vault.refusing = true

        assertEquals(RingKeysRead.Unavailable, store(1).current())
        assertNull(vault.stored)
    }

    @Test
    fun `deleting the key means the next read makes a new one`() {
        val keys = store(5, 6)
        keys.current()

        assertTrue(keys.delete())

        assertEquals(RingKeysRead.Missing, keys.load())
        assertEquals(6L, ready(keys.current()).kid)
    }

    @Test
    fun `a kid above the signed range survives storage`() {
        val keys = store(0xFFFF_FFFFL, 0x8000_0000L)
        keys.current()
        keys.rotate()

        val read = ready(store().load())

        assertEquals(0x8000_0000L, read.kid)
        assertEquals(0xFFFF_FFFFL, read.prevKid)
    }
}
