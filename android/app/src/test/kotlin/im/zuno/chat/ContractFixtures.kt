package im.zuno.chat

import java.io.File
import org.json.JSONObject

object ContractFixtures {
    fun load(name: String): JSONObject {
        val file = generateSequence(File("").absoluteFile) { it.parentFile }
            .map { File(it, "test/fixtures/push/$name") }
            .first { it.isFile }
        return JSONObject(file.readText())
    }
}
