# Legacy workspace fixtures

These synthetic workspaces were encoded using the unchanged `Models.swift` from
commit `1c7968ac263cdfe01c389662b76f3b5d685ba07d` (the initial commit), with fixed IDs and dates.
They contain no user data. They intentionally omit fields introduced later.

`initial-workspace.json` uses a Category filter; `legacy-filter-workspace.json`
uses the former Uncategorized filter. Both contain Notes in reverse creation
order, Unicode Markdown, an open To-do, an Appointment and nondefault Settings.
The tests must preserve their content through migration, editing, saving and reload.
Do not regenerate these fixtures using current models when the schema changes.
