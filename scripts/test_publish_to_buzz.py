#!/usr/bin/env python3
"""weown-fleet#128: no IP address or hostname reaches a Buzz note.

The DO audit reports name live droplets by public IPv4. Kind 1/9 notes are
plaintext, so publish_to_buzz() must redact addresses before it signs. The
relay send is replaced by a capture, so this needs no key, relay or nostr-sdk.
Run: python3 scripts/test_publish_to_buzz.py
"""
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import publish_to_buzz as pb  # noqa: E402

REPORT = """<!-- local only: do not commit — contains live resource names and addresses -->
# DigitalOcean Stale Backup Audit
- Generated: 2026-10-01T08:00:00Z (check_stale_backups.py, requirements.txt)
| CRITICAL_NO_BACKUP | web-1 | 203.0.113.10 / 123456789 | $12.34 | v1.12.1 |
| STALE_WARNING | db-2 | 198.51.100.7 / 987 | 2001:db8::1 | fe80:0:0:0:200:f8ff:fe21:67cf |
| OK | chat | chat.example-tenant.com | billing.weown.dev |
"""


class RedactBeforePublish(unittest.TestCase):
    def _published(self, content):
        sent = []

        async def capture(notes, secret, relay, routes):
            sent.extend(notes)
            return ["0" * 64]

        with mock.patch.object(pb, "_send", capture), mock.patch("sys.stdout"), mock.patch("sys.stderr"):
            status = pb.publish_to_buzz(content, private_key="a" * 64,
                                        relay_url="wss://relay.example.test/", channel_id="", channel_name="")
        self.assertEqual(status, "ok")
        return "\n".join(sent)

    def test_addresses_never_reach_the_note(self):
        body = self._published(REPORT)
        for leak in ("203.0.113.10", "198.51.100.7", "2001:db8::1", "fe80:0:0:0:200:f8ff:fe21:67cf",
                     "chat.example-tenant.com", "billing.weown.dev"):
            self.assertNotIn(leak, body)

    def test_the_rest_of_the_report_is_kept(self):
        body = self._published(REPORT)
        for keep in ("CRITICAL_NO_BACKUP", "web-1", "123456789", "$12.34", "v1.12.1",
                     "2026-10-01T08:00:00Z", "check_stale_backups.py", "requirements.txt"):
            self.assertIn(keep, body)


if __name__ == "__main__":
    unittest.main()
