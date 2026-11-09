package im.zuno.chat.zuno_http

import org.chromium.net.CronetProvider

data class ProviderInfo(val name: String, val enabled: Boolean)

fun chooseBundled(available: List<ProviderInfo>): ProviderInfo? =
    available.firstOrNull { it.name == CronetProvider.PROVIDER_NAME_APP_PACKAGED && it.enabled }
