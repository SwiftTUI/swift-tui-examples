# mrkdwn performance envelope

Internal regression budgets for the mrkdwn viewer. These are regression
budgets, not user-facing speed claims.

Timing assertions have two tiers. Every environment makes sure that each
measurement is below a **ceiling**. The native Linux gate also uses this
ceiling. A ceiling is
approximately five times its budget. A result above a ceiling indicates a
large regression, such as a lost cache or accidental O(n²) behavior. Tight
**budgets** are optional under `MRKDWN_PERFORMANCE_BUDGETS=1`. Shared CI runners
are two to three times slower than the calibration machine. Thus, CI does not
apply developer-machine budgets. Run the budget lane on a quiet machine. Tests
always print durations. All environments apply limits to node counts, geometry
computations, visible rows, scroll positions, and cache size.

The reference machine was an Apple M5 Max Mac17,7 with 128 GiB RAM, macOS 27,
and Swift 6.3.3. The Phase 4 debug baseline compiled a 1 MiB, 10,000-block
document in approximately 0.10 seconds. Its budget is 0.20 seconds. The settled
geometry path took approximately 0.60 seconds for the first 10,000-block
layout. It took 0.8 milliseconds for 1,000 cached scroll updates. The budgets
are 1.20 seconds and 1.5 milliseconds.

The root-shaped 80×24 table fixture compiled 500×20 cells in approximately
0.064 seconds. It computed wrapped metrics in 0.151 seconds and painted the
first frame in 0.62 seconds. A combined vertical and horizontal scroll caused
a repaint in 0.85 seconds. The respective budgets are 0.130, 0.300, 1.230, and
1.700 seconds. Each environment limits a table frame to fewer than 1,250 render
nodes. Separate fixtures insert image payloads and make sure that the encoded
cache stays within 64 entries and 64 MiB. Viewer admission and retained
resource states have a limit of 128.
Image execution permits four active loads and 64 queued loads. The app cancels
hidden work.
