<!--
  Before opening: search existing issues/PRs, and make sure each commit carries
  a DCO sign-off (`git commit -s`). Docs: CONTRIBUTING.md
-->

## Summary

<!-- What does this PR change, and why? Link the issue: "Fixes #123" -->

## Type of change

- [ ] 🐛 Bug fix
- [ ] ✨ Feature (native surface for an existing OpenCode API area)
- [ ] 🎨 UI/UX polish (no behavior change)
- [ ] 📖 Documentation
- [ ] 🔧 Build / tooling / snapshot scripts

## Testing

- [ ] Release build: `./script/build.sh` passes with no new warnings
- [ ] Smoke test: `swift script/Integration/Main.swift` (Core/flow changes)
- [ ] Manual flow covered: streaming, stop (⌘.), queue/steer delivery, disconnect → reconnect
- [ ] Light + dark mode verified
- [ ] Screenshots / screen recordings attached (UI changes)

## Ground rules (CONTRIBUTING.md)

- [ ] No third-party dependencies
- [ ] UI uses `Theme.swift` tokens (`Color.oc*`, `Motion.*`)
- [ ] State changes go through `AppModel`, network through `APIClient`/`EventStream`
- [ ] All commits are DCO signed-off (`Signed-off-by` matches author)
