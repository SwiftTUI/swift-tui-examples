import Foundation

/// Offline DAG layout for `git-viz dag`.
///
/// Given a topologically ordered list of `(sha, parents)` rows (newest
/// first), `layout` assigns each commit a lane, a pre-rendered glyph
/// stream, and an optional connector row below the commit. Each glyph
/// carries the lane it belongs to so the renderer can color lanes
/// individually for visual tracing.
enum GraphLayout {
  /// Layout result. `bailed` is true when the graph required more lanes
  /// than `maxLanes` and rendering stopped early.
  struct Result: Sendable, Equatable {
    var commits: [GraphCommit]
    var bailed: Bool
  }

  /// Computes lanes and per-row glyph streams for the supplied commits.
  ///
  /// - Parameters:
  ///   - rows: `(sha, parents, subject)` triples in display order
  ///     (newest first).
  ///   - maxLanes: Bail out and stop laying out once a row — a commit's
  ///     own row or the connector row below it — would need more than
  ///     `maxLanes` simultaneous lanes. A commit whose row fits but whose
  ///     connector would not is emitted without the connector. Defaults
  ///     to 12.
  static func layout(
    rows: [(sha: String, parents: [String], subject: String)],
    maxLanes: Int = 12
  ) -> Result {
    var lanes: [String?] = []  // index → sha the lane is waiting for
    var result: [GraphCommit] = []
    var bailed = false

    for row in rows {
      // 1. Find or allocate the lane for this commit.
      let lane: Int
      if let existing = lanes.firstIndex(where: { $0 == row.sha }) {
        lane = existing
      } else if let freeLane = lanes.firstIndex(where: { $0 == nil }) {
        lane = freeLane
        lanes[freeLane] = row.sha
      } else {
        lane = lanes.count
        lanes.append(row.sha)
      }

      if lanes.count > maxLanes {
        bailed = true
        break
      }

      // 2. Render the commit's own glyph row.
      let commitGlyphs = renderGlyphRow(commitLane: lane, lanes: lanes)

      // 3. Process parents. The commit's lane is freed first; then each
      //    parent is either joined in place (if some lane already waits
      //    for it) or assigned to the commit's freed lane (first eligible
      //    parent only) or to a brand-new lane. Joining already-waited
      //    parents avoids the duplicate-lane bug where two lanes would
      //    point at the same SHA; each join is remembered by the lane that
      //    holds that parent, so the connector can draw it.
      lanes[lane] = nil
      var newLanes: [Int] = []
      var joinLanes: [Int] = []
      var commitLaneAssigned = false
      for parent in row.parents {
        if let waiting = lanes.firstIndex(of: parent) {
          joinLanes.append(waiting)
          continue
        }
        if !commitLaneAssigned {
          lanes[lane] = parent
          commitLaneAssigned = true
        } else if let freeLane = lanes.firstIndex(where: { $0 == nil }) {
          lanes[freeLane] = parent
          newLanes.append(freeLane)
        } else {
          lanes.append(parent)
          newLanes.append(lanes.count - 1)
        }
      }

      // 4. The connector below this commit spans every lane it touches, so
      //    it needs the lanes as they are after its parents are placed.
      //    When that is more than `maxLanes`, emit the commit row (which
      //    fits) without the connector and stop.
      if lanes.count > maxLanes {
        bailed = true
        result.append(
          GraphCommit(
            sha: row.sha,
            parents: row.parents,
            subject: row.subject,
            lane: lane,
            glyphs: commitGlyphs,
            connectorGlyphs: nil
          )
        )
        break
      }

      // 5. Emit a connector when a parent opened a lane or joined one.
      let connectorGlyphs: [GraphGlyph]?
      if newLanes.isEmpty && joinLanes.isEmpty {
        connectorGlyphs = nil
      } else {
        connectorGlyphs = renderConnector(
          commitLane: lane,
          continues: commitLaneAssigned,
          newLanes: newLanes,
          joinLanes: joinLanes,
          lanes: lanes
        )
      }

      result.append(
        GraphCommit(
          sha: row.sha,
          parents: row.parents,
          subject: row.subject,
          lane: lane,
          glyphs: commitGlyphs,
          connectorGlyphs: connectorGlyphs
        )
      )

      // 6. Trim trailing nil lanes so the array stays compact.
      while let last = lanes.last, last == nil {
        lanes.removeLast()
      }
    }

    return Result(commits: result, bailed: bailed)
  }

  // MARK: - Glyph rendering

  /// Renders one commit row column-by-column. Lane columns sit at even
  /// positions (0, 2, 4, …); single-space separators sit between them.
  ///
  /// - The lane carrying the commit gets `●`.
  /// - Every other occupied lane gets `│`.
  /// - Empty lanes get a space.
  /// - Inter-lane separators get a space with `lane = nil` so the
  ///   renderer leaves them uncolored.
  private static func renderGlyphRow(
    commitLane: Int,
    lanes: [String?]
  ) -> [GraphGlyph] {
    var glyphs: [GraphGlyph] = []
    for index in 0..<lanes.count {
      if index == commitLane {
        glyphs.append(GraphGlyph(character: "●", lane: index))
      } else if lanes[index] != nil {
        glyphs.append(GraphGlyph(character: "│", lane: index))
      } else {
        glyphs.append(GraphGlyph(character: " ", lane: nil))
      }
      if index < lanes.count - 1 {
        glyphs.append(GraphGlyph(character: " ", lane: nil))
      }
    }
    return glyphs
  }

  /// Renders the connector row below a commit whose parents opened new
  /// lanes (a merge's fan-out) or joined lanes that already wait for them
  /// (a convergence). One row draws both: it spans from the commit's lane to
  /// the farthest new or joined lane on either side. New lanes can land on
  /// either side of `commitLane` depending on which free slot the allocator
  /// picked (e.g., a left-side lane was vacated by an earlier convergence).
  ///
  /// Glyphs:
  /// - The commit's lane gets `├`, `┤` or `┼` when it continues below
  ///   (its first fresh parent took it) and `╰`, `╯` or `┴` when it ends
  ///   there, by whether the span reaches right, left or both ways.
  /// - A new lane gets `╮` (right of the commit) or `╭` (left).
  /// - A joined lane is the lane holding that parent, found by commit id:
  ///   `┤` or `├` at the end of the span, `┼` inside it.
  /// - Any other occupied lane inside the span is crossed with `┼`.
  ///
  /// Lane attribution for coloring:
  /// - Endpoint and junction glyphs are tagged with their column's lane.
  /// - Crossings (`┼`) are tagged with the lane being crossed, so
  ///   eye-tracing follows the continuing lane through the crossing.
  /// - Horizontal glyphs (`─`) are tagged with the moving lane: the first
  ///   new lane when the commit spawns one, so the new branch's color
  ///   visibly leaves the commit, otherwise the commit's own lane, so a
  ///   join reads as that lane curving in to meet the survivor.
  private static func renderConnector(
    commitLane: Int,
    continues: Bool,
    newLanes: [Int],
    joinLanes: [Int],
    lanes: [String?]
  ) -> [GraphGlyph] {
    let newLanesSet = Set(newLanes)
    let joinLanesSet = Set(joinLanes)
    let targets = newLanes + joinLanes
    let reachesLeft = targets.contains { $0 < commitLane }
    let reachesRight = targets.contains { $0 > commitLane }
    let commitGlyph: Character =
      switch (continues, reachesLeft, reachesRight) {
      case (true, true, true): "┼"
      case (true, true, false): "┤"
      case (true, false, _): "├"
      case (false, true, true): "┴"
      case (false, true, false): "╯"
      case (false, false, _): "╰"
      }

    let leftBound = min(commitLane, targets.min() ?? commitLane)
    let rightBound = max(commitLane, targets.max() ?? commitLane)
    let maxIndex = max(rightBound, lanes.count - 1)
    let movingLane = newLanes.first ?? commitLane
    var glyphs: [GraphGlyph] = []

    for col in 0...maxIndex {
      let glyph: GraphGlyph
      if col < leftBound || col > rightBound {
        // Outside the connector — pass the underlying lane through.
        if col < lanes.count, lanes[col] != nil {
          glyph = GraphGlyph(character: "│", lane: col)
        } else {
          glyph = GraphGlyph(character: " ", lane: nil)
        }
      } else if col == commitLane {
        glyph = GraphGlyph(character: commitGlyph, lane: commitLane)
      } else if newLanesSet.contains(col) {
        glyph = GraphGlyph(character: (col > commitLane) ? "╮" : "╭", lane: col)
      } else if joinLanesSet.contains(col) {
        let ch: Character = col == leftBound ? "├" : col == rightBound ? "┤" : "┼"
        glyph = GraphGlyph(character: ch, lane: col)
      } else if col < lanes.count, lanes[col] != nil {
        glyph = GraphGlyph(character: "┼", lane: col)
      } else {
        glyph = GraphGlyph(character: "─", lane: movingLane)
      }
      glyphs.append(glyph)

      if col < maxIndex {
        let extends = (col >= leftBound && col < rightBound)
        if extends {
          glyphs.append(GraphGlyph(character: "─", lane: movingLane))
        } else {
          glyphs.append(GraphGlyph(character: " ", lane: nil))
        }
      }
    }
    return glyphs
  }
}
