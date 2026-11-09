package im.zuno.chat.zuno_http

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test

private class CountedCall : NativeCall {
    var cancels = 0

    override fun cancel() {
        cancels++
    }
}

class CallTableTest {
    @Test
    fun `a call added after detach is cancelled and never kept`() {
        val table = CallTable<CountedCall>()
        table.detach()
        val late = CountedCall()

        table.replace(1, late)

        assertEquals(1, late.cancels)
        assertNull(table[1])
    }

    @Test
    fun `detach cancels every call it holds`() {
        val table = CallTable<CountedCall>()
        val first = CountedCall()
        val second = CountedCall()
        table.replace(1, first)
        table.replace(2, second)

        table.detach()

        assertEquals(listOf(1, 1), listOf(first.cancels, second.cancels))
        assertNull(table[1])
    }

    @Test
    fun `a call with a reused id cancels the old one`() {
        val table = CallTable<CountedCall>()
        val old = CountedCall()
        val new = CountedCall()
        table.replace(1, old)

        table.replace(1, new)

        assertEquals(1, old.cancels)
        assertEquals(0, new.cancels)
        assertSame(new, table[1])
    }

    @Test
    fun `the old call ending leaves the new call with its id in place`() {
        val table = CallTable<CountedCall>()
        val old = CountedCall()
        val new = CountedCall()
        table.replace(1, old)
        table.replace(1, new)

        table.remove(1, old)

        assertSame(new, table[1])
    }
}
