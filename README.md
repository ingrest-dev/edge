# edge

Web server image for the [Ingrest](https://github.com/ingrest-dev) panel: nginx mainline with the Lua module stack, HTTP/3, brotli, zstd, GeoIP2 and ModSecurity on Debian 13, plus the directive table the panel validates configs against.

## Contents

- nginx from nginx.org, verified against the signing keys in `keys/nginx.gpg`.
- Static modules: `lua-nginx-module`, `stream-lua-nginx-module`, `ngx_devel_kit`; LuaJIT 2.1.
- Dynamic modules: brotli, zstd (`GetPageSpeed/zstd-nginx-module`), GeoIP2 (HTTP), ModSecurity.
- Lua libraries: `resty.core`, `resty.lrucache`, `resty.string` (`sha256`, `random`), `cjson`.
- Every source is pinned in the `Dockerfile` by version or commit and checked at build time.

## Layout

- `/usr/local/nginx/sbin/nginx`, modules in `/usr/local/nginx/modules`, Lua libraries in `/usr/local/nginx/lualib`.
- `/usr/local/nginx/directives.json`: every directive form of the build.
- Temp files, pid and lock default to `/tmp`, so the image runs with a read-only root and a tmpfs on `/tmp`.
- Licenses of nginx and every module in `/usr/local/nginx/licenses`.

## Versions

`VERSION` is `<nginx version>.<build>`; the image reports the build in `nginx -v` as `ingrest-<build>`.

- `watch` checks the nginx mainline hourly. A new signed release opens a pull request that bumps `VERSION`; when its CHANGES entry has security fixes, the pull request is labelled `security` and lists them.
- nginx releases are automatic: when the bot pull request builds and passes the smoke test on both architectures and changes only `VERSION`, `build` merges it, builds `main`, and `publish` signs it without review, but only when `VERSION` is the only file changed since the commit of the last published image (`commit` in `stable.json`). Anything else, modules included, waits for a merge and the `release` approval.
- `watch` also checks every module hourly (release tags; `ngx_brotli` and the GeoIP2 module by their default branch, they have no current tags) and opens one pull request per group; `lua-nginx-module`, `stream-lua-nginx-module` and `lua-resty-core` move together.
- A module pull request lists the compared commits and is labelled `security` when a commit subject names a CVE, an advisory or a memory safety fix.
- `scan` runs Trivy on the newest published image every 6 hours: fixable HIGH or CRITICAL Debian packages open a `security` pull request that changes `REFRESH`, which makes the runtime stage reinstall and upgrade its packages.
- `patches/` is for emergencies only (see `patches/README.md`).

## Releases

- Every pull request builds `ghcr.io/ingrest-dev/edge:test-<version>-<commit>` for amd64 and arm64 and runs `test/smoke.sh`. Test it on a panel by pinning that tag.
- `test/smoke.sh` covers what the panel's Lua uses: every phase (init, init_worker, ssl_certificate, balancer with retries, header_filter, log, stream preread, balancer and log), timers, light threads, cosockets, shared dicts, request bodies, the bundled libraries, brotli, zstd, ModSecurity, HTTP/3 and stream SNI passthrough.
- A merge to `main` publishes `<version>` and `<version>-<commit>`, then `publish` waits for approval in the `release` environment and adds the image digest to the signed manifest `stable.json` in the release `channels`. Signing runs one at a time in the `channel` environment, which holds `EDGE_KEY`; it refuses a build older than the newest published one and puts the previous manifest back when an upload fails.
- Panels take the newest image in the manifest whose `min_panel` is not above their own version. Set `MIN_PANEL` in the pull request when an image needs a newer panel.
- Label a pull request `security` to let panels with automatic security updates install it at once.
- The manifest is signed with the minisign key in `keys/edge.pub`.

## Build

```
docker build --build-arg VERSION=$(cat VERSION) -t edge .
sh test/smoke.sh edge
```
