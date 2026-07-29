# MrkdwnMermaid syntax profile

This file is the language contract for the first release. Fixtures under
`Tests/MrkdwnMermaidTests/Fixtures/` exercise a minimal positive source plus an
advanced, malformed, unsupported, wide-label, cyclic, and Unicode matrix for
every family under both ambiguous-width policies.

Statements may be separated by newlines or semicolons. `%%` starts a comment
outside a quoted string. Labels may be quoted. HTML line-break entities and
the common `&lt;`, `&gt;`, `&amp;`, `&quot;`, and `&#39;` entities are
decoded as label text; HTML is never executed.

## Flowcharts

Accepted headers are `graph` and `flowchart`, with `TD`, `TB`, `BT`, `LR`, or
`RL`. Node identifiers may use bare, rectangular, rounded, stadium,
subroutine, database-like, or diamond brackets. Relations recognize the
following terminal-rendered shapes without flattening: rectangle (`A[text]`),
rounded (`A(text)`), stadium (`A([text])`), subroutine (`A[[text]]`), cylinder
(`A[(text)]`), circle (`A((text))`), diamond (`A{text}`), hexagon
(`A{{text}}`), and asymmetric (`A>text]`).

Relations recognize solid (`---`, `-->`, `<--`, `<-->`), dotted (`-.-`,
`-.->`, `<-.->`), thick (`===`, `==>`, `<==>`, `<==`), circle (`--o`,
`---o`, `o--`, `o---`, `o--o`, and mixed circle/cross forms), and cross
(`--x`, `---x`, `x--`, `x---`, `x--x`) spellings plus an optional
`|label|`. Connector matching is longest-first, so compact Mermaid such as
`A---oB` retains `B` as the destination and the circle as the endpoint.

Subgraph declarations and direction changes are recognized. The first release
flattens subgraph geometry while preserving its label as a note. Visual style
and class directives are ignored with a diagnostic. Click directives are
never executed and also produce a diagnostic. Nodes are placed exactly once
in a stable topological traversal. Outgoing routes remain attached to their
source card; the requested axis selects their direction marker and ordering,
and cycles and parallel edges remain explicit.

## States

Accepted headers are exactly `stateDiagram` and `stateDiagram-v2`. State
aliases in both Mermaid orders, descriptions, transition labels, start/end
markers, `<<choice>>`, and direction are recognized. Composite braces are
flattened; all retained state and transition text remains visible. Missing or
extra composite braces are malformed rather than silently recovered.

## Sequences

`participant` and `actor` declarations, `as` labels, solid/dotted arrow
variants, message labels, notes, autonumber, and loop/alt/opt/par/critical/break
section labels are retained. When the offered width can hold the participant
lanes, the terminal presentation uses aligned participant headers, persistent
lifelines, and routed messages. Narrow widths use a folded lifeline geometry
plus a participant key. Both forms retain every message and label.

## Classes and ER

Class declarations, brace members, colon members, annotations, and inheritance
(`<|--`, `--|>`), realization (`<|..`, `..|>`), composition (`*--`, `--*`),
aggregation (`o--`, `--o`), dependency (`<..`, `..>`), and association
(`-->`, `<--`, `--`, `..`) relations are accepted.

ER entity brace attributes and all symbolic crow-foot combinations are
accepted. A left marker is `|o`, `||`, `}o`, or `}|`; a right marker is `o|`,
`||`, `o{`, or `|{`; and the middle is identifying `--` or non-identifying
`..`. Members and attributes remain literal lines inside the entity card.
Each class or entity card is placed once in shared topology; its authored
relations are attached immediately below that source card, with endpoint
markers, cycles, and parallel relations retained.

## XY

`xychart-beta` and `xychart` accept a quoted title, categorical bracket-list
`x-axis`, numeric `y-axis MIN --> MAX`, and numeric bracket-list `bar` and
`line` series. Axis bounds must both be finite and strictly increasing.
Every retained series must have the same observation count as the categorical
axis, or as the first series when no categorical axis is authored. A
mismatched series is diagnosed and omitted; a chart with no matching series
is malformed rather than padded with invented values.
When there are more observations than plot columns, geometry is aggregated
into deterministic buckets. Every x label, y bound, and numeric value is also
retained in wrapped textual legends, so aggregation does not hide authored
data.

## Recovery

An unsupported family and a supported family with no renderable content are
unavailable. Recognized but deliberately omitted constructs produce partial
fidelity. Flowcharts may safely omit an unreadable or unsupported statement
at any position and report `contentElided`; relation chains preserve their
first relation, so callers should use one relation per statement when complete
fidelity is required. State, sequence, class, and ER parsing is deliberately
stricter: exactly one unreadable final statement may be salvaged as partial.
An unreadable statement before the final position, a second structural
failure, or an unclosed strict-family body makes the diagram unavailable.

Connector, colon, semicolon, comment, and quote recognition is aware of quoted
strings, escapes, and every accepted balanced node shape, including asymmetric
`id>label]` nodes. Connector-looking text inside a label is never treated as
topology.
