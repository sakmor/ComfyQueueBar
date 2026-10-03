# 把影片進度監控交給 App：Agent 省 token 實作教學

影片生成可能需要數分鐘甚至更久。如果 Agent 每隔幾秒就發起新的模型回合、查詢進度、解讀回覆，等待期間也會累積 token 消耗。ComfyQueueBar 讓 App 持續監控指定工作，Agent 只在設定訂閱、收到事件或你回到對話時處理結果。

**適合的情境：你已經有 ComfyUI 影片工作，想知道何時完成，又不想讓 Agent 一直反覆問進度。** 這套方法也適用於圖片工作。

## 1. 安裝 App、MCP 與 skill

1. 從 [GitHub Release](https://github.com/sakmor/ComfyQueueBar/releases/latest) 下載最新版 Apple Silicon App。需要 macOS 13 以上；Intel Mac 請依 [README](../../README.md#build-from-source) 自行建置。
2. 開啟 App，在齒輪設定填入 ComfyUI 位址並連線。遠端伺服器可使用 [SSH 轉送](../REMOTE_SETUP.md)。
3. 開啟 **AI Agent 整合**，按 **一鍵設定 Claude／Codex**。MCP adapter 需要 Python 3.9 以上；Codex 自動註冊需要可用的 Codex CLI。
4. 查看設定結果。MCP 註冊與 skill 安裝分別回報，skill 安裝成功不代表 MCP 已連線。
5. 重新開啟 Agent 對話；若仍看不到工具，重新啟動代理桌面 App。

設定會安裝 MCP adapter 與共用 skill，並備份被取代的設定／skill。更新 ComfyQueueBar 後，請再次按一鍵設定，再重開 Agent 對話。

App 必須持續執行，Mac 必須保持喚醒。休眠、關閉 App 或關閉整合期間不會繼續監控。

## 2. 先確認連線

在 Codex 貼上：

```text
$comfyqueuebar 檢查連線，告訴我 App、ComfyUI 與歷史紀錄是否可用。
```

Claude Code 改用：

```text
/comfyqueuebar 檢查連線，告訴我 App、ComfyUI 與歷史紀錄是否可用。
```

正常情況應回報 App 可用、ComfyUI 已連線、歷史可用，以及執行中／等待中數量。零個工作也可能是正常的空佇列，請以連線狀態判斷。

這一步只讀取狀態一次，不會提交工作或建立訂閱。

## 3. 取得正確的 prompt ID

`prompt_id` 是 ComfyUI 分配給某次工作提交的完整識別碼，不是工作流程名稱、檔名、節點 ID，也不是你輸入的生成提示文字。

- **由 Agent 或程式提交：** 使用 ComfyUI `/prompt` 回應中的完整 `prompt_id`。同一對話已有該次提交的 ID 時，可直接要求 Agent 使用那個 ID。
- **由 ComfyUI 介面提交：** 可在瀏覽器開發者工具的 Network 面板找到此次提交的 `/prompt` 請求，查看 JSON 回應中的 `prompt_id`。請確認提交時間與工作相符。
- **已在執行或等待的工作：** ComfyUI `/queue` 的 `queue_running`、`queue_pending` 中，每筆工作陣列的第二個欄位是完整 ID。必須先確認是哪一筆工作；不要把第一筆當成你的工作。

App 面板可能只顯示縮短的 ID，請不要用縮短版本訂閱。下面的 `YOUR_PROMPT_ID` 都要換成你的真實完整 ID。

## 4. 訂閱一次，讓 App 接手

在 Codex 貼上：

```text
$comfyqueuebar 確認我已提交的 ComfyUI 影片工作，prompt ID 是 YOUR_PROMPT_ID。
只訂閱這個工作，等待一次，不要反覆查進度。
回報實際狀態與 subscription_id，讓我之後可以續查。
```

Claude Code 將第一行的 `$comfyqueuebar` 改成 `/comfyqueuebar`。

Agent 會確認連線、使用 App 回傳的伺服器位址建立訂閱，並保留 `subscription_id`。若已取得終態結果，就直接處理；否則通常等待一次、最長 45 秒，主機限制可能讓等待更短。

這個等待由程式檢查事件，不會每隔一秒呼叫模型。工具回傳後，Agent 仍需要一個模型回合來解讀結果。

| 回報狀態 | 代表什麼 | 下一步 |
| --- | --- | --- |
| queued | 還在等待佇列 | 保存訂閱 ID，稍後續查 |
| running | 正在執行 | 由 App 持續監控，稍後續查 |
| completed | 明確完成 | 可要求輸出參照或檢查影片 |
| failed / interrupted | 明確失敗或中斷 | 查看錯誤，再決定後續處理 |
| unknown | 尚無法確認 | 確認 ID、歷史與伺服器，勿當成成功 |

逾時、斷線、歷史不可用是等待／監控狀況，不能直接推論工作成功或失敗。訂閱 ID 與 prompt ID 不同：前者用來續查監控紀錄，後者識別 ComfyUI 工作。

## 5. 等 App 通知，再回來續查

在 App 設定中開啟需要的完成／失敗通知，並允許 macOS 通知。通知可作為回到對話的提醒；App 通知依其佇列與通知設定運作，請仍用訂閱結果確認你指定的工作。

**標準 MCP 不會在影片完成時自動喚醒閒置的 Codex 或 Claude 對話。** App 會保存監控結果，等你回來讀取。不要讓 Agent 每隔 45 秒再呼叫一次等待，也不要建立每分鐘喚醒模型的自動化。

稍後在 Codex 貼上：

```text
$comfyqueuebar 繼續查詢訂閱 YOUR_SUBSCRIPTION_ID。
讀取已保存的結果；若還沒完成，只等待一次，不要循環查詢。
```

重新開啟對話後，也可提供保存的訂閱 ID。Skill 使用 `resume_subscription` 接回原訂閱，不必為同一個工作重建訂閱。

如果你只想知道目前紀錄、不要等待，可以說：

```text
$comfyqueuebar 讀取訂閱 YOUR_SUBSCRIPTION_ID 的已保存結果，這次不要等待。
```

## 6. 完成後取回輸出或安排下一步

Skill 預設提供簡短狀態；若需要影片輸出資訊，請明確提出：

```text
$comfyqueuebar 查詢訂閱 YOUR_SUBSCRIPTION_ID，若工作已完成，列出影片輸出參照。
```

輸出參照包含 ComfyUI 檔名、子資料夾及 `/view` URL，並不代表影片已下載到 Agent 的本機。也可直接在 App 完成歷史中開啟 **Preview & download…** 預覽與下載。

若希望 Agent 完成後處理影片，請另外給出具體指示，例如「確認完成後，將影片下載到指定資料夾並檢查時長」。下載、剪輯或再次提交工作需要相應工具與明確任務；這個 skill 本身只負責查詢既有工作。

完成、失敗或中斷後，這個流程建立的驗證訂閱會結束監控，記錄仍保留；從其他流程續接的訂閱則不會任意取消。取消監控訂閱也不會停止 ComfyUI 工作。

## token 具體省在哪裡？

| 階段 | Agent 反覆查進度 | 使用 ComfyQueueBar |
| --- | --- | --- |
| 設定 | Agent 決定如何查詢 | Agent 確認連線並訂閱一次 |
| 等待生成 | 每次模型回合可能查詢、解讀進度、決定再查 | App 定時器與 MCP 程式化等待監控，不呼叫語言模型 |
| 結果處理 | Agent 解讀完成或錯誤 | Agent 在事件回傳或你續查時解讀結果 |

例如，影片生成要 10 分鐘，原本若每 10 秒發起一個模型回合檢查，可能累積約 60 次檢查。改成一次訂閱、一次有界等待，再於完成後續查，就能避免那些重複進度查詢回合。這是工作流程示例，**不是 token 基準測試或固定節省比例**；結果事件也可能提前結束等待。

真正減少的是等待期間的重複模型工作。訂閱設定、工具結果、失敗處理與後續影片處理仍會使用 token。若原本就由一般程式監控、沒有模型反覆參與，這部分的 token 節省可能很少。

## 常見問題

| 問題 | 處理方式 |
| --- | --- |
| 找不到 skill | 重新執行一鍵設定，確認 skill 安裝成功，重開對話 |
| 有 skill，但找不到 MCP 工具 | 查看一鍵設定的 MCP 註冊結果與代理的 MCP 清單；Claude Code 可用 `/mcp` |
| App 不可用 | 確認 App 已執行、整合已啟用、Mac 未休眠；心跳過期會回報不可用 |
| 工作一直 unknown | 確認完整 ID、正確伺服器與 ComfyUI 歷史；歷史被清除不能推論完成 |
| 切換伺服器後不更新 | 原訂閱暫停，切回原伺服器；訂閱不會自動移到另一台 |
| 優先執行後查不到原工作 | Prioritize 會重新提交並改變 prompt ID，確認新 ID 後再訂閱 |
| 等待逾時 | 保存訂閱 ID，等通知或稍後手動續查；不要循環喚醒模型 |
| 希望完成後自動繼續 | 標準 MCP 不提供閒置喚醒；Claude Channels 屬實驗支援，需確認實際入站推送，不能僅憑註冊成功認定可用 |

需要手動 MCP 設定、傳遞模式與資料保存細節，請閱讀 [完整整合文件（英文）](../AGENT_INTEGRATION.md)。Skill 原始內容見 [SKILL.md](../../.agents/skills/comfyqueuebar/SKILL.md)。
