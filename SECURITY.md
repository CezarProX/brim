# Security Policy

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

Use GitHub's private reporting instead: on the repository page, open **Security → Report a
vulnerability**. Include the steps to reproduce, the macOS version and the Brim version
(Settings → About).

You can expect a first reply within a week. Once a fix ships, the advisory is published with
credit to the reporter unless you ask otherwise.

## Scope

Brim runs locally and asks for powerful macOS permissions (Screen Recording, Accessibility,
Automation). Reports are especially welcome for:

- anything that lets another app, a web page or a file make Brim run commands, scripts or
  AppleScript it should not;
- the local socket used by the optional Claude Code hook ("Answer your agents");
- data written outside Brim's own folders, or deletion of files the user did not choose;
- screenshots, clipboard history or other private data leaving the Mac without the user asking.

## Supported versions

Only the latest release receives fixes.
