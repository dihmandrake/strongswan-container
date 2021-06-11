# StrongSwan Container (Experimental)

This container is a statically, monolithic compiled version of [StrongSwan](https://github.com/strongswan/strongswan) from the source. The executables are copied into a scratch container within one layer.

Static linking is used as dynamic linking does not actually provide any real advantages inside a container. Linking in itself provides not many advantages, as pointed out by Linus Torvalds in the [mailing list](https://lore.kernel.org/lkml/CAHk-=whs8QZf3YnifdLv57+FhBi5_WeNTG1B-suOES=RcUSmQg@mail.gmail.com/).

It uses [musl-libc](https://www.musl-libc.org/) and not [glibc](https://www.gnu.org/software/libc/), because glibc always requires dynamic linking for NSS. It is at least used for the function `getaddrinfo()`, which takes care of DNS/Name resolution. Musl handles this function without any dynamic linking.

New StrongSwan versions are automatically pulled in via [Git Submodules](https://git-scm.com/book/en/v2/Git-Tools-Submodules) and created as a new Pull Request with a nightly [GitHub Action](.github/workflows/update-submodules.yml). Container updates are manged via [Dependabot](.github/dependabot.yml).

All cipher suites are based on OpenSSL and all in-tree crypto is disabled for security reasons. The enabled plugins can be found in the [Dockerfile](./Dockerfile) and compiler flags as well.

## Run the container

Run the container with:

```sh
$ docker run --rm \
    --cap-add NET_ADMIN \
    --sysctl net.ipv4.ip_forward=1 \
    --sysctl net.ipv6.conf.all.forwarding=1 \
    --sysctl net.ipv6.conf.all.proxy_ndp=1 \
    --read-only \
    --tmpfs /var/run \
    --tty \
    -v my/strongswan-conf:/etc/strongswan/swanctl/conf.d:ro \
    dihmandrake/strongswan
```

Notes for the flags:

* `--cap-add NET_ADMIN` is required for StrongSwan to set up the network properly.
* `--sysctl *` to properly forward IP packets.
* `--tty` flag is needed for StrongSwan (charon) to properly output (likely flush) the logs to the container's stdout.
* `--read-only` as a security measure as the container should not write anything and make it immutable.
* `--tmpfs /var/run` allows charon to create the vici socket properly. One might mount this into a folder for other containers to access the control socket.
* `-v my/strongswan-conf:/etc/strongswan/swanctl/conf.d:ro` an example of how to mount the [StrongSwan config](https://wiki.strongswan.org/projects/strongswan/wiki/strongswanconf).

## TODOs

Notes for things that need optimization:

* Validate output of `swanctl --list-algs` after build to confirm only OpenSSL-based ciphers are loaded and no in-tree crypto.
* Validate that container can start after a new build.
* Look into better hardening with compiler flags. Maybe [OWASP compiler flags](https://cheatsheetseries.owasp.org/cheatsheets/C-Based_Toolchain_Hardening_Cheat_Sheet.html) are helpful.
* Look into running the container as non-root.
* Properly set tags for images in the format of `strongswanVersion-alpineVersion`, for example, `5.9.2-3.13.5`.
* Properly tag and release the repo repository instead of updating on any commit on the main branch.
* Push the image to alternative container repos (GitHub & Quay).
* Compile dependencies of StrongSwan from source to enable more compiler optimizations. Most important: OpenSSL, musl-libc and curl
