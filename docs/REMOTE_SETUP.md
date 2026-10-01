# Remote ComfyUI setup

The Mac app can monitor a ComfyUI server on another machine. An SSH tunnel is useful because it keeps the app connected to a local address and avoids exposing ComfyUI directly to the internet.

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

Set **ComfyUI address** to `http://127.0.0.1:18188` and click **Connect**. If your local ComfyUI already uses `8188`, it is unaffected by this separate tunnel port.

The app does not reconnect SSH, store SSH credentials, or keep the remote server awake. Reopen the tunnel if the SSH session ends.

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

There is no custom authentication-header UI, browser-login flow, or query-token support. If your host requires these, use an SSH tunnel or another trusted compatible access method. Never make ComfyUI publicly accessible just to connect this app.
