import Testing

@testable import GitViz

struct GraphLayoutTests {
  @Test("Linear history places every commit in lane 0")
  func linearHistory() {
    let rows = [
      (sha: "c3", parents: ["c2"], subject: "third"),
      (sha: "c2", parents: ["c1"], subject: "second"),
      (sha: "c1", parents: [], subject: "first"),
    ]
    let result = GraphLayout.layout(rows: rows)
    #expect(!result.bailed)
    #expect(result.commits.count == 3)
    #expect(result.commits.allSatisfy { $0.lane == 0 })
  }

  @Test("Merge commit reserves a second lane for its extra parent")
  func mergeCommitOpensLane() {
    // m  <- merge of f and a
    // |\
    // f a
    let rows = [
      (sha: "m", parents: ["f", "a"], subject: "merge"),
      (sha: "f", parents: ["root"], subject: "first parent"),
      (sha: "a", parents: ["root"], subject: "side branch"),
      (sha: "root", parents: [], subject: "root"),
    ]
    let result = GraphLayout.layout(rows: rows)
    #expect(!result.bailed)
    let merge = result.commits[0]
    let firstParent = result.commits[1]
    let sideBranch = result.commits[2]
    let root = result.commits[3]
    #expect(merge.lane == 0)
    #expect(firstParent.lane == 0)
    #expect(sideBranch.lane == 1)
    // Once both side lanes converge on `root`, the root lives in the
    // earliest available lane (lane 0).
    #expect(root.lane == 0)
  }

  @Test("Layout bails when a row would require more than maxLanes lanes")
  func bailsOnExcessLanes() {
    var rows: [(sha: String, parents: [String], subject: String)] = []
    rows.append(("m", (1...5).map { "p\($0)" }, "octopus"))
    for index in 1...5 {
      rows.append(("p\(index)", [], "parent \(index)"))
    }
    let result = GraphLayout.layout(rows: rows, maxLanes: 3)
    #expect(result.bailed)
  }

  @Test("Glyph row marks the commit lane with ● and other lanes with │")
  func glyphRowShape() {
    let rows = [
      (sha: "m", parents: ["a", "b"], subject: "merge"),
      (sha: "a", parents: [], subject: "left"),
      (sha: "b", parents: [], subject: "right"),
    ]
    let result = GraphLayout.layout(rows: rows)
    // First row: only one lane, just `●`.
    #expect(result.commits[0].glyphRow == "●")
    // Second row: lane 0 is the active commit (●), lane 1 still
    // carries `b` (│).
    #expect(result.commits[1].glyphRow == "● │")
  }

  @Test("Merge commit emits a ├─╮ fan-out connector below itself")
  func mergeEmitsFanOutConnector() {
    let rows = [
      (sha: "m", parents: ["f", "a"], subject: "merge"),
      (sha: "f", parents: ["root"], subject: "first parent"),
      (sha: "a", parents: ["root"], subject: "side branch"),
      (sha: "root", parents: [], subject: "root"),
    ]
    let result = GraphLayout.layout(rows: rows)
    let merge = result.commits[0]
    #expect(merge.connectorBelow == "├─╮")
  }

  @Test("Each connector glyph carries the lane index it belongs to for coloring")
  func glyphsCarryLaneIndices() {
    let rows = [
      (sha: "m", parents: ["f", "a"], subject: "merge"),
      (sha: "f", parents: ["root"], subject: "first parent"),
      (sha: "a", parents: ["root"], subject: "side branch"),
      (sha: "root", parents: [], subject: "root"),
    ]
    let result = GraphLayout.layout(rows: rows)
    let merge = result.commits[0]
    // Commit row: a single `●` on lane 0.
    #expect(merge.glyphs.count == 1)
    #expect(merge.glyphs[0].lane == 0)
    // Fan-out connector: `├─╮` — left lane = commit, middle = moving
    // (new lane 1), right = new lane 1.
    let connector = merge.connectorGlyphs ?? []
    #expect(connector.count == 3)
    #expect(connector[0].character == "├")
    #expect(connector[0].lane == 0)
    #expect(connector[1].character == "─")
    #expect(connector[1].lane == 1)  // the spawning lane
    #expect(connector[2].character == "╮")
    #expect(connector[2].lane == 1)
  }

  @Test("Convergence emits a ├─╯ connector when a side lane disappears")
  func convergenceEmitsConnector() {
    // Diamond: m -> f, a; f -> root; a -> root.
    // After processing `a`, lane 1 has nothing left to wait for (root
    // is already in lane 0), so we expect a convergence connector below
    // `a` rejoining lane 0.
    let rows = [
      (sha: "m", parents: ["f", "a"], subject: "merge"),
      (sha: "f", parents: ["root"], subject: "first parent"),
      (sha: "a", parents: ["root"], subject: "side branch"),
      (sha: "root", parents: [], subject: "root"),
    ]
    let result = GraphLayout.layout(rows: rows)
    let sideBranch = result.commits[2]
    #expect(sideBranch.connectorBelow == "├─╯")
  }

  @Test("Linear commits have no connector below")
  func linearCommitsHaveNoConnector() {
    let rows = [
      (sha: "c2", parents: ["c1"], subject: "second"),
      (sha: "c1", parents: [], subject: "first"),
    ]
    let result = GraphLayout.layout(rows: rows)
    #expect(result.commits.allSatisfy { $0.connectorBelow == nil })
  }

  @Test("Fan-out connector flips to ╭─┤ when the new lane is left of the commit")
  func leftSideFanOutConnector() {
    // Topology:
    //   m0: top-level merge with parents [p1, m]; opens lane 1 for m.
    //   p1: lives on lane 0, parent m is already in lane 1 → lane 0
    //       converges into lane 1.
    //   m:  the lane-1 commit, itself a merge with two fresh parents.
    //       Its first parent grabs lane 1; the second parent grabs the
    //       leftmost free lane — which is lane 0 — so the fan-out
    //       opens to the LEFT.
    let rows = [
      (sha: "m0", parents: ["p1", "m"], subject: "first merge"),
      (sha: "p1", parents: ["m"], subject: "converges into lane 1"),
      (sha: "m", parents: ["q1", "q2"], subject: "merge with left-side fan-out"),
    ]
    let result = GraphLayout.layout(rows: rows)
    #expect(result.commits[2].lane == 1)
    #expect(result.commits[2].connectorBelow == "╭─┤")
  }

  @Test("Merge with first parent already in another lane doesn't duplicate it")
  func noDuplicateLaneForAlreadyWaitedParent() {
    // m has parents [f, a]. After m: lanes = [f, a].
    // Then f's parent root is fresh — assigned to lane 0.
    // Then a's parent root is ALREADY in lane 0 — so lane 1 disappears
    // rather than getting a duplicate "root" assignment.
    let rows = [
      (sha: "m", parents: ["f", "a"], subject: "merge"),
      (sha: "f", parents: ["root"], subject: "first parent"),
      (sha: "a", parents: ["root"], subject: "side branch"),
    ]
    let result = GraphLayout.layout(rows: rows)
    // Side-branch commit's connector should converge into lane 0,
    // not vanish silently. The third commit (`a`) is at lane 1 and
    // its connectorBelow should be present.
    let sideBranch = result.commits[2]
    #expect(sideBranch.lane == 1)
    #expect(sideBranch.connectorBelow != nil)
  }

  @Test("Convergence joins the lane that holds the parent, colored as the ending lane")
  func convergenceTargetsTheParentsLane() {
    // m -> a, b, c; a -> r; b -> s; c -> r. When c's lane ends, r waits in
    // lane 0 and s in lane 1: the join reaches lane 0 and crosses lane 1.
    let rows = [
      (sha: "m", parents: ["a", "b", "c"], subject: "octopus"),
      (sha: "a", parents: ["r"], subject: "a"),
      (sha: "b", parents: ["s"], subject: "b"),
      (sha: "c", parents: ["r"], subject: "c"),
    ]
    let result = GraphLayout.layout(rows: rows)
    let c = result.commits[3]
    #expect(c.connectorBelow == "├─┼─╯")
    #expect(c.connectorGlyphs?.map(\.lane) == [0, 2, 1, 2, 2])
  }

  @Test("A merge whose lane continues still draws the join to a waited parent")
  func joinWhileCommitLaneContinues() {
    // m -> a, b; a -> b, x. b already waits in lane 1; x takes a's lane 0.
    let rows = [
      (sha: "m", parents: ["a", "b"], subject: "merge"),
      (sha: "a", parents: ["b", "x"], subject: "merge into a waited parent"),
      (sha: "b", parents: [], subject: "b"),
      (sha: "x", parents: [], subject: "x"),
    ]
    let result = GraphLayout.layout(rows: rows)
    #expect(result.commits[1].connectorBelow == "├─┤")
    #expect(result.commits[2].lane == 1)
    #expect(result.commits[3].lane == 0)
  }

  @Test("An ending lane joins every waited parent, on both sides")
  func endingLaneJoinsBothSides() {
    // t -> p, a, q; a -> p, q. Both of a's parents already wait.
    let rows = [
      (sha: "t", parents: ["p", "a", "q"], subject: "octopus"),
      (sha: "a", parents: ["p", "q"], subject: "joins both neighbours"),
    ]
    let result = GraphLayout.layout(rows: rows)
    #expect(result.commits[1].connectorBelow == "├─┴─┤")
  }

  @Test("A fan-out and a join share one connector row")
  func fanOutAndJoinShareOneConnector() {
    // t -> x, c; c -> x, n1, n2. x waits in lane 0, n1 continues c's lane
    // 1 and n2 opens lane 2.
    let rows = [
      (sha: "t", parents: ["x", "c"], subject: "merge"),
      (sha: "c", parents: ["x", "n1", "n2"], subject: "joins x and fans out"),
    ]
    let result = GraphLayout.layout(rows: rows)
    #expect(result.commits[1].connectorBelow == "├─┼─╮")
  }

  @Test("Bailing drops a connector wider than maxLanes and keeps the commit row")
  func bailDropsTheOverWideConnector() {
    var rows: [(sha: String, parents: [String], subject: String)] = []
    rows.append(("m", (1...5).map { "p\($0)" }, "octopus"))
    for index in 1...5 {
      rows.append(("p\(index)", [], "parent \(index)"))
    }
    let result = GraphLayout.layout(rows: rows, maxLanes: 3)
    #expect(result.bailed)
    #expect(result.commits.count == 1)
    #expect(result.commits[0].glyphRow == "●")
    #expect(result.commits[0].connectorBelow == nil)
  }

  @Test("An octopus merge within maxLanes keeps its fan-out connector")
  func octopusWithinTheBoundKeepsItsFanOut() {
    let rows = [
      (sha: "m", parents: ["a", "b", "c"], subject: "octopus"),
      (sha: "a", parents: [], subject: "a"),
      (sha: "b", parents: [], subject: "b"),
      (sha: "c", parents: [], subject: "c"),
    ]
    let result = GraphLayout.layout(rows: rows, maxLanes: 3)
    #expect(!result.bailed)
    #expect(result.commits.count == 4)
    #expect(result.commits[0].connectorBelow == "├─╮─╮")
  }
}
