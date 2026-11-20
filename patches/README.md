# Patches

Empty by default. nginx security releases reach the image as a `VERSION` bump, not as backports.

A patch goes here only when a module does not build on a new nginx and the bump cannot wait:

- Prefer patching the module: `patches/<source dir>/*.patch`, where the source dir is a name from the `sources` stage of the `Dockerfile` (`lua`, `stream-lua`, `ndk`, ...).
- Holding nginx and backporting a fix is the last resort: `patches/nginx/*.patch` from upstream nginx commits (`git format-patch`).
- Patches apply in name order with `git apply` (no fuzz) before `configure`; one that does not apply fails the build.
- Delete a patch as soon as its upstream release is in the image.
