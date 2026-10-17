# Omarchy tooltip lab comparison

Screenshots from the same native Wayland lab, with the same theme, configured font, tooltip text and 860 x 420 logical-pixel window. Both screenshots use square tooltip borders. Window opacity was set to fully opaque only for the lab windows to exclude unrelated desktop content from the captures.

- `before.png`: original official Quickshell 0.3.1 binary, extracted from the installed package archive without changing the system installation. Its default Fusion policy ignores Omarchy's style selection.
- `after.png`: the installed Omarchy tooltip compatibility runtime and shared style from PR #15694. The standard Qt Quick Controls tooltip declarations are unchanged between the two lab configurations.
- `interactive.png`: optional lazy interactive HoverCard with keyboard-focusable actions, using the same square-border preference.

The existing Omarchy UI kit buttons in the lab remain themed in both images. The before/after comparison specifically demonstrates the standard Qt Quick Controls attached tooltip.

Related PR: https://github.com/omacom/omarchy/pull/15694
