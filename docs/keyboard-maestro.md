# Creating .kmmacros Files Programmatically

## File Format

`.kmmacros` files are plist XML. Macros **must** be wrapped in a MacroGroup — a bare array of macro dicts silently fails with "Imported macros disabled - no macros were imported".

### Required structure

```xml
<plist version="1.0">
<array>
  <dict>
    <key>Macros</key>
    <array>
      <dict><!-- macro here --></dict>
    </array>
    <key>Name</key>
    <string>Group Name</string>
    <key>UID</key>
    <string>some-unique-id</string>
  </dict>
</array>
</plist>
```

If the group `Name` matches an existing group, KM merges the macro into it.

## ExecuteShellScript Action

All these fields are needed — missing ones cause silent failures:

```xml
<dict>
  <key>ActionUID</key>
  <integer>99901</integer>
  <key>DisplayKind</key>
  <string>None</string>
  <key>HonourFailureSettings</key>
  <true/>
  <key>IncludeStdErr</key>
  <true/>
  <key>MacroActionType</key>
  <string>ExecuteShellScript</string>
  <key>Path</key>
  <string></string>
  <key>Source</key>
  <string>Nothing</string>
  <key>Text</key>
  <string>#!/bin/bash
your-script-here</string>
  <key>TimeOutAbortsMacro</key>
  <true/>
  <key>TrimResults</key>
  <true/>
  <key>TrimResultsNew</key>
  <true/>
  <key>UseText</key>
  <true/>
</dict>
```

## Importing

- **Double-click in Finder** — `open file.kmmacros` from terminal is unreliable
- After import, the macro group is **disabled by default** — enable it in KM Editor (hold Option while importing to auto-enable)

## Best Practice

Always export a working macro from the target KM install first and use it as a template. Don't author from scratch.

## Modifier Values

| Modifier | Value |
|----------|-------|
| Command  | 256   |
| Shift    | 512   |
| Option   | 2048  |
| Control  | 4096  |

Combine by adding: Ctrl+Shift+Opt+Cmd = 6912
