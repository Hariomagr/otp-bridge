package com.hari.otpbridge

/**
 * Best-effort OTP detection. Prefers a code sitting next to an OTP-ish keyword,
 * then falls back to any standalone 4–8 digit or short alphanumeric code.
 */
object OtpExtractor {

    private val keywords = listOf(
        "otp", "code", "verification", "verify", "one-time", "one time",
        "passcode", "password", "pin", "auth", "2fa"
    )

    // A 4–8 digit run, or provider-style alphanumerics like "G-483920".
    private val digitCode = Regex("""(?<![\w-])(\d{4,8})(?![\w-])""")
    private val prefixedCode = Regex("""\b([A-Z]{1,3}-\d{4,8})\b""")
    private val alnumCode = Regex("""(?<![\w-])([A-Z0-9]{5,8})(?![\w-])""")

    fun extract(text: String): String? {
        val lower = text.lowercase()
        val hasKeyword = keywords.any { lower.contains(it) }

        // Prefixed codes are almost always the OTP (e.g. Google's "G-123456").
        prefixedCode.find(text)?.let { return it.groupValues[1].substringAfter('-') }

        val digits = digitCode.findAll(text).map { it.groupValues[1] }.toList()
        if (hasKeyword && digits.isNotEmpty()) {
            // Prefer 6-digit, the most common OTP length.
            return digits.firstOrNull { it.length == 6 } ?: digits.first()
        }
        if (digits.size == 1) return digits.first()

        // Alphanumeric codes only when a keyword makes intent clear, and only
        // if they actually contain a digit (avoid matching plain words).
        if (hasKeyword) {
            alnumCode.find(text)?.let { m ->
                val c = m.groupValues[1]
                if (c.any { it.isDigit() }) return c
            }
        }
        return null
    }
}
