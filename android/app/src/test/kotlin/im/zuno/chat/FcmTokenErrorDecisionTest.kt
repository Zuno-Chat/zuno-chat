package im.zuno.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class FcmTokenErrorDecisionTest {
    @Test
    fun `no instance-id service anywhere in the chain means no Google Play services`() {
        assertEquals(
            FcmTokenFailure.NO_PLAY_SERVICES,
            FcmTokenErrorDecision.classify(
                listOf(
                    "java.io.IOException: FCM Registration failed!",
                    "java.util.concurrent.ExecutionException: java.io.IOException: MISSING_INSTANCEID_SERVICE",
                    "MISSING_INSTANCEID_SERVICE",
                ),
            ),
        )
    }

    @Test
    fun `an uninitialized default app means the build has no Firebase config`() {
        assertEquals(
            FcmTokenFailure.NOT_CONFIGURED,
            FcmTokenErrorDecision.classify(
                listOf(
                    "Default FirebaseApp is not initialized in this process im.zuno.chat. " +
                        "Make sure to call FirebaseApp.initializeApp(Context) first.",
                ),
            ),
        )
    }

    @Test
    fun `service hiccups are worth another try`() {
        for (message in listOf(
            "SERVICE_NOT_AVAILABLE",
            "INTERNAL_SERVER_ERROR",
            "InternalServerError",
            "TIMEOUT",
        )) {
            assertEquals(
                message,
                FcmTokenFailure.UNAVAILABLE,
                FcmTokenErrorDecision.classify(listOf("FCM Registration failed!", message)),
            )
        }
    }

    @Test
    fun `anything else is a plain failure`() {
        for (messages in listOf(
            listOf("FIS_AUTH_ERROR"),
            listOf("TOO_MANY_REGISTRATIONS"),
            listOf(null),
            emptyList(),
        )) {
            assertEquals(
                "$messages",
                FcmTokenFailure.FAILED,
                FcmTokenErrorDecision.classify(messages),
            )
        }
    }

    @Test
    fun `a missing service wins over a hiccup further down the chain`() {
        assertEquals(
            FcmTokenFailure.NO_PLAY_SERVICES,
            FcmTokenErrorDecision.classify(
                listOf("SERVICE_NOT_AVAILABLE", "MISSING_INSTANCEID_SERVICE"),
            ),
        )
    }

    @Test
    fun `the wire names match what Dart parses`() {
        assertEquals(
            listOf("noPlayServices", "notConfigured", "unavailable", "failed"),
            FcmTokenFailure.entries.map { it.wire },
        )
    }
}
