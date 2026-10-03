Testing random stuff and playing around, not intended to be used.
Replaced all to change the name, sorry if that breaks credit or things like that, that was not my intention. Lmk and I'll fix it!

## Linux media playback

Audio and video playback use the system libmpv library. On Ubuntu/Debian, install
`libmpv2` (or `libmpv1` on older releases) and `libepoxy0` when running the Linux
tarball. The Snap includes these runtime dependencies.

When building from source, install `libmpv-dev` and `libepoxy-dev` in addition to
the usual Flutter Linux build dependencies.
