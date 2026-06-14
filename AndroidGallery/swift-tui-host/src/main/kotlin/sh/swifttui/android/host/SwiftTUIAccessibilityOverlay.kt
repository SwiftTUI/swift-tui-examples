package sh.swifttui.android.host

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.unit.Dp

@Composable
fun SwiftTUIAccessibilityOverlay(
  frame: SwiftTUIFrame?,
  style: SwiftTUIAndroidStyle,
  modifier: Modifier = Modifier
) {
  val nodes = frame?.accessibilityNodes.orEmpty().filterNot { node ->
    node.hidden || node.rect.width <= 0 || node.rect.height <= 0
  }
  val density = LocalDensity.current

  Box(modifier = modifier) {
    nodes.forEach { node ->
      Box(
        modifier = Modifier
          .offset(
            x = with(density) { (node.rect.x * style.cellWidthPx).toDp() },
            y = with(density) { (node.rect.y * style.cellHeightPx).toDp() }
          )
          .size(
            width = with(density) {
              (node.rect.width * style.cellWidthPx).toDp().coerceAtLeast(Dp.Hairline)
            },
            height = with(density) {
              (node.rect.height * style.cellHeightPx).toDp().coerceAtLeast(Dp.Hairline)
            }
          )
          .clearAndSetSemantics {
            val description = node.label ?: node.role
            if (description.isNotBlank()) {
              contentDescription = description
            }
            node.hint?.takeIf { it.isNotBlank() }?.let {
              stateDescription = it
            }
            node.role.toComposeRole()?.let {
              role = it
            }
            node.liveRegion.toLiveRegionMode()?.let {
              liveRegion = it
            }
            if (node.isFocused) {
              selected = true
            }
            testTag = node.id
          }
      )
    }

    SwiftTUIAnnouncer(announcement = frame?.accessibilityAnnouncements?.lastOrNull())
  }
}

/**
 * Speaks runtime accessibility announcements through TalkBack. The announcement
 * rides an invisible live-region node; Compose re-announces only when the text
 * changes, so a persisting message is not repeated every polled frame.
 */
@Composable
private fun SwiftTUIAnnouncer(
  announcement: SwiftTUIAccessibilityAnnouncement?
) {
  if (announcement == null || announcement.message.isBlank()) {
    return
  }
  Box(
    modifier = Modifier
      .size(Dp.Hairline)
      .clearAndSetSemantics {
        liveRegion = if (announcement.politeness == "assertive") {
          LiveRegionMode.Assertive
        } else {
          LiveRegionMode.Polite
        }
        contentDescription = announcement.message
      }
  )
}

private fun String.toComposeRole(): Role? =
  when (this) {
    "button", "disclosureGroup", "menuItem" -> Role.Button
    "checkbox" -> Role.Checkbox
    "image" -> Role.Image
    "tab" -> Role.Tab
    "toggle" -> Role.Switch
    else -> null
  }

private fun String?.toLiveRegionMode(): LiveRegionMode? =
  when (this) {
    "polite" -> LiveRegionMode.Polite
    "assertive" -> LiveRegionMode.Assertive
    else -> null
  }
