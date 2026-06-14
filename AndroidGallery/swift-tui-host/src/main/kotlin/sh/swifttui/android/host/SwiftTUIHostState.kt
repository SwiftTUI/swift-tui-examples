package sh.swifttui.android.host

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive

private data class HostResize(
  val columns: Int,
  val rows: Int,
  val cellPixelWidth: Double,
  val cellPixelHeight: Double
)

class SwiftTUIHostState internal constructor(
  private val createHost: () -> Long,
  private val clipboard: SwiftTUIClipboard? = null
) {
  var frame by mutableStateOf<SwiftTUIFrame?>(null)
    private set

  var lastError by mutableStateOf<String?>(null)
    private set

  private var handle by mutableLongStateOf(0L)
  private var lastResize: HostResize? = null

  fun start() {
    if (handle == 0L) {
      handle = createHost()
      if (handle == 0L) {
        lastError = "SwiftTUI host could not be created."
        return
      }
    }
    SwiftTUIJni.start(handle)
  }

  fun stop() {
    val currentHandle = handle
    if (currentHandle != 0L) {
      SwiftTUIJni.stop(currentHandle)
    }
  }

  fun destroy() {
    val currentHandle = handle
    handle = 0L
    lastResize = null
    if (currentHandle != 0L) {
      SwiftTUIJni.destroy(currentHandle)
    }
  }

  fun resize(
    columns: Int,
    rows: Int,
    cellPixelWidth: Double,
    cellPixelHeight: Double
  ) {
    val currentHandle = handle
    if (currentHandle == 0L) {
      return
    }

    val resize = HostResize(
      columns = columns.coerceAtLeast(1),
      rows = rows.coerceAtLeast(1),
      cellPixelWidth = cellPixelWidth.coerceAtLeast(1.0),
      cellPixelHeight = cellPixelHeight.coerceAtLeast(1.0)
    )
    if (resize == lastResize) {
      return
    }

    lastResize = resize
    SwiftTUIJni.resize(
      currentHandle,
      resize.columns,
      resize.rows,
      resize.cellPixelWidth,
      resize.cellPixelHeight
    )
  }

  fun sendInput(bytes: ByteArray) {
    val currentHandle = handle
    if (currentHandle != 0L && bytes.isNotEmpty()) {
      SwiftTUIJni.sendInput(currentHandle, bytes, bytes.size)
    }
  }

  /** Reads the system clipboard and delivers it to the app as a bracketed paste. */
  fun paste() {
    val text = clipboard?.read() ?: return
    sendInput(SwiftTUIInput.bracketedPaste(text))
  }

  suspend fun pollFrames() {
    while (currentCoroutineContext().isActive) {
      pollFrameOnce()
      drainClipboardWrite()
      delay(33L)
    }
  }

  /** Forwards any app-requested copy to the system clipboard, draining it once. */
  private fun drainClipboardWrite() {
    val currentHandle = handle
    val clipboard = clipboard ?: return
    if (currentHandle == 0L) {
      return
    }

    val needed = SwiftTUIJni.copyClipboardText(currentHandle, null, 0)
    if (needed <= 0) {
      return
    }

    val bytes = ByteArray(needed)
    val copied = SwiftTUIJni.copyClipboardText(currentHandle, bytes, bytes.size)
    if (copied in 1..bytes.size) {
      clipboard.write(bytes.decodeToString(0, copied))
    }
  }

  private fun pollFrameOnce() {
    val currentHandle = handle
    if (currentHandle == 0L) {
      return
    }

    val needed = SwiftTUIJni.copyLatestFrame(currentHandle, null, 0)
    if (needed <= 0) {
      return
    }

    val bytes = ByteArray(needed)
    val copied = SwiftTUIJni.copyLatestFrame(currentHandle, bytes, bytes.size)
    if (copied <= bytes.size) {
      val json = bytes.decodeToString(0, copied.coerceAtMost(bytes.size))
      runCatching {
        SwiftTUIFrame.parse(json)
      }.onSuccess { parsedFrame ->
        if (parsedFrame.sequence != frame?.sequence) {
          frame = parsedFrame
          lastError = null
        }
      }.onFailure { error ->
        lastError = error.message ?: error.toString()
      }
    }
  }
}

@Composable
fun rememberSwiftTUIHostState(): SwiftTUIHostState {
  val context = LocalContext.current
  val state = remember {
    SwiftTUIHostState(
      createHost = { SwiftTUIJni.createHost() },
      clipboard = AndroidSystemClipboard(context)
    )
  }

  DisposableEffect(state) {
    state.start()
    onDispose {
      state.destroy()
    }
  }

  LaunchedEffect(state) {
    state.pollFrames()
  }

  return state
}

