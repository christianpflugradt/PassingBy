# Product Specification

## 1. Purpose of this document

This document is the authoritative product specification for the application.

It serves four purposes:

1. guide implementation,
2. constrain design and architecture decisions,
3. enable implementation reviews against explicit requirements,
4. prevent feature creep and technically correct but product-inappropriate solutions.

An implementation is considered conformant only if it satisfies both:

- the explicit functional requirements, and
- the product principles and interaction expectations defined in this document.

When an implementation choice is not explicitly covered, the product principles in this specification shall be used to resolve the ambiguity.

---

# 2. Product vision

The application is a small, native macOS workspace for temporary information that needs to remain visible and accessible while it is relevant.

It combines three kinds of short- to medium-lived information:

- Notes
- To-dos
- Appointments

The application is deliberately not intended to replace a full calendar, project-management system, long-term knowledge base, or advanced to-do manager.

Its purpose is to reduce friction around information that is currently handled through:

- temporary text files,
- ad-hoc notes,
- lightweight to-do lists,
- calendar entries created only as reminders.

The application should feel closer to an external working memory than to a productivity suite.

---

# 3. Core user value

The product should make it easy to:

- capture temporary information,
- keep current information visible,
- distinguish different personal or work contexts,
- remove information from active view once it is no longer relevant,
- avoid manually maintaining files, folders, calendar entries, or complex to-do structures.

The application should require very little organisational effort.

The user should not need to repeatedly decide:

- where a file belongs,
- which folder should contain something,
- whether a tag hierarchy is correct,
- whether information should be moved somewhere else,
- whether an item needs elaborate metadata.

The system should support lightweight organisation without turning organisation itself into work.

---

# 4. Product principles

These principles are normative.

If a feature or implementation decision conflicts with them, the implementation should be reconsidered even if it is technically functional.

## 4.1 Temporary by default

The application is designed primarily for information that matters now or in the foreseeable future.

It is not a permanent knowledge-management system.

## 4.2 Low organisational overhead

The application must minimise maintenance effort.

Avoid introducing:

- folders,
- hierarchies,
- nested structures,
- mandatory categorisation,
- multi-tag systems,
- advanced project organisation.

## 4.3 Native macOS behaviour

The application should behave like a well-designed macOS desktop application.

Native interaction patterns should be preferred over custom interaction patterns unless a custom interaction provides a clear product benefit.

## 4.4 Immediate persistence

The user should never need to think about saving.

All user changes must be persisted automatically.

There must be no normal workflow containing a Save button or a "Save changes?" confirmation.

## 4.5 Visibility over workflow management

The product should help the user see what currently matters.

It should not attempt to manage workflows, projects, productivity methodologies, prioritisation frameworks, or planning systems.

## 4.6 Simple models over flexible complexity

Prefer one simple, understandable concept over several configurable alternatives.

Examples:

- one optional category instead of multiple categories,
- one global category filter instead of separate filters per screen,
- one date instead of start/end time modelling,
- one state transition for to-do completion.

## 4.7 No speculative features

Features should exist because they serve the defined product use case.

The implementation must not add functionality merely because similar applications commonly provide it.

---

# 5. Platform

The application is a native macOS desktop application.

Initial target platform:

- macOS only

No web application, mobile application, server component, or browser interface is part of the initial scope.

---

# 6. Technology expectations

The preferred application stack is:

- Swift
- SwiftUI
- AppKit where native macOS capabilities require it
- TextKit or equivalent native text infrastructure for the Markdown editor
- local persistent storage

SQLite is an acceptable and preferred persistence mechanism.

The product specification does not require a specific internal architecture beyond these constraints.

Architecture should favour:

- simplicity,
- local reliability,
- maintainability,
- clear separation of domain logic and UI,
- deterministic behaviour,
- testability.

---

# 7. Data ownership and persistence

All application data is stored locally.

Version 1 has:

- no user accounts,
- no server,
- no cloud dependency,
- no collaboration,
- no network dependency.

The application must remain fully functional offline.

## 7.1 Saved-data compatibility

An app update must load workspace data saved by older versions without requiring user action or losing existing items or settings. Every newly added persisted field must have a sensible default when absent. Fields the current app does not recognize must not prevent loading otherwise valid data.

After loading older data, the app must continue saving it normally, including any new values the user sets. A missing field must not cause unrelated saved content to be reset or discarded. If a file is genuinely unreadable, the app must report the failure rather than silently replace it with an empty workspace.

Changes to persisted models must be checked with tests that load representative older data and verify that existing content survives a save and reload.

---

# 8. Primary navigation

The application uses two navigation levels: a sidebar and one main content area. There is no permanent middle list or detail inspector.

The sidebar contains:

- Dashboard
- To-dos
- Appointments
- Help
- every individual Note as a direct sidebar entry, followed by New Note
- Settings

Selecting a Note opens its dedicated editor in the full main content area. There is no separate Notes list screen.

The sidebar is a compact, icon-only navigation rail with tooltips for every destination and Note title. It has no Notes collapse control. Settings is anchored separately at the bottom. Icons are comfortably clickable, clearly indicate selection, and use native SF Symbols. Notes may have a restrained category-color dot.

Primary navigation is keyboard-first: `Cmd+1` opens Dashboard, `Cmd+2` To-dos, `Cmd+3` Appointments, `Cmd+4` through `Cmd+9` the first six Notes in sidebar order, `Cmd+0` Help, and `Cmd+,` Settings. Further Notes remain accessible from the sidebar. The native menu exposes these commands. `Option+Cmd+S` focuses the current sidebar destination; Up/Down moves between entries, Enter opens an entry and focuses its main content, and Escape returns to the previous control. The sidebar is outside the main content Tab sequence.

Dashboard is the default starting view when no relevant navigation state can be restored. The application should restore the user's last relevant navigation state when practical.

A dedicated Archive screen is not part of Version 1.

---

# 9. Global category context

The application has one global category filter.

It affects:

- Notes
- To-dos
- Appointments

The same global filter is presented contextually on Dashboard, To-dos, and Appointments. It must not consume a global toolbar row while an individual Note, Help, or Settings is open. Filtered Note entries and restrained category dots make the active context apparent in the sidebar.

Available selections are:

- All
- each configured category

Example:

```text
All
Private
Consid
Customer A
```

## 9.1 Behaviour

When a category is selected, only items assigned to that category are shown.

When `All` is selected, all items are shown, including uncategorized items. Uncategorized items are not shown when a configured category is selected.

The currently selected global category context should be persisted and restored on application restart.

`Option+Cmd+F` opens a native category chooser from any screen, including an individual Note. Up/Down moves through All and the configured Categories, Enter applies the selection, and Escape cancels. Focus returns to the previous control, or to the current main content if filtering removed that control. The global filter is outside the main content Tab sequence; item Category assignment controls remain in their forms’ Tab sequences.

The UI must make an active filter obvious enough that the user does not mistakenly believe filtered-out items have disappeared.

The filter shows its selected value without a redundant caption in the page header.

When 1–4 Categories are configured, Dashboard, To-dos, and Appointments present this filter as one native segmented control containing `All` and every configured Category. Switching takes one click and the selected segment is immediately apparent. With no configured Categories or with five or more, the filter uses a compact picker. The presentation changes automatically without changing the selected filter or any item data. There is no maximum number of Categories. `All` is a filter state, not a stored Category.

An individual Note's Category control remains an ordinary picker because it assigns an item property rather than filtering the workspace.

## 9.2 No local category filters

Version 1 must not provide separate category filters for Notes, To-dos, or Appointments. Showing the same global filter on several relevant screens does not create separate filter states.

The global filter is the only category filter.

---

# 10. Categories

Categories provide lightweight contextual separation.

Typical examples include:

- Private
- Employer
- Customer

## 10.1 Cardinality

Each item may have:

- no category, or
- exactly one category.

Multiple categories per item are explicitly out of scope.

The domain model shall therefore represent this as an optional single category reference, not as a collection.

Example:

```text
categoryId: CategoryId?
```

not:

```text
categories: [Category]
```

## 10.2 Category management

Categories are managed only in Settings.

Users can:

- create a category,
- rename a category,
- assign a color,
- delete a category.

Users must not be able to create categories inline while editing a Note, To-do, or Appointment.

Item editors may only choose from existing categories.

## 10.3 Category deletion

Deleting a category must not delete associated Notes, To-dos, or Appointments.

Affected items become uncategorized.

Equivalent domain behaviour:

```text
categoryId = null
```

---

# 11. Notes

## 11.1 Purpose

Notes are temporary working documents containing arbitrary Markdown text.

They are intended for information such as:

- links,
- code snippets,
- temporary research,
- work-in-progress information,
- scratch notes,
- contextual material,
- ideas,
- reference material that is currently useful.

Notes may be short or long.

The product does not prescribe how many Notes the user should maintain.

A user may keep:

- one long-lived Note,
- several long-lived Notes,
- temporary Notes,
- any combination of these.

## 11.2 Note model

A Note contains at least:

```text
id
title
contentMarkdown
optional category
createdAt
updatedAt
icon from a curated native SF Symbols set
```

## 11.3 Note lifecycle

Notes are not archived.

Notes do not have a Completed state.

Notes do not participate in retention rules.

A Note remains present until explicitly deleted by the user.

Its contents may change indefinitely.

This is intentional.

The application must not treat content changes as versions, archive events, or retention events.

## 11.4 Creating Notes

The user must be able to create multiple Notes.

Each Note is independently selectable and editable.

Every Note appears directly in the sidebar and opens in a dedicated editor screen. The editor gives most of the main content area to the Markdown source, without a permanent list or inspector beside it.

Its compact header contains the selectable Note icon, editable title, category picker, and deletion action in one row above the editor. New Notes default to `doc.text`; existing Notes without an icon also use that symbol. Clicking the icon opens a compact picker of curated SF Symbols. The editor begins directly below the header and uses the remaining space.

The picker offers 49 recognizable everyday symbols in a compact 7 × 7 grid. A Note icon expresses the user-defined subject or purpose of that Note. Symbols Passing By deliberately uses for its own navigation, actions, or application concepts must not also be selectable Note icons. If a symbol is removed from the curated choices later, existing Notes using it retain and display their saved icon; removal affects only new assignments.

Creating a Note opens it and focuses its title. Keyboard focus proceeds from title to category to editor. Within the editor, Tab inserts indentation and Shift+Tab outdents where applicable without moving focus to surrounding controls. Escape does not unexpectedly leave the editor. `Shift+Cmd+T` returns focus to the Note title.

## 11.5 Deleting Notes

Notes may be explicitly deleted.

Deleting a Note requires explicit confirmation, whether triggered by its trash action or `Cmd+Delete`.

A Trash system is not required.

A Note archive is not required.

---

# 12. Markdown editor

Notes use Markdown as their editing format.

## 12.1 Editing model

Markdown is edited directly as source text by default. The editor is not a WYSIWYG editor and does not generally render Markdown into rich text while editing. Syntax normally remains visible. Deliberate, narrowly specified interactive exceptions are allowed when they make a frequent action easier, provided the Note remains editable and stored as Markdown source.

Task-list checkbox markers in unordered and ordered lists are one such exception: `[ ]`, `[x]`, and `[X]` appear as clickable checkboxes because clicking is simpler than editing the marker to toggle its state. A click changes the corresponding source marker between `[ ]` and `[x]`. Copy and paste preserve literal Markdown. Other Markdown syntax remains visible; highlighting may use semantic color and font traits without changing the underlying source. Links remain editable as source; a deliberate Command-click may open a recognized URL.

Example:

```markdown
# Heading

- First item
- Second item

**Important**

`inline code`
```

## 12.2 Syntax highlighting

The editor should visually distinguish common Markdown syntax.

At minimum, syntax highlighting should support:

- headings,
- unordered list markers,
- ordered list markers,
- bold syntax,
- italic syntax,
- links,
- inline code,
- fenced code blocks,
- blockquotes.

The purpose of highlighting is readability, not rendering.

## 12.3 Editor behaviour

The editor should support normal native text-editing expectations including:

- selection,
- keyboard navigation,
- copy,
- cut,
- paste,
- Undo,
- Redo,
- scrolling,
- standard macOS text interaction.

Notes use standard native macOS text editing where practical. Undo and Redo support multiple edits during the active editing session; their history is not retained across application restarts. Find searches the open Note, and native Find and Replace may be available where the macOS text system provides it naturally.

Native spell checking may indicate possible errors. Automatic spelling correction, Smart Quotes, and Smart Dashes are off by default so literal Markdown source is preserved. The editor remains compatible with native macOS Dictation when it is available.

Notes use spaces for indentation. Tab indents and Shift-Tab outdents using the configured width of 2, 4, or 8 spaces; the default is 4. Line numbers are configurable and shown by default. Native spell checking is on by default. Automatic correction, Smart Quotes, and Smart Dashes are off by default, and each may be enabled in Settings.

Large code blocks and reasonably large Notes must remain usable.

---

# 13. To-dos

## 13.1 Purpose

To-dos represent concrete things the user expects to perform in the relatively near future.

To-dos should remain intentionally lightweight.

## 13.2 To-do model

A To-do contains at least:

```text
id
title
optional description
optional category
createdAt
completedAt
```

`completedAt` is nullable.

## 13.3 To-do fields

Required:

- title

Optional:

- description
- category

To-dos have no:

- due date,
- due time,
- priority,
- subtasks,
- recurrence,
- project assignment.

## 13.4 To-do states

A To-do is either:

- open
- completed

Completed To-dos are treated as archived from the active-to-do perspective.

## 13.5 Completing a To-do

The user must be able to mark an open To-do as completed.

The To-do must immediately leave the default active-to-do list.

## 13.6 Showing completed To-dos

The To-dos screen includes a control similar to:

```text
Show archived
```

or equivalent wording.

When disabled:

- only open To-dos are shown.

When enabled:

- completed To-dos are also visible.

Completed To-dos should be clearly distinguishable from open To-dos.

## 13.7 Restoring To-dos

A completed To-do may be restored to open state.

Restoration must:

- clear the completed state,
- make the To-do active again,
- prevent retention deletion.

## 13.8 To-do retention

Completed To-dos are retained for a configurable duration.

After the configured retention period expires, they may be permanently deleted.

Retention applies only to completed To-dos.

Open To-dos must never be deleted by retention logic.

---

# 14. Appointments

## 14.1 Purpose

Appointments are lightweight time-related entries for events or dates the user wants to keep visible.

Typical examples:

- user groups,
- important appointments,
- inspections,
- planned office days,
- future events,
- reminders tied to a calendar date.

Appointments intentionally model less information than calendar events. They are not intended to evolve into a full calendar; calendar views and calendar management remain out of scope.

## 14.2 Appointment model

An Appointment contains at least:

```text
id
title
date
optional description
optional category
createdAt
passedAt or equivalent derived state
```

## 14.3 Appointment fields

Required:

- title
- date

Optional:

- description
- category

Version 1 has no structured field for:

- time,
- start time,
- end time,
- duration,
- timezone,
- recurrence,
- reminder.

If a time is relevant, the user may write it in the description.

Example:

```text
18:00
Moderate User Group event
```

---

# 15. Appointment display modes

The Appointments screen supports exactly two primary display modes:

- Chronological
- By Category

The user can switch between them.

The selected mode should preferably be persisted.

## 15.1 Chronological mode

All matching Appointments are displayed in chronological order.

The view must provide access to all matching Appointments.

The configured per-category display limit must not truncate this view.

The user must be able to see the complete set of matching Appointments here.

## 15.2 By Category mode

Appointments are grouped by category.

Category section headings should be clearly stronger than Appointment rows and show the category color when there is one.

Example:

```text
Private
  Dentist
  Main inspection

Employer
  User Group
  Internal workshop

Customer
  Architecture workshop
```

Items inside each group are sorted chronologically.

Uncategorized Appointments should appear in a dedicated uncategorized group when applicable.

## 15.3 Relative date presentation

Where useful, the UI should provide relative date information such as:

```text
Today
Tomorrow
in 4 days
next week
```

The actual calendar date should remain accessible or visible.

Relative descriptions must not replace the underlying date value.

---

# 16. Upcoming Appointment visibility

Settings contain a global maximum upcoming Appointments per Category, default 5, and a future time horizon in integer days, default 14. The horizon can be set from 1 to 365 days. Today through the day at the configured horizon are eligible.

These settings control compact upcoming presentation, including Dashboard and grouped Appointments. They do not delete or modify Appointments. Chronological mode continues to expose the complete matching Appointment collection.

The maximum is one configurable value:

```text
Maximum upcoming Appointments per category
```

This controls compact grouped presentation.

Example:

```text
5
```

A separate value per category is not supported.

The setting is global.

## 16.1 Behaviour

In grouped presentation, only the nearest configured number of Appointments within the future horizon may initially be shown per category.

If more matching Appointments exist, the interface must make that fact clear.

An affordance such as:

```text
Show 4 more…
```

may be provided.

The full chronological Appointment view must never lose access to these additional Appointments.

The limit is a presentation constraint, not a data constraint.

---

# 17. Passed Appointments

An Appointment becomes passed when its calendar date is before the current local calendar date.

The application should not depend on a configured event time because Version 1 has no time field.

Passed Appointments disappear from the normal active Appointments view.

They remain retained according to Appointment retention settings.

The Appointments screen includes a control similar to:

```text
Show past
```

When disabled, only today and future Appointments are shown. When enabled, retained passed Appointments are also visible in the existing Appointments screen. Passed Appointments should be clearly distinguishable from active Appointments and remain editable. Changing a passed Appointment to today or a future date naturally makes it active again.

---

# 18. Appointment retention

Passed Appointments are retained for a configurable duration.

After the configured retention period expires, they may be permanently deleted.

Future Appointments must never be deleted through retention.

The retention period should be independent from To-do retention.

---

# 19. Retention settings

Settings contain separate retention configuration for:

- completed To-dos,
- passed Appointments.

Notes have no retention setting.

The implementation must not introduce Note retention.

Reasonable representation may include durations such as:

```text
7 days
14 days
30 days
90 days
Never
```

Exact available values may be refined during implementation, but the following semantics are mandatory:

- each supported item type has its own independent retention setting,
- `Never` may be supported,
- retention affects only already-completed or already-passed items,
- active content is never deleted by retention.

---

# 20. Auto-save

All editable application content is automatically persisted.

This includes:

- Note title,
- Note content,
- Note category,
- Note icon,
- To-do data,
- Appointment data,
- category assignments,
- Settings.

For text-heavy fields, persistence may use a short debounce.

The user must not lose substantial content if:

- the window closes,
- the app quits normally,
- navigation changes.

No explicit Save action should be required.

---

# 21. Settings

Settings contain six vertical sections: Dashboard, Categories, To-dos, Appointments, Notes, and Security. Controls remain inline in one calm, native screen. Keyboard shortcut documentation belongs on Help.

## 21.1 Dashboard

Users can configure the maximum number of To-dos and Appointments shown on Dashboard independently, from 1 to 10. Both default to 4. These limits affect only Dashboard presentation, after its existing filtering and ordering rules; they do not change the full To-dos or Appointments views, stored data, retention, or Category filtering semantics. Changes take effect immediately.

## 21.2 Categories

Category management uses a list of Categories and an editor for the selected Category. Users can create, rename, assign a color, and delete Categories.

One global Default Category is used when creating a new Note, To-do, or Appointment. It may be any configured Category or Uncategorized; Uncategorized is the initial default. Changing this setting does not change existing items.

One optional Scheduled Default Category may override the fallback Default Category on selected weekdays during one local time range. The scheduled choice may explicitly be Uncategorized; before a choice is made, the schedule is inactive. The start time is inclusive and the end time exclusive. A schedule with no selected days or an end time at or before its start is inactive. Overnight ranges are not supported. The scheduled setting is off by default; its initial days are Monday–Friday, 08:00–17:00.

The override is resolved only when a new item is created, using the current local creation time. An Appointment's own date does not affect its initial Category. Existing items are never recategorized when time passes. Deleting a referenced Category safely clears its default reference; deleting a scheduled Category also disables that override.

## 21.3 To-dos

Users can configure completed To-do retention.

Scheduled To-dos are managed only here. A schedule has a static To-do title, one selected Category or an explicit Uncategorized choice, a weekly or monthly recurrence, and a persisted next occurrence. Weekly choices are every week or every two weeks on one selected weekday; the first occurrence anchors the two-week cadence. Monthly choices are the first day, first weekday, last day, or last weekday of the month, where weekday means Monday through Friday. Schedules can be created, viewed, and deleted, but not edited or paused. The list identifies schedules by title and provides a compact read-only view of their configuration and next occurrence.

When a schedule is due, the app creates one ordinary To-do with its saved title and Category; the Default Category is not used. If several occurrences were missed, it creates only the most recent due one and advances the next occurrence to the first future date. Evaluation on launch and while the app remains open is idempotent across repeated checks and restarts. Earlier generated To-dos do not affect future generation; deleting a schedule leaves them untouched. Deleting a Category changes schedules that selected it to Uncategorized, consistent with existing item references.

## 21.4 Appointments

Users can configure passed Appointment retention, the global maximum upcoming Appointments per Category, and the future time horizon. This section also provides a simple TSV bulk import.

Each non-empty TSV line contains `DD.MM.YYYY`, a required title, and an optional description, separated by tabs. An empty description may be omitted or represented by a trailing tab. The user selects one existing Category or Uncategorized for the whole import. The app previews all parsed Appointments and reports invalid rows before confirmation; invalid or empty files cannot be imported. Confirmed imports append ordinary Appointments, with no automatic duplicate detection or merging. Import is one-time ingestion, without synchronization with the TSV file.

## 21.5 Notes

Users can configure line numbers, indent width, spell checking, automatic correction, Smart Quotes, and Smart Dashes. Line numbers and spell checking default on. Indent width defaults to 4 spaces. Automatic correction, Smart Quotes, and Smart Dashes default off.

## 21.6 Security

Optional global App Lock protects app content from casual exposure. It is off by default and uses native macOS authentication, including Touch ID when available through the system. With App Lock enabled, every fresh launch starts locked and no private app content is visible until authentication succeeds. `Shift+Cmd+L` and Lock Now in Settings lock the app immediately.

Users may optionally lock after Passing By has remained inactive for a configured 1–120 minutes (default 5). This option is off by default. Inactive means the application is not active; keyboard and mouse idle time while it remains active does not count. Returning before the delay cancels the pending lock. Category-specific privacy filtering is outside Version 1.

---

# 21A. Help and keyboard commands

The dedicated Help screen is informational and lists all supported application shortcuts. `Cmd+0` opens it. Shortcuts appear in the native macOS menu where applicable.

`Cmd+N` creates a To-do on To-dos, an Appointment on Appointments, and a Note on Dashboard, Help, Settings, or an open Note. `Shift+Cmd+N` creates a Note from anywhere. The sidebar New Note button has the same action.

`Cmd+Delete` deletes a current or selected item only when its target is unambiguous. Note and Appointment deletion always require confirmation. `Shift+Cmd+T` focuses the open Note title.

`Shift+Cmd+L` locks Passing By when App Lock is enabled.

---

# 22. Search

Global search is not part of the required Version 1 scope.

It may be considered later if real usage demonstrates a need.

The implementation must not delay or complicate Version 1 in order to support future global search.

---

# 23. Quick Capture

Quick Capture is explicitly not part of Version 1.

Version 1 has no requirement for:

- global keyboard shortcuts,
- floating capture windows,
- menu-bar capture,
- alternative creation workflows.

All content creation occurs through the main application UI.

---

# 24. Dashboard

Dashboard is the deliberately minimal "what matters now" starting view.

In Version 1 it surfaces open To-dos and upcoming Appointments under the current global category context, up to the respective maximums configured in Settings. It does not surface recent Notes.

To-dos appear in the left column and Appointments in the right. The columns form one balanced composition with aligned headings, comfortable spacing, and a restrained maximum content width. They are sections, not cards or widgets. To-do rows contain only a completion control, an applicable Category color indicator, and the title. Appointment rows put useful relative time first, keep the absolute date visible but secondary, then show the title on a second line; they also show an applicable Category color indicator. For example, `Today · 27 Sep` above `New Date`.

It is a short path to current items, not an analytics or widget dashboard. A restrained status bar at the bottom shows exactly three lifetime values: Days Passed, To-dos Completed, and Appointments Passed. Days Passed counts local calendar days inclusively from the first persisted statistics start date. Completed To-dos and passed Appointments contribute while retained, and their lifetime totals survive normal retention. Explicit deletion removes an item from the lifetime total if it has not already been removed by retention. These values describe usage history rather than productivity. The Dashboard must not introduce cards, charts, trends, scores, or other dense overview furniture. To-dos, Appointments, and individual Notes remain directly accessible from the sidebar.

---

# 25. Native macOS expectations

The application should follow common macOS conventions where applicable.

Expected behaviour includes:

- native window handling,
- standard keyboard navigation,
- light and dark appearance compatibility,
- standard menu behaviour,
- standard text editing,
- Undo and Redo,
- standard scrolling,
- context menus where appropriate,
- sensible focus behaviour,
- restoration of practical UI state.

Custom UI components should not unnecessarily imitate web application patterns.

---

# 26. Information density

The application should favour calm readability and clarity. Empty space may create hierarchy, while lists should still be easy to scan.

It should avoid:

- oversized cards,
- space that hides current items or forces unnecessary scrolling,
- decorative dashboards,
- large empty panels,
- visually heavy controls.

To-do and Appointment lists occupy the main content area rather than sharing it with a permanent inspector. Rows should have readable typography and enough vertical space that roughly 8–10 To-dos at a typical window size feel natural, without becoming oversized cards.

A categorized To-do or Appointment should show its category color as a small indicator; uncategorized items remain neutral. Chronological Appointments must not rely on category text alone for this cue.

This is a desktop productivity tool, not a marketing interface.

---

# 27. Creation and editing UX

Creating and editing an item should require as little ceremony as practical.

Required fields must remain minimal.

Avoid multi-step creation wizards.

To-dos and Appointments are scanned and acted on in their main lists; their creation and editing use temporary sheets, popovers, or equivalent native UI rather than permanent editing panes. A Note opens directly in its dedicated main-content editor and has no permanent list or inspector alongside it.

Settings are intentionally exempt: configuration controls remain inline on the Settings screen.

The primary actions should be discoverable but not visually dominant.

---

# 28. Error handling

Normal user operations should fail gracefully.

The application should not silently lose user-created content.

Persistence failures should be surfaced clearly if they occur.

Destructive operations should be deliberate.

---

# 29. Data integrity rules

The following invariants must always hold.

## 29.1 Category invariants

An item references zero or one existing category.

Deleting a category must not delete an item.

## 29.2 To-do invariants

An open To-do has no `completedAt`.

A completed To-do has a completion timestamp or equivalent durable completed state.

Restoring it removes that state.

## 29.3 Appointment invariants

A future or current Appointment must not be deleted by retention for passed Appointments.

A passed Appointment is determined from its calendar date, not an arbitrary display state.

## 29.4 Note invariants

Notes have no archive state.

Notes have no completion state.

Notes have no retention-based deletion.

---

# 30. Explicit non-goals

Version 1 must not implement:

- Quick Capture
- Note archive
- Note history
- Note versioning
- Note retention
- folders
- projects
- nested Notes
- multiple categories per item
- inline category creation
- to-do priorities
- to-do due dates
- subtasks
- recurrence on individual To-dos
- recurring Appointments
- structured event times
- event duration
- timezone handling
- reminders
- notifications
- calendar views
- calendar synchronisation
- Nextcloud integration
- cloud synchronisation
- user accounts
- sharing
- collaboration
- attachments
- WYSIWYG Markdown
- Markdown preview
- statistics beyond the three Dashboard lifetime values
- productivity scores
- gamification
- Kanban boards
- analytics or widget dashboards
- plugin architecture.

These exclusions are deliberate product decisions, not missing implementation work.

An implementation agent must not add them unless this specification is explicitly revised.

---

# 31. Product-quality acceptance criteria

Functional correctness alone is insufficient.

A conforming implementation should also satisfy the following qualitative criteria.

## 31.1 Low friction

Common operations must feel immediate.

Examples:

- switching Notes,
- completing a To-do,
- restoring a To-do,
- changing a category,
- switching Appointment views,
- changing the global category context.

None of these should require unnecessary navigation.

## 31.2 Predictability

The same concept must behave consistently throughout the application.

Examples:

- global category context means the same thing everywhere,
- categories always come from Settings,
- auto-save applies everywhere,
- archived/completed content is never mixed ambiguously with active content.

## 31.3 Minimal cognitive load

The UI should not expose implementation concepts or unnecessary configuration.

The user should not need to understand database states, archival machinery, or retention jobs.

## 31.4 Clear active versus inactive state

The user must be able to distinguish:

- open versus completed To-dos,
- upcoming versus passed Appointments,
- active global category filtering.

## 31.5 No accidental feature expansion

A technically impressive implementation that adds complexity beyond this specification should be considered worse, not better.

---

# 32. Verification checklist

A reviewer should explicitly verify all of the following.

## Product structure

- [ ] Application has Dashboard, To-dos, Appointments, Help, individual Notes, and Settings in a two-level sidebar and content layout.
- [ ] Dashboard shows no more than the configured maximum of open To-dos in the left column and upcoming Appointments in the right, without recent Notes or analytics widgets.
- [ ] Dashboard maximums are independently configurable from 1 to 10 in Settings, default to 4, and apply after existing relevance, filtering, and ordering rules without changing full views or stored items.
- [ ] Dashboard shows only Days Passed, To-dos Completed, and Appointments Passed in a restrained status bar; the totals survive retention and remain hidden while locked.
- [ ] Dashboard Appointment rows show relative time prominently and the absolute date secondarily.
- [ ] Each Note opens directly from the sidebar in the main content area.
- [ ] The compact icon sidebar has tooltips, Notes do not collapse, and Settings is anchored at the bottom.
- [ ] No dedicated Archive area exists unless explicitly justified by revised specification.
- [ ] One global category context exists.

## Categories

- [ ] Categories are managed in Settings.
- [ ] Inline category creation is impossible.
- [ ] Each item has zero or one category.
- [ ] Categorized To-dos and Appointments show a restrained color cue; category group headings also show color.
- [ ] Multiple categories cannot be assigned.
- [ ] Deleting a category preserves associated items.
- [ ] Deleted-category items become uncategorized.

## Notes

- [ ] Multiple Notes can be created.
- [ ] Notes contain title and Markdown content.
- [ ] Notes persist a user-selectable curated native icon; older Notes default safely.
- [ ] Notes support one optional category.
- [ ] Markdown remains raw editable text.
- [ ] Syntax highlighting exists.
- [ ] Markdown task-list markers appear as clickable checkboxes and retain literal Markdown source.
- [ ] Notes auto-save.
- [ ] The Note title, category picker, and delete action share a compact header above the editor.
- [ ] Notes can be deleted.
- [ ] Notes cannot be completed.
- [ ] Notes cannot be archived.
- [ ] Notes are not affected by retention.

## To-dos

- [ ] To-dos require a title.
- [ ] Description is optional.
- [ ] Category is optional.
- [ ] To-dos have no due date.
- [ ] To-dos have no priority.
- [ ] To-dos have no subtasks.
- [ ] To-dos can be completed.
- [ ] Completed To-dos disappear from the default active view.
- [ ] Archived/completed To-dos can be shown via a toggle.
- [ ] Completed To-dos can be restored.
- [ ] Completed To-do retention is configurable.
- [ ] Open To-dos are never deleted by retention.
- [ ] Settings can create, inspect, and delete weekly or monthly Scheduled To-dos with an explicit Category choice; generated To-dos are ordinary items, missed occurrences create only the latest due item, and repeated evaluation does not duplicate it.

## Appointments

- [ ] Appointments require title and date.
- [ ] Description is optional.
- [ ] Category is optional.
- [ ] No structured time field exists.
- [ ] No recurrence exists.
- [ ] Chronological view exists.
- [ ] By Category view exists.
- [ ] Chronological view exposes all matching Appointments.
- [ ] Grouped view sorts within each category chronologically.
- [ ] Relative date information is presented where appropriate.
- [ ] Passed Appointments leave the active view.
- [ ] Retained passed Appointments can be shown from the Appointments screen via a toggle and remain editable.
- [ ] Passed Appointment retention is configurable.
- [ ] Future Appointments are never deleted through retention.
- [ ] Maximum upcoming Appointments per category is configurable.
- [ ] Upcoming presentation respects the configurable future horizon (default 14 days) without hiding stored Appointments from chronological mode.
- [ ] Settings preview and validate TSV bulk imports before appending ordinary Appointments to one chosen Category or Uncategorized.

## Global filter

- [ ] All exists.
- [ ] Uncategorized items appear under All and no configured category filter.
- [ ] Every configured category is selectable.
- [ ] Selection affects Notes.
- [ ] Selection affects To-dos.
- [ ] Selection affects Appointments.
- [ ] Active selection is visually apparent.
- [ ] Selection persists across restart.
- [ ] The filter is one native segmented control with 1–4 configured Categories and a compact picker at five or more, with unchanged selection semantics.
- [ ] A Note's Category assignment remains an ordinary picker.

## Persistence

- [ ] Workspaces saved by older versions load with sensible defaults for fields added later, while preserving existing content and settings.
- [ ] Unrecognized saved fields do not prevent an otherwise valid workspace from loading; unreadable files are not silently replaced.
- [ ] After loading older data, new values persist through a save and reload without losing existing content.
- [ ] No Save button is required.
- [ ] Notes auto-save.
- [ ] To-dos auto-save.
- [ ] Appointments auto-save.
- [ ] Settings auto-save.
- [ ] Normal navigation does not lose changes.
- [ ] Normal app termination does not lose changes.

## Native UX

- [ ] App Lock is off by default; when enabled, fresh launches show only the locked view until native macOS authentication succeeds.
- [ ] Locked presentation exposes no private workspace content, sidebar entries, or Note tooltips.
- [ ] `Shift+Cmd+L` and Lock Now lock immediately when App Lock is enabled.
- [ ] Optional inactivity locking uses time away from the active application, and returning before the delay cancels it.
- [ ] To-dos and Appointments use temporary editors rather than permanent inspectors; Notes have a dedicated editor screen.
- [ ] Settings keeps inline configuration controls.
- [ ] Standard keyboard behaviour works.
- [ ] Help lists the application shortcuts, and contextual creation, navigation, Note title focus, and guarded deletion shortcuts work.
- [ ] Undo/Redo works where appropriate.
- [ ] Light mode is usable.
- [ ] Dark mode is usable.
- [ ] Text editing feels native.
- [ ] UI density is appropriate for desktop use.
- [ ] No unnecessary web-style interaction patterns are present.

## Scope control

- [ ] No Quick Capture.
- [ ] No analytics or widget dashboard.
- [ ] No cloud sync.
- [ ] No Nextcloud integration.
- [ ] No user accounts.
- [ ] No multi-category system.
- [ ] No calendar implementation.
- [ ] No to-do-management features outside this specification.

---

# 33. Reviewer decision model

Reviews should distinguish three classes of findings.

## A. Specification violation

The implementation directly contradicts an explicit requirement.

Examples:

- To-dos support multiple categories.
- Notes can be archived.
- Appointments have mandatory times.
- Open To-dos are removed by retention.

These must be fixed.

## B. Product-principle violation

The implementation technically satisfies the feature but undermines the intended product.

Examples:

- editing a To-do requires navigating through several screens,
- Note editing feels like a web form rather than a text editor,
- the global category filter is hidden and easy to overlook,
- grouped Appointments are rendered as large decorative cards that severely reduce information density.

These should normally be fixed.

## C. Implementation preference

The implementation differs from an unstated preference but does not violate the specification or product principles.

Examples:

- exact sidebar width,
- precise spacing,
- internal repository structure,
- database library choice.

These should not be treated as defects merely because a reviewer would personally implement them differently.

---

# 34. Interpretation rule

When the specification does not explicitly define an interaction, use the following order of precedence:

1. preserve the stated product purpose,
2. minimise user effort,
3. preserve simplicity,
4. follow native macOS conventions,
5. avoid adding new concepts,
6. choose the least surprising behaviour.

If a proposed solution requires introducing a new product concept, it should normally be rejected until the specification is revised.

---

# 35. Version 1 completion definition

Version 1 is complete when:

- all required capabilities in this specification are implemented,
- all invariants hold,
- all applicable verification checklist items pass,
- all critical product-principle violations are resolved,
- all explicitly excluded capabilities remain excluded,
- the application is stable enough for daily personal use.

Version 1 does not require speculative extensibility for future features.

The implementation should optimise for the product defined here rather than for hypothetical future expansion.
