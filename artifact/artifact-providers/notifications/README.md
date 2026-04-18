# notifications — artifact scheme

Session-scoped notifications log. Single well-known URI `notifications|<backend>/session`.

Append-only. The backend caps the recent-entry count.

Default backend: `os-notifications` (ephemeral session file).
