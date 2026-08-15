# PTMC integration

This branch follows upstream PlayCover `develop` and swaps the bundled PlayTools dependency to the public `EmilyTsum/PlayTools` `metal-capture` branch.

Pinned PlayTools commit at this revision: `e5af5c9e44ff9939cc254ef00f57edabd5d26e96`.

The intent is to keep the PlayCover diff minimal: no capture implementation lives here. PTMC remains inside PlayTools in the game process; PlayCover only bundles that framework. Update this pin after the PlayTools macOS CI build passes.
