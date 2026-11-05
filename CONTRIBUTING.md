# Contributing to OpenCode Harness

Thank you for considering contributing! This is a native macOS SwiftUI client for
[OpenCode](https://opencode.ai) — small, dependency-free, and built entirely with
system frameworks. Most useful contributions fit in one focused page of code.

## Ways to contribute

- 🐛 **Bug reports** — wrong rendering, crashes, reconnect edge cases, API drift
- 💡 **Feature ideas** — discuss in an issue before building something big
- 📖 **Docs** — README screenshots, keybinding tables, architecture notes
- 🧩 **OpenCode API coverage** — if OpenCode v2 exposes an area the harness doesn't
  surface yet, mapping it to a native surface is high-value work
- 🌐 **Localization** — strings are currently English-only; happy to add a strategy

## Development setup

Requirements:

- macOS 15+
- Xcode 16+ (tested with Xcode 26)
- OpenCode CLI 2.x on `PATH` or at `~/.opencode/bin/opencode`
- A configured OpenCode provider/model (for live testing)

Build and run:

```bash
git clone https://github.com/adityakrchy/opencode-harness
cd opencode-harness
./script/build.sh          # release build into dist/
open "dist/OpenCode Harness.app"
```

…or open `OpenCodeHarness.xcodeproj`, pick the **OpenCodeHarness** scheme, and press **⌘R**.

## Project layout

```
OpenCodeHarness/
  App/         SwiftUI entry point, window, menu-bar commands
  Core/        AppModel (source of truth), APIClient, SSE EventStream,
               server lifecycle, models, preferences
  Design/      Theme, reusable components, Markdown/code/diff rendering
  Features/    One file per screen area (chat, composer, sidebar, inspector…)
```

Ground rules that keep the codebase small:

- **No third-party dependencies.** System frameworks only (SwiftUI, AppKit, Foundation).
- **`AppModel` is the single source of truth.** Views observe it; don't add parallel
  stores or singletons.
- **Networking lives in `APIClient` / `EventStream`.** Feature code goes through the
  model, never straight to URLSession.
- **New UI follows `Theme.swift` colors/tokens** (`Color.ocTextPrimary`, `Motion.smooth`,
  …) rather than ad-hoc colors or durations, so dark/light stay consistent.

## Testing your changes

- Manual: boot → session → prompt → streamed reply → tool approvals → compact/revert.
- Automated smoke test (spins a real headless flow):

  ```bash
  swift script/Integration/Main.swift
  ```

- Visual regression: `script/Snapshot/main.swift` renders deterministic screenshots
  of every screen without a logged-in desktop session. Include before/after shots
  for UI changes if you can.

## Commit conventions

Conventional Commits, matching the existing history:

```
feat(ui): add support for raw data drops
fix(core): recover SSE connection after server restart
docs: update API coverage table
```

Scope is optional; use the area touched (`ui`, `core`, `docs`, `snapshot`, …).

## Developer Certificate of Origin (DCO)

This project uses the [DCO](https://developercertificate.org) — the same lightweight
mechanism used by the Linux kernel, Homebrew, and many others. There is no CLA to
sign; your sign-off asserts you have the right to submit the code and license it
under the project's MIT license.

Add a `Signed-off-by` line to every commit (trailer must match the commit author):

```bash
git commit -s -m "feat(ui): my change"
```

…or add manually:

```
Signed-off-by: Jane Doe <jane@example.com>
```

PRs with unsigned commits will be asked to rebase with sign-offs; maintainers may
fix trivially signed-off-only PRs themselves with the author's permission.

## Pull request checklist

- [ ] Builds clean with `./script/build.sh` (Release, no new warnings)
- [ ] Commits follow the conventions above and are DCO signed-off
- [ ] No new dependencies, color literals, or parallel state stores
- [ ] UI changes: tested in both light and dark mode
- [ ] Streaming/interruption behavior survives: stop (⌘.), queue/steer, disconnect + reconnect
- [ ] Screenshots attached for visual changes

## Review process

- Small fixes and API-surface plumbing are usually merged within a few days.
- Large features: open an issue first so we agree on the native-UI approach before
  code lands — the goal is a *native* macOS surface, not a ported web UI.
- Maintainers may squash-merge; keep commits logically separate even so.

## Reporting problems

- Bugs → [Issues](https://github.com/adityakrchy/opencode-harness/issues) with the bug template
- Security → **do not file a public issue**; see [SECURITY.md](SECURITY.md)
- Conduct issues → see [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)

## License

By contributing, you agree your contributions are licensed under the project's
[MIT License](LICENSE) (documented in full by your DCO sign-off).
