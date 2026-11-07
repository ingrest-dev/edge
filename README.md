# edge

OpenResty image for the [Ingrest](https://github.com/ingrest-dev) panel: OpenResty with HTTP/3, brotli, zstd, GeoIP2 and ModSecurity modules on Debian 13, plus the directive table the panel validates configs against (`/usr/local/openresty/directives.json`).

## Releases

- `watch` checks OpenResty tags daily and opens a pull request that bumps `VERSION`.
- Every pull request builds `ghcr.io/ingrest-dev/edge:test-<version>-<commit>` for amd64 and arm64. Test it on a panel by pinning that tag.
- A merge to `main` publishes `<version>` and `<version>-<commit>`, then `publish` waits for approval in the `release` environment and adds the image digest to the signed manifest `stable.json` in the release `channels`.
- Panels take the newest image in the manifest whose `min_panel` is not above their own version. Set `MIN_PANEL` in the pull request when an image needs a newer panel.
- Label a pull request `security` to let panels with automatic security updates install it at once.

The OpenResty tarball is verified against the signing key in `keys/openresty.gpg`. The manifest is signed with the minisign key in `keys/edge.pub`.

## Build

```
docker build --build-arg OPENRESTY=$(cat VERSION) -t edge .
sh test/smoke.sh edge
```
