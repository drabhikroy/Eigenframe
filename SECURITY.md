# Security Policy

## Supported Versions

Only the latest release of Eigenframe receives security updates.

| Version | Supported |
| ------- | --------- |
| 1.5.x   | Yes       |
| < 1.5   | No        |

## Reporting a Vulnerability

If you discover a security vulnerability, please do not open a public issue. Instead, report it privately through GitHub's private vulnerability reporting on this repository (Security → Report a vulnerability), or by email to the address on the maintainer's GitHub profile.

Please include:

- A description of the vulnerability
- Steps to reproduce it
- The potential impact
- Any suggested fixes if you have them

You can expect an acknowledgement within 48 hours and a resolution or status update within 14 days.

## What Eigenframe can and cannot reach

Eigenframe makes no network connections of any kind. It has no update checker, no telemetry, and no analytics. The Help page is a local file and loads no remote resources.

The only data it writes is `~/Library/Application Support/Eigenframe/assignments.json`, created with `0600` permissions inside a `0700` directory. It holds the paths of the media files you assigned and two boolean settings, nothing else.

## Permissions

**Input Monitoring** is requested only when *Pause while typing* is switched on, and is released as soon as that switch is turned off. The event tap is listen-only and observes key-down events solely to detect that typing is in progress. No keystroke is decoded, recorded, stored, or transmitted; the callback's only effect is to set a timer.

Eigenframe does **not** request Accessibility, Screen Recording, Full Disk Access, camera, or microphone access.

## Sandboxing and the hardened runtime

Eigenframe cannot run inside the App Sandbox: Space enumeration uses private window-server APIs, and session event taps are unavailable to sandboxed processes. Neither works under a sandbox profile.

Because the app is therefore unsandboxed and can hold an Input Monitoring grant, the **hardened runtime is a required part of the build**. It enables library validation, which prevents another process running as the same user from injecting code into Eigenframe and inheriting that grant. `Installer/build_and_package.sh` signs with `--options runtime` and aborts the build if the resulting signature does not carry the flag.

Do not add `com.apple.security.cs.disable-library-validation`, `com.apple.security.cs.allow-dyld-environment-variables`, or `com.apple.security.cs.allow-unsigned-executable-memory` to the entitlements file. Any of them re-opens that path.

## Notes on Private API Usage

Eigenframe uses private macOS APIs (`CGSMainConnectionID`, `CGSGetActiveSpace`, `CGSCopyManagedDisplaySpaces`) for Space detection. These are read-only calls that do not modify system state. If you believe their use introduces a security concern, please report it using the process above.

## Untrusted inputs

The assignments file is treated as untrusted input, because any process running as the user can rewrite it. Every stored path is re-validated (canonicalised, checked against the supported-format allowlist, and required to resolve to an ordinary file rather than a directory, device node, fifo, or socket) both when the store is loaded and again at the moment the media is rendered. Dropped files and files chosen in the open panel go through the same validation. See `Eigenframe/MediaPath.swift`.
