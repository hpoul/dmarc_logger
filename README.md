# dmarc_logger

Turns DMARC aggregate-report emails into rows of a flat CSV file. It runs as
a postfix pipe: every report mail addressed to the report address is fed to
the binary on stdin, and its records are appended to the CSV.

## Usage

```
# Pipe mode: read one mail from stdin, append its rows (this is what the
# postfix alias runs).
dmarc_logger --csv-file /path/to/reports.csv [--dead-letter-dir /path/to/failed]

# Rewrite a pre-2026 twelve-column file to the current header, padding old
# rows with empty fields. Idempotent: a second run changes nothing.
dmarc_logger migrate --csv-file /path/to/reports.csv

# Replay every dead-lettered mail through the current parser. Successes are
# appended and moved to "processed/"; failures stay put with their reason
# on stderr.
dmarc_logger reprocess --csv-file /path/to/reports.csv [--dead-letter-dir /path/to/failed]
```

`--dead-letter-dir` defaults to `failed/` beside the CSV file. Everything is
logged to stderr, because stdout belongs to postfix. Every run prints one
outcome line saying what happened: rows appended, duplicate skipped, or the
mail saved to the dead letter and why.

For postfix, `/etc/aliases` holds a line like:

```
dmarc.report.receive: "|/path/to/dmarc_logger_linux.exe --csv-file /path/to/reports.csv"
```

## The contract with postfix

- Exit 0 once the report's rows are appended, **or** once the raw mail is
  safely saved to the dead-letter directory. A parse failure is not the
  reporter's problem; bouncing it helps nobody.
- Exit 75 (`EX_TEMPFAIL`) only when even the dead-letter write fails, so
  postfix queues and retries.
- Exit 64 on usage errors (a missing `--csv-file`), exit 1 when `migrate`
  or `reprocess` fails.

Concurrent deliveries are safe: header check, duplicate check and append run
under an exclusive lock, and each report's rows go out in one write. A
report whose `(orgName, reportId)` is already in the file is skipped as a
duplicate. Appending never happens under a foreign header; the mail is
dead-lettered instead, and `migrate` plus `reprocess` recover it.

Accepted attachments: zip, gzip (`.gz`, `.xml.gz`), plain `.xml`, and gzip
parts that are inline or carry no disposition. When several parts qualify,
the one whose content parses as a `<feedback>` document wins. Values
outside the RFC 7489 result sets are kept as their raw string with a
warning, never thrown on. Forensic (`ruf`) reports are out of scope.

## Columns

The first twelve columns are unchanged since 2020, in the same order with
the same names, so every old row stays valid:

`orgName, begin, end, sourceIp, count, dkim, spf, headerFrom, dkim_domain,`
`dkim_result, spf_domain, spf_result`

`dkim`/`spf` are the receiver's DMARC verdict per mechanism
(`policy_evaluated`); `dkim_domain`/`dkim_result` and
`spf_domain`/`spf_result` are the first DKIM/SPF auth result, or
`(absent)`/`none` when there is none.

Appended after them:

| Column | Content |
|---|---|
| `reportId` | `report_metadata/report_id`; with `orgName` it recognizes duplicates. |
| `policyDomain` | The domain the receiver evaluated (`policy_published/domain`). |
| `policyP` | The requested policy: `none`, `quarantine` or `reject`. |
| `policySp` | The subdomain policy, if the record publishes one. |
| `policyPct` | The `pct` tag, if published. |
| `policyAdkim`, `policyAspf` | The alignment modes (`r`/`s`) under which `dkimAligned`/`spfAligned` were computed; without them those columns are uninterpretable. |
| `disposition` | What the receiver did: `none`, `quarantine` or `reject`. |
| `reasonType`, `reasonComment` | `policy_evaluated/reason` overrides (`forwarded`, `sampled_out`, `trusted_forwarder`, `mailing_list`, `local_policy`, `other`), joined with `;`. |
| `dkimSelector` | The first DKIM result's selector. |
| `dkimAll` | Every DKIM auth result as `domain:selector:result`, joined with `;`. |
| `spfScope` | `mfrom` or `helo`, from the first SPF result's `scope`. |
| `spfAll` | Every SPF result as `domain:scope:result`, joined with `;`, symmetric with `dkimAll`. |
| `dkimAligned`, `spfAligned` | Whether a passing DKIM `d=` or SPF domain matches `header_from` under the published mode; empty when nothing passed. Relaxed alignment uses a same-or-subdomain check, which agrees with the RFC's organizational-domain comparison except on multi-level public suffixes. The receiver's own verdict in `dkim`/`spf` stays the authority next to it. |
| `failureCause` | One derived label per row; see below. |

## failureCause labels

The receiver's verdict rules: when either mechanism passed, the row is `ok`.
Otherwise the first matching rule wins. Each label names what usually
produces it and what to do about it.

| Label | Meaning | Usual producer | Remedy |
|---|---|---|---|
| `ok` | DMARC passed. | — | None. |
| `forwarded` | The receiver overrode the policy for a forwarding reason. | Mailing lists, forwarders. | None if expected; else check the `reasonType`. |
| `verdict-differs` | This tool computed an aligned pass but the receiver reported fail on both mechanisms. | Subdomain-vs-organizational-domain edge cases, receiver bugs. | Trust the receiver; inspect `dkimAll`/`spfAll`. |
| `temperror` | A transient DNS error left the verdict provisional. | DNS timeouts at the receiver. | Ignore; later reports supersede it. |
| `dkim-unaligned` | A signature passed, but for a third-party domain. | ESPs signing with their own `d=`. | Publish a DKIM key for your domain at the ESP (aligned `d=`). |
| `spf-unaligned` | SPF passed, but for a third-party domain. | Forwarders, ESP bounces. | Same as above; SPF alone rarely fixes forwarding. |
| `dkim-broken` | DKIM failed definitively (`fail`, `policy`, `permerror`). | Body/header modification in transit, expired keys, broken signing. | Check the sending pipeline modifies nothing; rotate keys. |
| `spf-not-listed` | SPF failed (`fail`, `softfail`, `permerror`). | Senders missing from the SPF record. | Add the sender to SPF, or rely on aligned DKIM. |
| `unsigned` | Neither mechanism produced a signal. | Spoofing, or legitimate mail with no auth at all. | If legitimate, deploy SPF and DKIM; else it is working as intended. |
| `unrecognized` | A result value outside the RFC set. | New reporter vocabulary. | Inspect `dkimAll`/`spfAll`; may need a mapping update. |

## Viewer

`viewer/index.html` is a self-contained page that reads the CSV in the
browser: summary figures, a weekly pass/fail chart, per-domain and
per-cause tables, a sources table with the failure cause on each row, and
a panel listing rows it could not use. It opens on invented example data.
This repo copy is the source; the same page is also published as a GitHub
Pages site on every push to master that touches `viewer/`.

To look at the live file:

```
scp services.tapo.at:dmarc/reports.csv .
```

then open `viewer/index.html` in a browser and drop the CSV onto it (or
paste its contents). The file is parsed locally and never uploaded.

The "Rows the viewer could not use" panel doubles as a check on the
locking fix: a file appended only by the new binary leaves that panel
empty. Any row listed there predates the fix or was written around it.

## Building

1. Install Dart 3 (SDK constraint `^3.13.0`).
2. `dart pub get`
3. `dart analyze --fatal-infos && dart test`
4. `dart compile exe bin/dmarc_logger.dart -o dmarc_logger_linux.exe`
   (add `--target-os linux --target-arch x64` when cross-compiling from
   macOS).

## Deploying (steps for root)

The binary was proven on the host before anything changed there: copied
aside, piped every `example/*.eml` fixture through it into a temporary CSV,
and `migrate` run against a copy of the live file with row counts and the
first twelve fields verified byte-identical. To deploy:

1. `cd /home/herbert/dmarc && cp reports.csv reports.csv.pre29`
2. Migrate the live file as the pipe user (root would leave the file
   root-owned):
   `sudo -u nobody /home/herbert/dmarc_logger_linux.exe.new migrate --csv-file /home/herbert/dmarc/reports.csv`
3. Swap the binary, keeping the old one:
   `mv /home/herbert/dmarc_logger_linux.exe /home/herbert/dmarc_logger_linux.exe.old && mv /home/herbert/dmarc_logger_linux.exe.new /home/herbert/dmarc_logger_linux.exe`
4. Re-run the same `migrate` command: it pads any twelve-column row the
   old binary appended between steps 2 and 3, and is otherwise a no-op.
5. Create the dead-letter directory writable by `nobody`:
   `mkdir -p /home/herbert/dmarc/failed && chown nobody:herbert /home/herbert/dmarc/failed && chmod 770 /home/herbert/dmarc/failed`
6. The alias needs no argument changes (`--csv-file` as before); run
   `newaliases` only if the alias line itself was touched.
7. After deploy, recover anything the new binary dead-lettered:
   `sudo -u nobody /home/herbert/dmarc_logger_linux.exe reprocess --csv-file /home/herbert/dmarc/reports.csv`
   Mails bounced in the past are gone; only mails saved since the new
   binary runs can come back this way.
