package org.swifttui.gallery.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import sh.swifttui.android.host.SwiftTUIAndroidStyle
import sh.swifttui.android.host.SwiftTUIFrame
import sh.swifttui.android.host.SwiftTUIHostView
import sh.swifttui.android.host.rememberSwiftTUIHostState

class MainActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    setContent {
      GalleryScreen()
    }
  }
}

@Composable
private fun GalleryScreen() {
  val hostState = rememberSwiftTUIHostState()
  val hostStyle = SwiftTUIAndroidStyle.default()
  val hostFrame = hostState.frame
  SideEffect {
    AndroidGalleryTestProbe.snapshot = AndroidGalleryTestProbe.Snapshot(
      frame = hostFrame,
      style = hostStyle
    )
  }
  Box(
    modifier = Modifier
      .fillMaxSize()
      .background(Color(0xFF101318))
  ) {
    Box(
      modifier = Modifier
        .fillMaxSize()
        .safeDrawingPadding()
    ) {
      SwiftTUIHostView(
        state = hostState,
        style = hostStyle,
        modifier = Modifier
          .fillMaxSize()
          .testTag("swiftTUIHost")
      )
    }
  }
}

internal object AndroidGalleryTestProbe {
  data class Snapshot(
    val frame: SwiftTUIFrame?,
    val style: SwiftTUIAndroidStyle
  )

  @Volatile
  var snapshot: Snapshot? = null
}
