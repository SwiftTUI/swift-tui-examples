# GifEditor authoring glossary

Shared vocabulary for GifEditor design work. Each term describes current code.

- **Document lifecycle**: This lifecycle tracks an authoring document from
  launch or recovery through New, Open, and Save. It also protects unsaved
  work. A document can be untitled, project-backed, or imported from a GIF.
  GIF export does not change the document identity.
  _Avoid_: file lifecycle, editor session lifecycle.
- **Editing session**: This session contains the active document, authoring
  context, and undo history. These parts change or restore as one unit. The
  session excludes window state and document-lifecycle workflow.
  _Avoid_: document mutation, editor model.
- **Editing intent**: This semantic request changes or navigates an Editing
  session. A key, menu, pointer, or other input can create the request.
  Document-lifecycle and display-only commands are not Editing intents.
  _Avoid_: editor command, key action.
- **Document ingestion**: This process recognizes external bytes as a
  GifEditor document. It also interprets the source metadata. Project ingestion
  restores the authoring structure. GIF ingestion imports the animation. Byte
  transport and host-specific error text are outside this process.
  _Avoid_: document loading, document import, file decoding.
- **Project backing**: This durable project location gives Save its write-back
  authority. Untitled, recovered, and GIF-ingested documents have no Project
  backing. Source provenance does not give this authority.
  _Avoid_: document backing, document path.
