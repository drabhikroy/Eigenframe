# Security Policy

## Supported Versions

Only the latest release of Eigenframe receives security updates.

| Version | Supported |
| ------- | --------- |
| 1.0.x   | Yes       |

## Reporting a Vulnerability

If you discover a security vulnerability, please do not open a public issue. Instead, report it privately by emailing the repository owner directly via the contact information on their GitHub profile.

Please include:

- A description of the vulnerability
- Steps to reproduce it
- The potential impact
- Any suggested fixes if you have them

You can expect an acknowledgement within 48 hours and a resolution or status update within 14 days.

## Notes on Private API Usage

Eigenframe uses private macOS APIs (`CGSGetActiveSpace`, `CGSCopyManagedDisplaySpaces`) for Space detection. These are read-only calls that do not modify system state. If you believe their use introduces a security concern, please report it using the process above.
