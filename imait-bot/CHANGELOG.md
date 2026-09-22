# i.MAIT.bot Changelog

## [Unreleased]

### Fixed

- Buzz session crash / reconnect storm: Hermes 0.20.6 watched every listed channel when `BUZZ_CHANNELS` was empty, blew relay WS quota (`rate-limited: quota exceeded`), and dropped replies whose prose contained an unresolved `@token` (no `--mention` on `buzz messages send`). Image patch now watches `BUZZ_HOME_CHANNEL` when the watch list is empty, passes `--mention` of the bot pubkey, honours relay `retry in Ns`, and treats `i.MAIT.bot` / `iMAIT` as inbound mention aliases. Host overlay sets home channel + transport `auto`. Git still does not pin live UUIDs.

### Changed

- Keep git `imait-bot/` as shared gateway infrastructure. Teammates add **i.MAIT.bot** from the Buzz channel UI; do not pin channel UUIDs in git. The live watch set / home channel live in the host `.env` overlay (`scripts/apply-host-overlay.sh`).

### Added

- Initial standalone compose stack: Hermes Agent gateway (`imait-bot:8080`) + Caddy for `i.mait.bot`. Buzz community is chosen per instance via host `.env`.
- Image build compiles `buzz` CLI from pinned `block/buzz` so the Hermes Buzz adapter can load.
