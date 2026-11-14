package org.swifttui.gallery.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.fail
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Proves that the connected-journey runner turns a failed test into a red
 * verdict. The test is skipped unless the run passes the instrumentation
 * argument [ARGUMENT] as `true`; `Scripts/android_connected_journey.sh
 * --failing-fixture` does that.
 */
@RunWith(AndroidJUnit4::class)
class AndroidJourneyVerdictFixtureTest {
  @Test
  fun failsOnlyWhenTheRunnerAsksForARedVerdict() {
    val requested = InstrumentationRegistry.getArguments().getString(ARGUMENT) == "true"
    assumeTrue("the verdict fixture runs only when $ARGUMENT=true", requested)
    fail("deliberate failure requested by the instrumentation argument $ARGUMENT")
  }

  private companion object {
    const val ARGUMENT = "swifttuiJourneyFailFixture"
  }
}
