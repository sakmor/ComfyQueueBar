<p align="center"><img src="../../assets/app-icon.png" width="112" alt="ComfyQueueBar 圖示" /></p>

# ComfyQueueBar

**在 macOS 選單列，一鍵查看 ComfyUI 佇列。** 查看執行中的工作、目前節點進度，並決定下一個執行的工作。

**讓 Agent 把 token 花在製作影片上，進度交給 ComfyQueueBar。**

長時間生成影片時，Agent 若反覆查詢「完成了嗎」，每次模型回合與工具結果都可能消耗 token。ComfyQueueBar 讓 Agent 訂閱指定工作一次，由 App 與程式化等待接手監控，再於事件抵達或你回到對話時處理結果，減少重複查進度的 token 消耗。

[詳細教學：安裝、訂閱、續查與 token 節省原理](AGENT_TOKEN_GUIDE.zh-TW.md)

App 自行監控不會呼叫語言模型；Agent 處理結果仍會使用 token。實際節省取決於原本查詢頻率、模型與影片耗時，目前未量測固定節省比例。標準 MCP 不會自動喚醒閒置對話。

[English](../../README.md) · [简体中文](README.zh-CN.md) · **繁體中文** · [日本語](README.ja.md)

最新版介面使用虛構示範工作與自製範例圖片；桌面圖為原生 macOS 截圖。

<img src="../images/queue-light.png" width="360" alt="ComfyQueueBar v1.4.1" />

## 看看它怎麼用

**點選 macOS 選單列圖示，就能展開佇列面板。**

![macOS 桌面上的 ComfyQueueBar 選單列圖示與佇列面板](../images/desktop-menubar.png)

這是真實 macOS 桌面截圖，面板使用文件示範模式與固定範例工作；不含私人桌面內容或即時工作流程。App 支援英文、簡體中文、繁體中文與日文，依 macOS 偏好語言顯示。GitHub 截圖維持英文，以下按鈕名稱以英文對照說明。更改系統語言或 App 語言後，請重新啟動 App。

<details>
<summary>查看淺色與深色介面</summary>

![淺色介面](../images/queue-light.png)
![深色介面](../images/queue-dark.png)

</details>

## 最近完成與新功能

每 **15 秒**讀取最新 **200 筆**伺服器歷史，可依最近一小時、24 小時、今天或已載入歷史篩選，並搜尋工作名稱或輸出檔名。未提供時間的紀錄只出現在「已載入歷史」。展開「失敗與中斷」可查看伺服器錯誤原因；清除 ComfyUI 歷史也會移除這些紀錄。

- **媒體預覽與下載**：點選縮圖或 Preview & download…，選擇輸出後原生預覽圖片／影片，再透過 Download… 選擇儲存位置。MP4、MOV、M4V 需 macOS 支援其編碼，其他格式仍可下載。
- **通知**：齒輪設定可選關閉、每項完成或佇列完成通知，並另開失敗／斷線提醒。預設關閉，開啟需 macOS 授權；首次連線不通知舊歷史。
- **多伺服器**：輸入位址與名稱，按 Save address；點選面板頂端伺服器名稱可快速切換，一次監看一台。
- **時間估算**：顯示 App 首次觀察後的執行時間；至少三筆設定相近且有起訖時間的成功工作才估算剩餘時間，負載與快取可能影響準確度。

<img src="../images/settings.png" width="360" alt="英文伺服器與通知設定" />

## 功能與需求

- 原生 SwiftUI 工具，沒有 Dock 視窗，不使用 Electron；自動更新使用開源 Sparkle 框架。
- 選單列顯示執行中與等待中工作的總數；兩份清單每 **4 秒**更新。
- 顯示工作流程名稱、簡短 prompt ID、節點數與等待順序。
- **Prioritize（優先執行）**：確認後將等待中的工作移至佇列前端。
- **Stop（停止）**：確認後要求中斷執行中的工作，保留等待佇列。
- 安裝選用的伺服器擴充後，每 **1 秒**更新目前節點名稱與百分比。
- 儲存伺服器位址，支援手動更新、本機連線與 SSH 轉送。

| 項目 | 需求 |
| --- | --- |
| Mac | macOS 13 Ventura 或更新版本 |
| 編譯 | Swift 5.9 或更新版本；由適用的 Xcode／Command Line Tools 提供 |
| ComfyUI | 可存取 `/queue`、`/prompt`；指定工作停止需 `/interrupt` 支援 `prompt_id` |
| 節點進度 | ComfyUI 提供 `comfy_execution.progress.ProgressHandler`、`add_progress_handler`、`execution.reset_progress_state` |
| 擴充環境 | 使用 ComfyUI 本身的 Python 環境與既有 `aiohttp` |

App 僅支援 macOS；遠端 ComfyUI 可在 macOS、Linux 或 Windows 執行。建置產生目前 Mac 架構的程式，並非 universal binary。舊版或第三方 ComfyUI 的相容性可能不同。

## 下載 Mac App

[ComfyQueueBar — Apple Silicon ZIP](https://github.com/sakmor/ComfyQueueBar/releases/latest/download/ComfyQueueBar-macOS-arm64.zip)

需要 macOS 13 或更新版本與 Apple Silicon（M1 或更新晶片）。下載 ZIP 後解壓縮，將 `ComfyQueueBar.app` 移至「應用程式」並開啟，不需安裝 Swift 或 Xcode。Intel Mac 請使用下方原始碼建置步驟。

此版本使用 ad-hoc 簽章，尚未經 Apple 公證。如 macOS 阻擋開啟，先嘗試開啟，再到「系統設定 → 隱私權與安全性」選擇「強制打開」並確認；僅對本倉庫 Release 下載的檔案操作。

## 自動更新

v1.2.0 起會自動檢查（通常每 24 小時）、下載並在適當時機安裝已簽章的更新。面板提供「自動更新 App」開關與「檢查更新」按鈕。請將 App 放在可寫入的應用程式資料夾；v1.1.0 或更舊版本需先手動下載新版一次。GitHub 截圖維持英文，未展示新增的更新控制項。

## 用 Skill 讓 AI 查詢工作

先看 [Agent 省 token 實作教學](AGENT_TOKEN_GUIDE.zh-TW.md)，內含可直接貼上的指令、如何取得完整 prompt ID、結果判讀與疑難排解。

1. 安裝最新版 App 並連線至 ComfyUI。
2. 開啟 **設定 → AI Agent 整合 → 一鍵設定 Claude／Codex**，然後重新開啟代理對話。更新 App 後再次執行設定，即可更新已安裝的 skill 與 MCP adapter；被取代的 skill 會備份。
3. 在 Codex 輸入 `$comfyqueuebar 檢查連線`；Claude Code 使用 `/comfyqueuebar 檢查連線`。
4. 查詢已有工作：`$comfyqueuebar 確認 prompt ID <prompt_id> 的結果`。保留代理回傳的訂閱 ID，下次輸入 `$comfyqueuebar 繼續查詢訂閱 <subscription_id>`。Claude Code 改用 `/comfyqueuebar` 前綴。

將佔位文字換成真實 ID。Skill 不會提交工作或變更佇列，通常只等待一次、最長 45 秒；逾時不代表工作失敗或完成，仍可用訂閱 ID 續查。標準 MCP 不會自動喚醒閒置對話，可啟用 App 完成／失敗通知後回到對話續查。詳見[完整教學與疑難排解（英文）](../AGENT_INTEGRATION.md#use-the-comfyqueuebar-skill)。

## 快速開始

### 1. 準備編譯工具

```sh
xcode-select --install
swift --version
```

已安裝工具可跳過安裝。請確認 Swift 至少為 5.9；版本太舊時更新 Command Line Tools，或選用適用的 Xcode。

### 2. 下載並建置

```sh
git clone https://github.com/sakmor/ComfyQueueBar.git
cd ComfyQueueBar
bash build-app.sh
open build/ComfyQueueBar.app
```

腳本編譯 release 程式、建立 App bundle 並使用本機 ad-hoc 簽章；只重建此 repository 的 `build/ComfyQueueBar.app`，不會安裝或啟動 ComfyUI。

### 3. 連線

1. 啟動你現有的 ComfyUI。
2. 點選 macOS 選單列上的 ComfyQueueBar 圖示。
3. 在齒輪設定的 **ComfyUI address** 輸入位址，通常為 `http://127.0.0.1:8188`。
4. 點選 **Connect**。
5. 在 ComfyUI 提交工作，下一次更新時應出現在面板。

空佇列與未連線都可能顯示 0，請查看面板的連線狀態。也可直接檢查：

```sh
curl --fail http://127.0.0.1:8188/queue
```

### 4. 啟用節點進度（選用）

基本佇列監看不需要擴充。要查看節點進度，請安裝到**實際提供連線端點的 ComfyUI**：

```sh
bash install-comfyui-extension.sh /path/to/ComfyUI
# 路徑有空格時加上引號
bash install-comfyui-extension.sh "$HOME/AI Tools/ComfyUI"
```

等待生成結束後重新啟動 ComfyUI，再檢查：

```sh
curl --fail http://127.0.0.1:8188/comfyqueuebar/queue-progress
```

尚未回報進度時，回應中的 null 值屬正常。App 只顯示 prompt ID 與執行中工作相符的進度。**百分比是目前節點的進度，不是整個工作流程的完成度**；換節點時可能重新開始，有些節點不回報百分比。遠端連線需將擴充安裝在伺服器上。

## 安裝與登入時啟動

```sh
mkdir -p "$HOME/Applications"
cp -R build/ComfyQueueBar.app "$HOME/Applications/"
open "$HOME/Applications/ComfyQueueBar.app"
```

替換前先結束現有 App。需要登入時啟動，可在 macOS「系統設定 → 一般 → 登入項目」加入 App；名稱依系統版本可能不同，App 不會自動註冊。

## 操作的實際行為

**Prioritize** 使用 `front: true` 重新提交選取的工作流程，再刪除原本的等待項目，因此 prompt ID 會改變，不會中斷目前執行的工作。這是多次請求的操作；中途斷線或原工作開始執行時，可能發生競態或重複項目。App 會嘗試復原，無法確認結果時回報 ID；重試前請先檢查佇列。

**Stop** 重新確認佇列後，將選取的 prompt ID 傳給 `/interrupt`，不清除等待工作。相容伺服器會中斷指定工作，下一項可能接著開始。舊伺服器可能忽略 ID 而執行全域中斷。

重新提交保留 `/queue` 回傳的 prompt graph 與 `extra_data`，無法保留 API 未回傳的私有欄位或提交選項。含外部副作用或付費 API 節點的工作，重新提交前請確認影響。

## 隱私與遠端連線

佇列請求傳送至設定的 ComfyUI 位址；更新檢查與下載另外使用 GitHub。沒有分析、遙測或雲端帳號，Sparkle 系統資訊回報已關閉。位址與更新偏好儲存在 macOS user defaults，佇列回應可能包含工作流程 metadata。

擴充新增唯讀 JSON 路由，透過 ComfyUI 內部進度 registry 觀察進度，並包裝 reset 函式以逐工作重新註冊；不開 WebSocket、不修改佇列。路由沿用伺服器的網路曝露範圍，**不會自動限制為 localhost**。建議使用可信任網路或 SSH port forwarding。

App 沒有自訂 API key、bearer token 或登入介面；請求會捨棄網址的 query 與 fragment，因此不支援 query-string 憑證。

## 進一步文件（英文）

- [完整操作說明](../USAGE.md)
- [遠端連線、SSH 與 Windows 設定](../REMOTE_SETUP.md)
- [疑難排解、更新與移除](../TROUBLESHOOTING.md)
- [架構、API、測試與相容性](../DEVELOPMENT.md)
- [安全說明](../../SECURITY.md)、[貢獻指南](../../CONTRIBUTING.md)、[更新紀錄](../../CHANGELOG.md)

## 授權與致謝

採用 [MIT 授權](../../LICENSE)。源自 AniClayFilm repository 中供 [Clay Trouble](https://www.youtube.com/@ClayTrouble) 使用的工具；獨立版本具有多語介面、獨立 App identifier 與進度端點，不包含影片素材、工作流程、模型或憑證。

[ComfyUI](https://github.com/Comfy-Org/ComfyUI) 是獨立專案；ComfyQueueBar 是社群工具，並非官方產品，也未隨附 ComfyUI 原始碼。
