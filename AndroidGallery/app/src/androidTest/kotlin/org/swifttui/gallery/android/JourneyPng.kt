package org.swifttui.gallery.android

import android.util.Base64

/**
 * A 240x160 opaque RGB PNG for the file journeys: the left half is
 * [LEFT_COLOR], the right half is [RIGHT_COLOR]. Two flat halves make a decoded
 * and rendered copy recognizable from two pixel samples.
 */
internal object JourneyPng {
  const val WIDTH = 240
  const val HEIGHT = 160
  const val LEFT_COLOR = 0xFFE61EC8.toInt()
  const val RIGHT_COLOR = 0xFF14C85A.toInt()

  private const val BASE64 =
    "iVBORw0KGgoAAAANSUhEUgAAAPAAAACgCAIAAAC9uXYyAAAB1UlEQVR42u3SMQ0AMAgAMERwI2yKUYIOVIyrSSU0" +
      "ppoD2Y8DoZrQQiO00EIjtNAILbTQCC00QgstNEILjdBCC43QQiO00EIjtNAILbTQCC00QgstNEILjdBCC43QQiO0" +
      "0EIjtNAILbTQCC00QgstNEILjdBCC43QQiO00EIjtNAILbTQCC00qgktNEILLTRCC43QQguN0EIjtNBCI7TQCC20" +
      "0AgtNEILLTRCC43QQguN0EIjtNBCI7TQCC200AgtNEILLTRCC43QQguN0EIjtNBCI7TQCC200AgtNEILLTRCC43Q" +
      "QguN0EIjtNBCI7TQQiO00AgttNAILTRCCy00QguN0EILjdBCI7TQQiO00AgttNAILTRCCy00QguN0EILjdBCI7TQ" +
      "QiO00AgttNAILTRCCy00QguN0EILjdBCI7TQQiO00AgttNAILTRCCy00QgsttG1CC43QQguN0EIjtNBCI7TQCC20" +
      "0AgtNEILLTRCC43QQguN0EIjtNBCI7TQCC200AgtNEILLTRCC43QQguN0EIjtNBCI7TQCC200AgtNEILLTRCC43Q" +
      "QguN0EIjtNBCI7TQQtsmtNAILbTQCC00QgstNEILjdBCC43QQiO00ELzxwK6G6MwS3b9HAAAAABJRU5ErkJggg=="

  fun bytes(): ByteArray = Base64.decode(BASE64, Base64.DEFAULT)
}
