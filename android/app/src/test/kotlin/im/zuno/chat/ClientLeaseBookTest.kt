package im.zuno.chat

import im.zuno.chat.zuno_notifications.ClientLeaseAction.Deny
import im.zuno.chat.zuno_notifications.ClientLeaseAction.Grant
import im.zuno.chat.zuno_notifications.ClientLeaseAction.Yield
import im.zuno.chat.zuno_notifications.ClientLeaseBook
import im.zuno.chat.zuno_notifications.ClientLeaseKind.APP
import im.zuno.chat.zuno_notifications.ClientLeaseKind.BACKGROUND
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ClientLeaseBookTest {
    private val book = ClientLeaseBook()

    private val app = 1L
    private val push = 2L
    private val action = 3L
    private val secondApp = 4L

    private fun token(actions: List<Any>, request: Long): String =
        actions.filterIsInstance<Grant>().single { it.request == request }.token

    @Test
    fun `a free store is granted at once`() {
        val actions = book.acquire(request = 1, engine = push, kind = BACKGROUND)

        assertEquals(1, actions.size)
        assertFalse((actions.single() as Grant).forced)
        assertFalse(book.isWaiting(1))
    }

    @Test
    fun `an engine that already holds a lease is granted again at once`() {
        val first = token(book.acquire(request = 1, engine = app, kind = APP), 1)

        val again = book.acquire(request = 2, engine = app, kind = APP)

        assertTrue(again.single() is Grant)
        assertNotEquals(first, token(again, 2))
    }

    @Test
    fun `a background request is refused at once while the app holds the client`() {
        book.acquire(request = 1, engine = app, kind = APP)

        assertEquals(listOf(Deny(2)), book.acquire(request = 2, engine = push, kind = BACKGROUND))
        assertFalse(book.isWaiting(2))
    }

    @Test
    fun `an app holder is never asked to yield`() {
        book.acquire(request = 1, engine = app, kind = APP)

        val actions = book.acquire(request = 2, engine = secondApp, kind = APP)

        assertTrue(actions.isEmpty())
        assertTrue(book.isWaiting(2))
    }

    @Test
    fun `a second app engine gets the client when the first lets it go`() {
        val first = token(book.acquire(request = 1, engine = app, kind = APP), 1)
        book.acquire(request = 2, engine = secondApp, kind = APP)

        val handedOn = book.release(first)

        assertTrue(handedOn.single() is Grant)
        assertEquals(2L, (handedOn.single() as Grant).request)
    }

    @Test
    fun `a second app engine gets the client anyway once its wait is over`() {
        book.acquire(request = 1, engine = app, kind = APP)
        book.acquire(request = 2, engine = secondApp, kind = APP)

        val forced = book.timedOut(2).single() as Grant

        assertEquals(2L, forced.request)
        assertTrue(forced.forced)
    }

    @Test
    fun `a background holder is asked to yield for the app, which gets it on release`() {
        val held = token(book.acquire(request = 1, engine = push, kind = BACKGROUND), 1)

        assertEquals(listOf(Yield(push)), book.acquire(request = 2, engine = app, kind = APP))
        assertTrue(book.isWaiting(2))

        val handedOn = book.release(held).single() as Grant
        assertEquals(2L, handedOn.request)
        assertFalse(handedOn.forced)
    }

    @Test
    fun `the app gets the client after its wait even if the background holder never lets go`() {
        book.acquire(request = 1, engine = push, kind = BACKGROUND)
        book.acquire(request = 2, engine = app, kind = APP)

        val forced = book.timedOut(2).single() as Grant

        assertTrue(forced.forced)
        assertEquals(listOf(Deny(3)), book.acquire(request = 3, engine = action, kind = BACKGROUND))
    }

    @Test
    fun `the app waits ahead of background requests`() {
        val held = token(book.acquire(request = 1, engine = push, kind = BACKGROUND), 1)
        book.acquire(request = 2, engine = action, kind = BACKGROUND)
        book.acquire(request = 3, engine = app, kind = APP)

        val handedOn = book.release(held)

        assertEquals(3L, (handedOn.first() as Grant).request)
        assertTrue(handedOn.contains(Deny(2)))
        assertFalse(book.isWaiting(2))
    }

    @Test
    fun `background requests wait their turn behind a background holder`() {
        val held = token(book.acquire(request = 1, engine = push, kind = BACKGROUND), 1)

        assertEquals(
            listOf(Yield(push)),
            book.acquire(request = 2, engine = action, kind = BACKGROUND),
        )
        assertTrue(book.isWaiting(2))

        assertEquals(2L, (book.release(held).single() as Grant).request)
    }

    @Test
    fun `a background request that waits too long is refused`() {
        book.acquire(request = 1, engine = push, kind = BACKGROUND)
        book.acquire(request = 2, engine = action, kind = BACKGROUND)

        assertEquals(listOf(Deny(2)), book.timedOut(2))
        assertFalse(book.isWaiting(2))
    }

    @Test
    fun `background waiters are refused once the app gets the client`() {
        book.acquire(request = 1, engine = push, kind = BACKGROUND)
        book.acquire(request = 2, engine = action, kind = BACKGROUND)
        book.acquire(request = 3, engine = app, kind = APP)

        val actions = book.timedOut(3)

        assertTrue((actions.first() as Grant).forced)
        assertEquals(listOf(Deny(2)), actions.drop(1))
    }

    @Test
    fun `a holder is asked to yield only once`() {
        book.acquire(request = 1, engine = push, kind = BACKGROUND)

        assertEquals(
            listOf(Yield(push)),
            book.acquire(request = 2, engine = action, kind = BACKGROUND),
        )
        assertTrue(book.acquire(request = 3, engine = app, kind = APP).isEmpty())
    }

    @Test
    fun `a background engine that gets the client while others still wait is asked to yield too`() {
        val held = token(book.acquire(request = 1, engine = push, kind = BACKGROUND), 1)
        book.acquire(request = 2, engine = action, kind = BACKGROUND)
        book.acquire(request = 3, engine = 9, kind = BACKGROUND)

        val handedOn = book.release(held)

        assertEquals(listOf(Grant(2, (handedOn.first() as Grant).token), Yield(action)), handedOn)
    }

    @Test
    fun `a detached engine lets go of all its leases`() {
        book.acquire(request = 1, engine = push, kind = BACKGROUND)
        book.acquire(request = 2, engine = push, kind = BACKGROUND)
        book.acquire(request = 3, engine = app, kind = APP)

        val handedOn = book.detached(push)

        assertEquals(3L, (handedOn.single() as Grant).request)
    }

    @Test
    fun `a detached engine's own waiting requests are answered with null`() {
        val held = token(book.acquire(request = 1, engine = push, kind = BACKGROUND), 1)
        book.acquire(request = 2, engine = action, kind = BACKGROUND)

        assertEquals(listOf(Deny(2)), book.detached(action))
        assertFalse(book.isWaiting(2))
        assertTrue(book.release(held).isEmpty())
    }

    @Test
    fun `an app lease taken by an engine that already holds one still refuses the queue`() {
        book.acquire(request = 1, engine = push, kind = BACKGROUND)
        book.acquire(request = 2, engine = action, kind = BACKGROUND)

        val actions = book.acquire(request = 3, engine = push, kind = APP)

        assertTrue(actions.first() is Grant)
        assertEquals(listOf(Deny(2)), actions.drop(1))
    }

    @Test
    fun `tokens are unique ids`() {
        val first = token(book.acquire(request = 1, engine = app, kind = APP), 1)
        val second = token(book.acquire(request = 2, engine = app, kind = APP), 2)

        assertEquals(36, first.length)
        assertNotEquals(first, second)
        java.util.UUID.fromString(first)
    }

    @Test
    fun `a released store is free again`() {
        val held = token(book.acquire(request = 1, engine = app, kind = APP), 1)
        book.release(held)

        assertTrue(book.acquire(request = 2, engine = push, kind = BACKGROUND).single() is Grant)
    }

    @Test
    fun `unknown tokens and settled requests change nothing`() {
        book.acquire(request = 1, engine = app, kind = APP)

        assertTrue(book.release("nope").isEmpty())
        assertTrue(book.timedOut(1).isEmpty())
        assertTrue(book.timedOut(42).isEmpty())
        assertTrue(book.detached(77).isEmpty())
    }
}
