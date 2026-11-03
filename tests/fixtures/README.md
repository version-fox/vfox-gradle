# Fixtures

`releases.html` is an excerpt of <https://gradle.org/releases/>, taken on
2026-11-03. The page's head is reduced to its title, and 12 of its 174 release
blocks are copied as they are, in the order the page lists them: by date, not by
version, so `8.14.6` comes before `9.8.1`. `Available` reads the
`<a name="…"></a>` anchor at the start of each block, and
`tests/available_test.lua` checks what it makes of them.

If gradle.org changes the markup of the page and `vfox search gradle` stops
working, put a block of the new markup here and change the hook and the test
together. The E2E suite is what notices the change first, see
[docs/e2e.md](../../docs/e2e.md).
