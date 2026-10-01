package im.zuno.chat

import android.app.Activity
import android.content.Context
import android.util.Log
import com.google.android.gms.common.GoogleApiAvailability
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging

sealed interface FcmTokenOutcome {
    data class Token(val token: String) : FcmTokenOutcome

    data class Failure(val failure: FcmTokenFailure, val message: String?) : FcmTokenOutcome
}

object FcmPlatform {
    private const val TAG = "FcmPlatform"
    private const val MAX_CAUSES = 8

    fun configured(context: Context): Boolean? = try {
        FirebaseApp.getApps(context).isNotEmpty()
    } catch (e: Exception) {
        Log.w(TAG, "Could not ask Firebase whether it is set up", e)
        null
    }

    fun availability(context: Context): FcmAvailability =
        FcmAvailabilityDecision.decide(configured(context), playServicesStatus(context))

    @Suppress("DEPRECATION")
    fun token(context: Context, done: (FcmTokenOutcome) -> Unit) {
        if (configured(context) == null) {
            return done(
                FcmTokenOutcome.Failure(
                    FcmTokenFailure.FAILED,
                    "Could not ask Firebase whether it is set up",
                ),
            )
        }
        val messaging = messaging(context) ?: return done(
            FcmTokenOutcome.Failure(
                FcmTokenFailure.NOT_CONFIGURED,
                "Firebase is not set up in this build",
            ),
        )
        try {
            messaging.isAutoInitEnabled = true
            messaging.token.addOnCompleteListener { task ->
                val token = if (task.isSuccessful) task.result else null
                if (!token.isNullOrEmpty()) {
                    done(FcmTokenOutcome.Token(token))
                } else {
                    val error = task.exception
                    Log.w(TAG, "FCM token request failed", error)
                    done(
                        FcmTokenOutcome.Failure(
                            FcmTokenErrorDecision.classify(causes(error)),
                            error?.message,
                        ),
                    )
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "FCM token request could not start", e)
            done(FcmTokenOutcome.Failure(FcmTokenErrorDecision.classify(causes(e)), e.message))
        }
    }

    @Suppress("DEPRECATION")
    fun deleteToken(context: Context, done: (Exception?) -> Unit) {
        val messaging = messaging(context) ?: return done(null)
        try {
            messaging.isAutoInitEnabled = false
            messaging.deleteToken().addOnCompleteListener { task -> done(task.exception) }
        } catch (e: Exception) {
            done(e)
        }
    }

    fun fixPlayServices(activity: Activity, done: (FcmAvailability) -> Unit) {
        try {
            GoogleApiAvailability.getInstance()
                .makeGooglePlayServicesAvailable(activity)
                .addOnCompleteListener { done(availability(activity)) }
        } catch (e: Exception) {
            Log.w(TAG, "Google Play services could not be fixed", e)
            done(availability(activity))
        }
    }

    private fun messaging(context: Context): FirebaseMessaging? {
        if (configured(context) != true) return null
        return try {
            FirebaseMessaging.getInstance()
        } catch (e: IllegalStateException) {
            Log.w(TAG, "Firebase Messaging is not available", e)
            null
        }
    }

    private fun playServicesStatus(context: Context): Int = try {
        GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context)
    } catch (e: Exception) {
        Log.w(TAG, "Could not ask for Google Play services", e)
        FcmAvailabilityDecision.CHECK_FAILED
    }

    private fun causes(error: Throwable?): List<String> = generateSequence(error) { it.cause }
        .take(MAX_CAUSES)
        .map { it.message ?: it.toString() }
        .toList()
}
