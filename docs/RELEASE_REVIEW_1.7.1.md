# Release review: 1.7.1

Reviewed on 2026-11-01 against the public v1.6.7 baseline, the previously uncommitted connection/continuation work, and the managed-batches development branch through `39c48dc`.

## Findings resolved before release

| Priority | Finding and consequence | Resolution |
| --- | --- | --- |
| P1 | Remote output filenames were used directly as local paths. Traversal could escape the destination; matching basenames from different segments or subfolders could overwrite outputs or share transfer files. | Reject unsafe names, isolate each batch/segment, derive distinct local names from remote references, and allocate private unique transfer files. |
| P1 | The adapter and runner both rewrote whole batch records. A late runner save could erase a cancellation, and concurrent same-ID submissions could replace each other's state. | Serialize creation/cancellation per batch, merge persisted cancellation during runner saves, and check cancellation before prompt submission. |
| P1 | A known prompt outside the recent 200 history entries could be treated as lost and resubmitted. Unknown submission outcomes could retry without consuming the configured resubmission budget. | Check exact prompt history first and apply the same retry budget to unknown outcomes. Retain stable client IDs, using full batch UUIDs for new batches. |
| P1 | Missing completion metadata was accepted as success when collecting outputs or reporting a successfully drained queue. | Require `completed: true` and `status_str: success`; reject malformed queue payloads as unknown. |
| P2 | Fractional retry counts reached `range`, non-finite values reached JSON state, and zero timeouts could disable expected transfer bounds. | Validate numeric types, finite values, positive timeouts, retry limits, nonempty segment lists, and absolute destination/upload paths before persistence. |
| P2 | After the final download succeeded, an unavailable server could keep the batch waiting indefinitely. | Finalize locally completed downloads before probing server reachability. |
| P2 | Packaging directly from a synced checkout could include Finder metadata reattached after signing, producing an invalid distributed signature. | Archive a clean staging copy outside the checkout and verify its signature before creating the ZIP. |

Ten focused release regressions cover these fixes, in addition to the existing Swift and Python suites. The MCP adapter is version 0.3.3; the app bundle is version 1.7.1.

## Validation scope

Run `bash scripts/check.sh` for the complete gate: four localizations, history and notification models, simulated queue actions and multi-server monitoring, GPUtw authentication/port recovery fixtures, UDP loopback Wake-on-LAN, local HTTP discovery, extension installation, Swift/Python IPC, MCP transport/cancellation, batch recovery/pipelining/download faults, watchdog behavior, release build, bundle resources, AVKit linkage, and ad-hoc signature verification.

The complete check gate passed, including the release build and signature/resource checks. The focused 10-test release regression suite also passed after the final runner change.

Release environment: Apple Silicon (`arm64`), macOS 27.2 (26B123). Batch integration uses a fault-injecting local HTTP fixture; it does not generate media on a GPU. GPUtw checks use fixture credentials and intercepted requests. No live account management, physical wake, real GPU generation, or production stop/prioritize operation was performed for this release. Native notification delivery and authenticated SSH depend on the user's macOS permissions and keys.

GPUtw transport and port semantics were cross-checked against the provider's [API host documentation](https://docs.gputw.ai/zh-TW/docs/ai-assistant), [port management API](https://docs.gputw.ai/zh-TW/docs/rest-api-quickstart), and [access mode/password rules](https://docs.gputw.ai/zh-TW/docs/ports).

Recovery is best effort when server history has been erased or an unknown submission has aged beyond the searchable history window; ComfyUI does not provide an exactly-once submission transaction here. SHA-256 records local transfer integrity, not an independently supplied server checksum. Independent prepared graphs can be batched; dependencies that require reviewing an earlier result must pass the existing QC gate first.

The distributed app is ad-hoc signed, with a Sparkle Ed25519-signed archive/feed using the existing release key. It is not Apple Developer ID signed or notarized.
