# Midnight Manor II Preview

Phone-test deployment for the newest Midnight Manor II work (the Realm open world map, PR #3 in `lifetimeballer1/midnight-manor-2`).

The preview workflow:
- checks out the pinned source commit (`SOURCE_SHA` in the workflow)
- verifies all assets
- runs Python tests
- runs the Godot gameplay regression suites, including the Realm suites
- exports the single-threaded Safari-compatible Web build
- deploys the result to this repository's GitHub Pages site

Expected preview URL after Pages is enabled:

https://lifetimeballer1.github.io/midnight-manor-2-preview/

The main Midnight Manor II repository and its live Pages deployment are not modified by this preview.
