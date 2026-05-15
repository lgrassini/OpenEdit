# OpenEdit — macOS Native App

## Project Overview

A lightweight, native macOS ODT (OpenDocument Text) editor for personal notes and journaling.
The app must feel at home on macOS: minimal, fast, and built with native frameworks only.

---

## Hard Constraints

- **Native only**: Use Swift + AppKit (macOS). No Electron, no Catalyst, no web views.
- **No third-party dependencies**: No Swift Package Manager libraries unless absolutely unavoidable and explicitly approved.
- **Minimum deployment target**: macOS 13 (Ventura), compatible with a 2017 Mac.
- **Xcode version**: Must build cleanly with Xcode 14.3.
- **File format**: ODT (OpenDocument Text) — the app reads and writes valid `.odt` files conforming to the ODF 1.2+ standard.

---

## Core Features

### Text Editing
- Bold, italic, strikethrough
- Font family picker (using system fonts)
- Font size control
- Font color picker (using `NSColorWell` / `NSColorPanel`)
- All styling stored as proper ODF text properties in the `.odt` file

### Document Structure
- Heading levels: H1 through H4 (mapped to ODF `text:h` with `outline-level` attribute)
- Body paragraph style (ODF `text:p`)
- Style picker in the toolbar (e.g. a dropdown: Body / Heading 1 / Heading 2 / Heading 3 / Heading 4)

### Lists
- Unordered (bullet) lists
- Nested bullet lists (at least 3 levels deep)
- Implemented using ODF `text:list` and `text:list-item` elements

#### List usability

Creating a list — auto-detect:
If the user starts a line with - or * followed by a space, the line automatically converts into a bullet list item (the trigger character is removed and replaced with a bullet). Same behavior as Apple Notes.

Creating a list — from selection:
If the user selects one or more lines and clicks the bullet icon in the toolbar, each selected line becomes a list item.

Removing a list — from selection:
If the user selects one or more list items and clicks the bullet icon again (toggle off), the items convert back to normal body paragraphs.

Adding items:
Pressing Return inside a list item creates a new empty item at the same nesting level on the line below.

Exiting the list:
Pressing Return on an empty list item exits the list and creates a normal body paragraph below.

Nesting:
Pressing Tab while the cursor is on a list item indents it one level deeper (creates a nested list).
Pressing Shift+Tab outdents it one level. Maximum nesting depth: 3 levels.

Bullet style per level:

Level 1: •
Level 2: ◦
Level 3: ▪




### Images
- Insert JPG and PNG images via a standard macOS open panel
- Images must be **embedded** inside the `.odt` file (stored in the `Pictures/` folder within the ODT ZIP container, referenced via `draw:frame` / `draw:image` in the content XML)
- Images should be resizable within the document (drag handles or a size input)
- No external image references — all images are self-contained in the file

---

## ODT File Handling

An `.odt` file is a ZIP archive. The app must handle the following entries:

| Entry | Description |
|---|---|
| `mimetype` | Must be first entry, uncompressed: `application/vnd.oasis.opendocument.text` |
| `META-INF/manifest.xml` | Lists all files in the package including embedded images |
| `content.xml` | Main document content (text, styles, images references) |
| `styles.xml` | Document-wide styles |
| `Pictures/` | Folder for embedded images (e.g. `Pictures/image1.png`) |

Use `ZipArchive` via `libcompression` or `Zip` via `NSFileWrapper`+`ZipFoundation`... 
**Preferred approach**: Use `Process` + the system `zip`/`unzip` command-line tools, or implement ZIP read/write using the `libz` (zlib) system library (available on macOS with no extra dependencies) to avoid third-party packages.

All XML must be valid, well-formed, and namespace-correct per the ODF 1.2 specification.

---

## User Interface

### Philosophy
- **Mac-assed app**: follow Apple HIG strictly. Use standard controls. No custom-drawn chrome.
- Minimal toolbar — only what's needed.
- The document window should feel like a writing environment, not a developer tool.

### Layout
- Standard `NSWindow` with a toolbar (`NSToolbar`)
- Main content area: `NSTextView` (or a custom view wrapping it) inside an `NSScrollView`
- No sidebar required in v1

### Toolbar Items (in order)
1. **Style picker** — `NSPopUpButton`: Body / H1 / H2 / H3 / H4
2. **Separator**
3. **Bold** — `NSButton` (toggle), keyboard shortcut ⌘B
4. **Italic** — `NSButton` (toggle), keyboard shortcut ⌘I
5. **Strikethrough** — `NSButton` (toggle)
6. **Separator**
7. **Font** — `NSFontPanel` trigger button (or use system Font menu: ⌘T)
8. **Font size** — small `NSTextField` + stepper, or `NSComboBox` with common sizes
9. **Color** — `NSColorWell`
10. **Separator**
11. **Bullets** — `NSButton` (toggle bullet list on/off for current paragraph)
12. **Increase indent / Decrease indent** — for nested lists
13. **Separator**
14. **Insert Image** — `NSButton`, opens `NSOpenPanel` filtered to JPG/PNG

### Menus
Implement standard macOS menus:
- **File**: New, Open (⌘O), Save (⌘S), Save As (⇧⌘S), Close
- **Edit**: Undo, Redo, Cut, Copy, Paste, Select All
- **Format**: Bold, Italic, Strikethrough, Font (opens NSFontPanel), Colors (opens NSColorPanel)
- **View**: nothing special required in v1

### Autosave / Dirty state
- Show a dot in the close button when there are unsaved changes (standard AppKit behavior via `NSDocument`)
- Prompt to save on close if unsaved changes exist

---

## Architecture

Use `NSDocument`-based architecture (`NSDocument` subclass). This gives you:
- Autosave, versioning, and iCloud compatibility for free in the future
- Correct dirty-state tracking
- Proper file coordination

Suggested classes:
- `ODTDocument: NSDocument` — handles read/write of `.odt` files
- `ODTParser` — parses `content.xml` into an internal model
- `ODTWriter` — serializes internal model back to `content.xml` + ZIP
- `EditorViewController: NSViewController` — owns the `NSTextView` and toolbar logic
- `DocumentModel` — in-memory representation of the document (paragraphs, styles, images)

---

## What to Avoid

- No `WKWebView` or any web-based rendering
- No `NSAttributedString` archiving as a persistence format — always serialize to/from ODT XML
- Do not use deprecated AppKit APIs that were removed before macOS 13
- Do not break the ODT ZIP structure (e.g. `mimetype` must be first and uncompressed)

---

## Native-First Rule

**Before implementing any UI behaviour or action, check whether AppKit already provides it.**

AppKit is rich. Many things that look like features to build are already built:

| Example | Native API |
|---|---|
| Add / Edit / Remove Link | `NSTextView.orderFrontLinkPanel(_:)` + built-in context menu |
| Link styling (colour, underline, hand cursor) | `NSTextView.linkTextAttributes` (temporary attrs, zero storage overhead) |
| Font picker | `NSFontManager.orderFrontFontPanel(_:)` |
| Colour picker | `NSApp.orderFrontColorPanel(_:)` |
| Spell check | Built into `NSTextView` |
| Undo / Redo | `NSUndoManager` via `NSTextView` |
| Find & Replace | `NSTextView.usesFindPanel` |
| Standard Edit actions (Cut/Copy/Paste/Select All) | First-responder action methods on `NSText` |

**The rule:** if a right-click or system menu already shows the desired action, wire a menu-bar item to the same selector via the responder chain (nil target) rather than reimplementing it. Only build custom UI when the native component genuinely cannot meet the requirement.

---

## Testing

- Verify that files saved by this app can be opened in **LibreOffice** and display correctly
- Verify that `.odt` files created in LibreOffice can be opened and edited in this app
- Test embedded images round-trip: insert image → save → reopen → image still present and correct

---

## Workflow Instructions for Claude Code

### Step 1 — Plan first, build second
Before writing any code, produce a numbered implementation plan and stop.
The plan must include:
- A list of all phases/steps in order
- What will be built in each step
- What the deliverable or verification of each step is (e.g. "app compiles and opens a blank window")

**Wait for explicit user approval of the plan before proceeding.**

### Step 2 — Execute one step at a time
After the plan is approved:
- Implement one step at a time
- After completing each step, **stop and write a short summary** of what was done, what files were created or modified, and how to verify it works
- Do not proceed to the next step until the user confirms

### Summary format after each step
```
## ✅ Step N complete — [Step title]

**What was done:**
- ...

**Files created/modified:**
- `path/to/file` — description

**How to verify:**
- ...

**Next step:** [brief description of step N+1]
Proceed? (yes / yes with changes / no)
```

---

## Git & GitHub Workflow

The upstream repository is: **https://github.com/lgrassini/OpenEdit.git**

### Branch strategy
- `main` — stable baseline; only receives merges via reviewed PRs
- `phase-N-<short-title>` — one branch per phase (e.g. `phase-5-bullets-images`)

### Per-phase Git workflow (Step 3 of each phase execution)
After the implementation compiles and the step summary is written:

1. **Commit** all changes on the feature branch with a descriptive message.
2. **Push** the branch to origin.
3. **Open a PR** against `main` using `gh pr create` with:
   - A short title (≤ 70 chars): `Phase N — <title>`
   - A body listing what was built and how to verify it
4. **Post the PR URL** in the conversation so the user can review and merge.

Do **not** merge the PR yourself. Wait for explicit user confirmation before starting the next phase.

### First commit
Phases 1–4 were committed directly to `main` as the initial baseline (commit `295c79c`).
All subsequent work follows the branch + PR workflow above.

---

## Out of Scope (v1)

- Tables
- Spell check (AppKit's built-in `NSTextView` spell check is fine)
- Export to PDF or other formats
- Tags, search, or note organization
- Cloud sync
- Dark mode customization (respect system appearance automatically via AppKit)
