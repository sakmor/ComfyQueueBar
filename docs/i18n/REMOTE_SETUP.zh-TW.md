# 遠端 ComfyUI 設定教學

[English](../REMOTE_SETUP.md) · [简体中文](REMOTE_SETUP.zh-CN.md) · **繁體中文** · [日本語](REMOTE_SETUP.ja.md)

本教學涵蓋 GPUtw 登入、辨認正確的 ComfyUI 服務、SSH 連線與遠端 Mac 喚醒。App 一次監控一台伺服器，數字代表該佇列「執行中＋等待中」的工作數。

第一次連線 GPUtw？先看[影片佇列圖文快速入門](GPUTW_SETUP.zh-TW.md)，包含版本準備、登入步驟、連接埠核對，以及真實影片佇列和完成紀錄截圖。

**適用版本：** GPUtw 內建登入、連線確認卡、連線狀態符號與 Wake-on-LAN 已加入目前的 `main` 原始碼，尚未包含在 v1.5.2 下載版。新版發行前，請依 [原始碼編譯教學](README.zh-TW.md)建置使用。

## GPUtw 私人或密碼保護的執行個體

### 登入並選擇服務

1. 保持租用的執行個體運行。在 ComfyQueueBar 點齒輪 → **登入 GPUtw…**。也可以在 **ComfyUI 位址** 貼上 `https://gputw.ai/dashboard`，按 **連線** 開啟相同流程。
2. 在 App 內的瀏覽器登入。Safari、Chrome 的登入狀態不會自動共用。
3. 開啟執行個體的 **ComfyUI Web UI**。若生成使用其他已設定的 HTTP 連接埠，請從控制台開啟該連接埠的 Web UI；密碼保護的連接埠須在 GPUtw 頁面輸入密碼。
4. 按 **確認此 ComfyUI**，核對連接埠、執行中／等待中工作數與最近三筆成功工作。確認卡讀取佇列及最新最多 20 筆歷史；歷史無法讀取時會標示未知，佇列驗證失敗則不能確認。
5. 按 **監控此伺服器**，才會儲存並選用此 GPUtw 服務。按 **取消** 會保留目前的監控連線。主畫面與選單列提示會顯示選用的連接埠。
6. 可將 **伺服器名稱** 改成容易辨認的名稱，例如 `GPUtw · 8090 · 影片生成`，再按 **儲存位址**。透過 GPUtw 重新連線會保留既有的自訂名稱。

GPUtw 服務位址格式為 `https://<port>-<instance-id>.gputw.ai`。私人服務需要控制台建立擁有者登入狀態；密碼保護的服務會先顯示密碼頁。維持既有存取模式即可，這個登入流程不需要平台 API 金鑰或公開連接埠。參考 [GPUtw Web UI](https://docs.gputw.ai/zh-TW/docs/jupyter-web-ui) 與[連接埠存取模式](https://docs.gputw.ai/zh-TW/docs/ports)。

### GPU 很忙，但 App 顯示 0

同一個 GPU 執行個體的不同連接埠，可能分別運行獨立的 ComfyUI。例如 `8080` 開啟預設服務，`8090` 運行自訂影片環境。這只是範例，實際連接埠以你提交工作的 ComfyUI 位址為準。

1. 比較生成頁面的連接埠與 ComfyQueueBar 顯示的連接埠。
2. 按 **查看此連線**，或選擇想使用的已儲存伺服器，先查看近期工作。
3. 比對工作名稱與完成時間。空佇列加上不相關的歷史，可能代表連錯服務；讀不到歷史不能視為工作已完成。
4. 若正確服務的佇列為空，查看 **最近完成** 與 **失敗與中斷**。工作可能已在兩次更新之間結束。

GPU 使用率與已配置 VRAM 都不是 ComfyUI 工作數。App 目前不讀取 GPU 使用率、不自動搜尋所有連接埠，也不合併多個服務的佇列；只會每四秒檢查選用的佇列。不要只因看到 0 就重新提交同一工作。

### 選單列符號

| 顯示 | 意義 | 建議操作 |
| --- | --- | --- |
| `0` | 最新有效回應確認目前佇列為空 | 若預期有工作，核對連接埠與近期紀錄 |
| `1`–`99`、`99+` | 執行中＋等待中工作數 | 開啟面板看詳情；選單列提示顯示完整總數 |
| `—` | 斷線、佇列回應格式錯誤，或超過 30 秒未取得最新佇列 | 檢查連線；目前工作數未知 |
| `!` | 需要登入 | GPUtw 請重新登入並開啟執行個體 Web UI |
| `…` | 等待首次佇列回應 | 等待連線確認完成 |

取得有效佇列後會自動恢復工作數。歷史或節點進度讀取失敗，不會把正常佇列判成斷線。0 本身不代表成功；成功工作必須有明確的成功歷史紀錄。

### 登入、輸出與恢復

- 登入過期時，再按 **登入 GPUtw…**，開啟正確連接埠、查看確認卡並確認。只開啟控制台或 Jupyter 頁面不能識別 ComfyUI 服務。
- **清除 GPUtw 登入** 會移除這個 App 的瀏覽器登入資料，包含帳號與執行個體 session；不會登出其他瀏覽器或停止租用的 GPU。
- 儲存的服務位址會移除 handoff 路徑、query token 與 fragment。Cookie 留在 App 的 WebKit 儲存區，不會寫入書籤或 Agent 橋接檔。詳見[安全說明](../../SECURITY.md)。
- 圖片與下載會套用登入狀態。受保護的影片預覽會先下載暫存副本，關閉或切換預覽後移除；影片縮圖會顯示占位圖示。
- 節點百分比需要將進度擴充安裝到**同一套遠端 ComfyUI**。Mac 上的安裝按鈕只安裝到本機；雲端伺服器請依下方方式處理。
- 若身分提供者不允許內嵌瀏覽器登入，可使用既有且相容的 SSH 連線；不要為了登入而停用存取控制。

## 喚醒遠端 Mac

Wake-on-LAN 是每個已儲存伺服器的選用設定，透過 UDP 傳送指定網卡 MAC 位址的 magic packet。它不會啟動已停止的 GPUtw 租用執行個體、啟動 ComfyUI 或建立 SSH 通道。

### 設定與測試

1. 在目標 Mac 的系統設定啟用可用的 **喚醒以供網路存取** 選項。機型、供電、網路與 macOS 設定都會影響支援情況，參考 [Apple 喚醒說明](https://support.apple.com/en-gb/guide/mac-help/mh27905/mac)。
2. 在 ComfyQueueBar 輸入目標 ComfyUI 位址與名稱，按 **儲存位址**。儲存書籤不要求睡眠中的伺服器立即回應。
3. 展開該位址下的 **喚醒 Mac**，填入目標網卡的 **MAC 位址**、網路允許的 **廣播 IPv4 位址** 與 **UDP 連接埠**。預設是 `255.255.255.255` 與 `9`，請依實際網路調整。`02:11:22:33:44:55` 僅為範例 MAC。
4. 按 **儲存喚醒設定**，再按 **立即喚醒**。立即喚醒也會先驗證並儲存畫面上的設定。
5. 「已傳送喚醒封包」只代表本機傳送成功。等待目標醒來且 ComfyUI 可連線，再選擇書籤、檢查確認卡並按 **監控此伺服器**。
6. 若需要，勾選 **離線時自動喚醒** 並再次儲存。只要目前選用的是這台伺服器，符合條件的網路離線錯誤就可能觸發封包，每台伺服器最多每兩分鐘一次。HTTP 錯誤與登入失敗不會觸發喚醒。取消勾選並儲存即可停用。

執行 ComfyQueueBar 的 Mac 必須保持醒著，App 也必須持續運行。手動 **立即喚醒** 可用於任一已儲存伺服器；自動喚醒只處理目前選用的伺服器，不會輪詢其他書籤。

### 目標仍然睡眠時

確認網卡 MAC、喚醒設定、供電狀態與 UDP 目的地是否可達。廣播封包不會透過 App 的 SSH 通道傳送，也不會自動跨路由器／VPN 轉送。請使用既有可用的區網路徑；App 不會設定路由器、防火牆或轉送服務。封包傳送成功不等於實體 Mac 已醒來；醒來後仍須確認 ComfyUI 與 SSH 通道可用。

## SSH 連線與遠端進度設定

以下範例使用本機 `18188`、遠端 ComfyUI `8188`，請換成實際連接埠。

### 1. 確認遠端服務

在運行 ComfyUI 的機器執行：

```sh
curl --fail http://127.0.0.1:8188/queue
```

沿用原本的 ComfyUI 啟動方式；本 App 不會安裝 ComfyUI 或模型。

### 2. 從 Mac 建立通道

```sh
ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 \
  -L 127.0.0.1:18188:127.0.0.1:8188 user@your-server
```

替換 `user@your-server`。自訂 SSH 連接埠可加 `-p 2222`；需要私鑰時加 `-i /path/to/private-key`，切勿提交私鑰。本機端綁定 `127.0.0.1`，不會向區網開放。保持終端機運行，Control-C 結束通道。若 ComfyUI 在容器裡，遠端目的地必須是 SSH 主機可到達的連接埠；主機的 localhost 不一定是容器的 localhost。

### 3. 連接 App

```sh
curl --fail http://127.0.0.1:18188/queue
```

將 **ComfyUI 位址** 設為 `http://127.0.0.1:18188`，按 **連線**，核對佇列與歷史，再按 **監控此伺服器**。這個獨立的通道連接埠不影響本機 `8188` 的 ComfyUI。App 不保存 SSH 憑證或自動重建 SSH 通道，也不會讓遠端機器持續保持醒著；通道中斷後需自行重開。

### 4. 安裝遠端進度擴充

Linux／macOS 伺服器上執行：

```sh
git clone https://github.com/sakmor/ComfyQueueBar.git
cd ComfyQueueBar
bash install-comfyui-extension.sh /path/to/ComfyUI
```

也可以將本機的 `comfyui_extension/ComfyQueueBarProgress/` 複製到遠端 `ComfyUI/custom_nodes/`。伺服器不需要 Swift。目標檔案應是 `ComfyUI/custom_nodes/ComfyQueueBarProgress/__init__.py`，不要多加一層目錄。

Windows 請透過檔案總管複製同一個資料夾到實際安裝位置的 `custom_nodes`；portable 版通常位於其 `ComfyUI` 子目錄。手動複製不需要 Bash；只有選用 SSH 通道時才需要 Windows SSH 伺服器。

等待目前生成結束，再重新啟動**該套** ComfyUI。從 Mac 經同一通道驗證：

```sh
curl --fail http://127.0.0.1:18188/comfyqueuebar/queue-progress
```

## 直接使用區網或 HTTPS

可信任區網可以使用 `http://192.0.2.10:8188` 這類位址，請換成真實位址。伺服器須監聽正確介面，防火牆與 macOS 區域網路權限須允許連線。

HTTPS 反向代理可使用 `https://comfy.example.com` 或 `https://comfy.example.com/comfy` 路徑前綴，並轉送 ComfyUI API 與 `/comfyqueuebar/queue-progress`；憑證必須受 macOS 信任。非本機 HTTP 可能受系統傳輸安全限制，SSH loopback 通道通常較容易配合現有 App 設定。

內建瀏覽器登入目前只針對 GPUtw。其他主機若需要自訂驗證 header 或 query token，請使用相容的 SSH 或既有可信任存取方式。不要只為連接 App 就將 ComfyUI 公開到網際網路。

自動測試使用模擬 API 與本機 UDP 接收器，不能證明每個 GPUtw 帳號均能登入，或每種 Mac／網路都能實際喚醒。
