# Remote ComfyUI setup

**English** · [简体中文](i18n/REMOTE_SETUP.zh-CN.md) · [繁體中文](i18n/REMOTE_SETUP.zh-TW.md) · [日本語](i18n/REMOTE_SETUP.ja.md)

This guide covers GPUtw login, choosing the correct ComfyUI service, SSH connections, and waking a remote Mac. One server is monitored at a time; the number represents running plus waiting ComfyUI jobs.

**Availability:** GPUtw browser login, connection review, distinct connection badges, and Wake-on-LAN are available in the current `main` source. They are not included in the v1.5.2 download. [Build from source](../README.md#build-from-source) to use them before the next release.

## GPUtw private and password-protected instances

### Sign in and select the service

1. Keep your rented instance running. In ComfyQueueBar, open the gear → **Sign in to GPUtw…**. Pasting `https://gputw.ai/dashboard` in **ComfyUI address** and clicking **Connect** opens the same flow.
2. Sign in inside the app's browser. A Safari or Chrome session is not automatically reused.
3. Open the instance's **ComfyUI Web UI**. If generation uses another configured HTTP port, open that port's Web UI from the dashboard. Enter the port password on the GPUtw page if prompted.
4. Click **Review this ComfyUI**. Check the port, running/waiting counts, and the three most recent successful jobs. The review reads the queue and up to 20 history records. If history is unavailable, it is marked unknown; a failed queue check prevents confirmation.
5. Click **Monitor this server** to save/select this GPUtw service. **Cancel** keeps your existing monitoring connection. The main panel and menu-bar tooltip identify the selected port.
6. Optionally give the bookmark a recognizable **Server name**, such as `GPUtw · 8090 · Video`, then **Save address**. Reconnecting through GPUtw preserves an existing custom name.

GPUtw uses service addresses such as `https://<port>-<instance-id>.gputw.ai`. Private services require the dashboard's owner-session handoff; password-protected services present a password page. Keep the existing access mode. This login flow needs no platform API key or public port. See [GPUtw Web UI](https://docs.gputw.ai/zh-TW/docs/jupyter-web-ui) and [port access modes](https://docs.gputw.ai/zh-TW/docs/ports).

### GPU is busy, but the app shows 0

Different ports on one GPU instance can run independent ComfyUI processes. For example, `8080` might open a default service while `8090` runs a custom video environment. These are examples, not universal port assignments. Check the address of the ComfyUI where you submitted the job.

1. Compare that port with the port in ComfyQueueBar.
2. Use **Review this connection**, or select the intended saved server, to inspect recent work before switching.
3. Match the workflow title and completion time to your own job. An empty queue with unrelated history can indicate the wrong service; missing history is not proof of completion.
4. If the correct service's queue is empty, check **Recently completed** and **Failures & interruptions**. A job may have finished between refreshes.

GPU utilization and allocated VRAM are not ComfyUI job counts. This app does not currently read GPU utilization, automatically discover every port, or aggregate multiple services. It checks the selected queue every four seconds. Do not resubmit a job solely because this app shows 0.

### Read the menu-bar status

| Display | Meaning | What to do |
| --- | --- | --- |
| `0` | A fresh, valid response reports an empty selected queue | Check the selected port and recent history if you expect work |
| `1`–`99`, `99+` | Running plus waiting jobs in this queue | Open the panel for details; the tooltip has the exact total |
| `—` | Disconnected, invalid queue response, or no fresh queue response for 30 seconds | Check the connection; the count is unknown |
| `!` | Sign-in required | For GPUtw, sign in again and reopen the instance Web UI |
| `…` | Waiting for the initial queue response | Wait for the check to finish |

A successful queue response restores the count automatically. A history/progress failure does not turn a healthy queue into a disconnected queue. A zero count alone never establishes success; completed jobs require explicit successful history records.

### Login, outputs, and recovery

- For an expired login, use **Sign in to GPUtw…**, reopen the correct port, review it, and confirm. Opening only the dashboard or Jupyter page does not identify a ComfyUI service.
- **Clear GPUtw sign-in** removes this app's browser login data, including account and instance sessions. It does not sign out other browsers or stop the rented instance.
- The app saves the service origin, discarding handoff paths, query tokens, and fragments. Login cookies remain in the app's WebKit store, separate from bookmarks and agent bridge files. See [security details](../SECURITY.md).
- Images and downloads use the authenticated connection. Protected video previews download a temporary local copy before playback; closing/changing the preview removes it. Video thumbnails use a placeholder.
- Node percentages require the progress extension in the **same remote ComfyUI installation**. The Mac's extension-install button installs locally; use the remote instructions below for a cloud server.
- If an identity provider prevents embedded-browser login, use an existing compatible SSH connection. Do not disable access controls to work around login.

## Wake a remote Mac

Wake-on-LAN is optional and configured per saved server. It sends a UDP magic packet for a network interface's MAC address. It does not start a stopped GPUtw rental, launch ComfyUI, or establish an SSH tunnel.

### Configure and test

1. On the target Mac, enable the available **Wake for network access** option in System Settings. Hardware, power, network, and macOS settings affect wake support; see [Apple's wake guidance](https://support.apple.com/en-gb/guide/mac-help/mh27905/mac).
2. In ComfyQueueBar, enter the target ComfyUI address and a server name, then **Save address**. Saving a bookmark does not require the sleeping server to respond.
3. Expand **Wake Mac** below that saved address. Enter the target network interface's **MAC address**, your network's **Broadcast IPv4 address**, and **UDP port**. The defaults are `255.255.255.255` and `9`; use the actual destination permitted by your network. `02:11:22:33:44:55` is a sample MAC, not your device's address.
4. Click **Save wake settings**, then **Wake now**. This button also validates and saves the visible settings before sending.
5. A “packet sent” message only confirms that the local send succeeded. Wait for the target to wake and ComfyUI to become reachable, then select the bookmark, review the connection, and confirm **Monitor this server**.
6. Optionally enable **Automatically wake when offline** and save again. While this server is selected, qualifying network failures can trigger a packet, at most once every two minutes per server. HTTP errors and login failures do not trigger waking. Clear the checkbox and save to disable automatic waking.

The Mac running ComfyQueueBar must remain awake and the app must remain running. Manual **Wake now** can target any saved server; automatic waking applies only to the selected one. Other bookmarks are not polled.

### If the target stays asleep

Check the target interface's MAC address, wake setting, power state, and whether the network permits the UDP destination. Broadcast packets are not carried by the app's SSH tunnel or automatically relayed across routers/VPNs. Use a suitable existing LAN path; the app does not configure routers, firewall rules, or relay services. A successful packet send is not evidence that a physical Mac woke up. Once it wakes, ComfyUI and any SSH tunnel still need to be available.

## SSH connection and remote progress setup

An SSH tunnel keeps the Mac-side endpoint on loopback. The following examples use local port `18188` and remote ComfyUI port `8188`; replace them with your actual ports.

## 1. Verify the remote server

On the machine running ComfyUI:

```sh
curl --fail http://127.0.0.1:8188/queue
```

Replace `8188` if your server uses another port. Use your existing server startup procedure; ComfyQueueBar does not install ComfyUI or its models.

## 2. Open a tunnel from your Mac

```sh
ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 \
  -L 127.0.0.1:18188:127.0.0.1:8188 user@your-server
```

Replace `user@your-server` with your SSH destination. If SSH uses a different port, add `-p 2222` with your actual port. If a key is needed, add `-i /path/to/private-key`; never commit the key.

Here, `18188` is the Mac's local port, and `8188` is the remote ComfyUI port. Binding the local end to `127.0.0.1` keeps it off your LAN. Leave the terminal session running. To close the tunnel, press Control-C.

If ComfyUI runs inside a container, the remote end of the forwarding rule must point to a port reachable from the SSH host. An SSH host's `127.0.0.1` is not automatically the container's `127.0.0.1`.

## 3. Connect the app

On your Mac:

```sh
curl --fail http://127.0.0.1:18188/queue
```

Set **ComfyUI address** to `http://127.0.0.1:18188`, click **Connect**, review the queue/history, then click **Monitor this server**. If your local ComfyUI already uses `8188`, it is unaffected by this separate tunnel port.

The app does not reconnect SSH or store SSH credentials. Optional Wake-on-LAN sends a separate UDP packet and does not travel through this TCP tunnel or keep a server awake. Reopen the tunnel if the SSH session ends.

## 4. Install progress on the remote server

### Linux or macOS server

On the remote machine, clone this repository and run the installer:

```sh
git clone https://github.com/sakmor/ComfyQueueBar.git
cd ComfyQueueBar
bash install-comfyui-extension.sh /path/to/ComfyUI
```

Alternatively, transfer `comfyui_extension/ComfyQueueBarProgress/` from your Mac into the server's `ComfyUI/custom_nodes/` directory. No Swift build is needed on the server.

The final layout must be:

```text
ComfyUI/
└── custom_nodes/
    └── ComfyQueueBarProgress/
        └── __init__.py
```

Wait until active generation ends and restart the remote ComfyUI process. From your Mac, verify through the same tunnel:

```sh
curl --fail http://127.0.0.1:18188/comfyqueuebar/queue-progress
```

### Windows server

Copy the `ComfyQueueBarProgress` directory into the actual Windows ComfyUI installation's `custom_nodes` directory using File Explorer. For the portable distribution, this is usually inside its `ComfyUI` subdirectory. Do not copy only the parent `comfyui_extension` directory or add an extra nesting level.

The bundled installer is Bash-based; manual copying avoids requiring Bash on Windows. Restart ComfyUI after generation finishes. A Windows SSH server is required only if you choose SSH forwarding; use an existing trusted remote access setup.

## Direct LAN or HTTPS connection

A trusted LAN server can be entered directly, for example `http://192.0.2.10:8188` (replace this documentation address with your server's real address). Your server must listen on the relevant interface, its firewall must allow the connection, and macOS must allow the app's local-network access where prompted.

A reverse proxy can use an HTTPS base URL such as `https://comfy.example.com` or a path prefix such as `https://comfy.example.com/comfy`. The app appends API paths to the base path, so the proxy must forward both the standard ComfyUI API and `/comfyqueuebar/queue-progress`. Certificates must be trusted by macOS. Non-local plain HTTP may be constrained by macOS transport security; SSH forwarding is the most predictable HTTP setup with the bundled app configuration.

The built-in browser-login flow currently targets GPUtw. There is no generic custom authentication-header UI or query-token support. For other hosts that require these, use an SSH tunnel or another trusted compatible access method. Never make ComfyUI publicly accessible just to connect this app.

Automated tests use simulated APIs and a local UDP receiver. They do not establish login compatibility for every GPUtw account or physical wake support for every Mac/network.
