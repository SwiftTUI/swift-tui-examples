package sh.swifttui.android.host

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

class SwiftTUIImeTest {
  @Test
  fun appendedTextEmitsTheSuffix() {
    assertEquals("i", SwiftTUIIme.bytesForEdit("h", "hi").decodeToString())
    assertEquals("ello", SwiftTUIIme.bytesForEdit("h", "hello").decodeToString())
  }

  @Test
  fun deletionEmitsBackspaces() {
    assertArrayEquals(
      byteArrayOf(0x7F),
      SwiftTUIIme.bytesForEdit("hi", "h")
    )
    assertArrayEquals(
      byteArrayOf(0x7F, 0x7F),
      SwiftTUIIme.bytesForEdit("hello", "hel")
    )
  }

  @Test
  fun replacementBackspacesThenInserts() {
    // "cat" -> "cot": delete 't','a' down to common prefix "c", then insert "ot".
    assertArrayEquals(
      byteArrayOf(0x7F, 0x7F) + "ot".encodeToByteArray(),
      SwiftTUIIme.bytesForEdit("cat", "cot")
    )
  }

  @Test
  fun newlinesAreNormalizedToCarriageReturn() {
    assertEquals("\r", SwiftTUIIme.bytesForEdit("", "\n").decodeToString())
    assertEquals("a\r", SwiftTUIIme.bytesForEdit("", "a\r\n").decodeToString())
  }

  @Test
  fun noChangeEmitsNothing() {
    assertArrayEquals(ByteArray(0), SwiftTUIIme.bytesForEdit("same", "same"))
    assertArrayEquals(ByteArray(0), SwiftTUIIme.bytesForEdit("", ""))
  }
}
