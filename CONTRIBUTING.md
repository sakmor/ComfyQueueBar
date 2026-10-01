# Contributing

Bug reports, documentation improvements, and focused pull requests are welcome.

Before reporting a bug, read the [troubleshooting guide](docs/TROUBLESHOOTING.md). Include the environment, expected result, actual result, and a reproducible example. Sanitize logs and workflow metadata.

For changes, fork the repository, create a branch, and keep the scope focused. Use English for public documentation, UI strings, issues, and pull requests. Follow the existing Swift and Python style; avoid adding dependencies when Apple frameworks or the Python standard library suffice.

Run `bash scripts/check.sh` on macOS. For API or UI changes, manually test with disposable jobs and describe what was actually tested. Include the ComfyUI version or commit for compatibility changes. Do not claim live-server validation based only on mocked tests.

Queue actions must retain confirmation dialogs and clear recovery messages. Do not silently clear queues, interrupt unrelated jobs, or introduce telemetry. Changes to progress observation should document any internal ComfyUI API dependency.

By submitting a contribution, you agree that it can be distributed under the repository's MIT license.
