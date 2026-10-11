# unraid-timemachine-discovery

Makes Unraid shares exported as **Yes (Time Machine)** appear in macOS Time
Machine's disk picker.

## Why

Time Machine over SMB needs the server to advertise two mDNS services under one
instance name: `_smb._tcp`, and `_adisk._tcp` naming the shares that are valid
backup destinations. Unraid sets `multicast dns register = No` and hand-writes
its own avahi service file, which emits `_smb._tcp` but never `_adisk._tcp` — so
a Time Machine share is fully visible in Finder and absent from Time Machine.

This plugin reads the running Samba config, collects every share with
`fruit:time machine = yes`, and writes the missing record to
`/etc/avahi/services/timemachine.service`, leaving Unraid's own file alone. Both
use `%h`, so avahi publishes them under one instance name, which is what the
pairing requires. It re-runs on array start and whenever share settings change,
reloading avahi only when the content actually changed. If a future Unraid
release publishes `_adisk._tcp` itself, the plugin stands down.

## Requirements

- Unraid 6.12 or newer. Developed and tested on 7.3.2.
- At least one share exported as **Yes (Time Machine)**.
- The Mac and the server on the same subnet: mDNS does not cross subnets.

## Install

Plugins → Install Plugin:

```text
https://raw.githubusercontent.com/externl/unraid-timemachine-discovery/main/timemachine-discovery.plg
```

Then **Settings → User Utilities → Time Machine Discovery**, or:

```bash
/usr/local/emhttp/plugins/timemachine-discovery/scripts/rc.timemachine-discovery status
```

The settings page shows what is being advertised and can turn the
advertisement off, which withdraws the record. To check from a Mac, run
`dns-sd -B _adisk._tcp`.

## Troubleshooting

If the server's mDNS name picks up a numeric suffix, such as `Tower-2` instead
of `Tower`, Time Machine loses the destination. Another mDNS responder on the
server is claiming the same host name, usually a container on host networking
that runs its own avahi daemon. Each time Unraid's avahi restarts, such as on
array start, it gives up the name and takes the next free one.

The suffix shows on the settings page under **live mDNS advertisement**, and on
a Mac in `dns-sd -B _adisk._tcp`.

Turn off the container's avahi daemon (for Homebridge, set `ENABLE_AVAHI=0`),
then reclaim the name:

```bash
/etc/rc.d/rc.avahidaemon restart
```

## Build

```bash
./release.sh "What changed"          # version is today's date
./release.sh -s .1 "Fixed that"      # same-day rerun, numeric suffix
```

Builds the package, stamps the version and sha256 into the `.plg`, prepends the
changelog and checks they agree. Needs Slackware's `makepkg`, so run it on the
server or anywhere with Docker. Commit the package and the `.plg` together;
pushing to `main` is what publishes.

The suffix must be numeric — PHP's `version_compare` reads a trailing `a` as
"alpha" and ranks it *older*.

## Support

Bugs and questions:
[GitHub issues](https://github.com/externl/unraid-timemachine-discovery/issues).

## License

MIT
