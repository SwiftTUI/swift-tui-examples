package sh.swifttui.android.host

internal object SwiftTUIJni {
  init {
    System.loadLibrary("swift_tui_jni")
  }

  external fun createHost(): Long
  external fun start(handle: Long)
  external fun stop(handle: Long)
  external fun destroy(handle: Long)
  external fun resize(
    handle: Long,
    columns: Int,
    rows: Int,
    cellPixelWidth: Double,
    cellPixelHeight: Double
  )
  external fun copyLatestFrame(handle: Long, outBuffer: ByteArray?, capacity: Int): Int
  external fun copyClipboardText(handle: Long, outBuffer: ByteArray?, capacity: Int): Int
  external fun sendInput(handle: Long, input: ByteArray, count: Int)
}

