package org.swifttui.gallery.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
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
  Box(
    modifier = Modifier
      .fillMaxSize()
      .background(Color(0xFF101318))
  ) {
    SwiftTUIHostView(
      state = hostState,
      modifier = Modifier.fillMaxSize()
    )
  }
}

