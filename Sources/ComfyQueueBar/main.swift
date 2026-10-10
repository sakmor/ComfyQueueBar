import AppKit
import Foundation
import SwiftUI
import WebKit
#if !DOCUMENTATION_SCREENSHOT
import Sparkle
#endif

#if !DOCUMENTATION_SCREENSHOT
@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()
    let controller: SPUStandardUpdaterController
    @Published var automaticallyUpdates: Bool {
        didSet {
            controller.updater.automaticallyChecksForUpdates = automaticallyUpdates
            controller.updater.automaticallyDownloadsUpdates = automaticallyUpdates
        }
    }

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        automaticallyUpdates = controller.updater.automaticallyChecksForUpdates && controller.updater.automaticallyDownloadsUpdates
    }

    func check() { controller.checkForUpdates(nil) }
}
#endif

// App-owned text is localized; server-provided workflow/node names remain unchanged.
enum L10n {
    static let language: String = {
        #if DOCUMENTATION_SCREENSHOT
        // Public documentation screenshots always use English. Preview overrides are test-only.
        return ProcessInfo.processInfo.environment["COMFYQUEUEBAR_PREVIEW_LANGUAGE"] ?? "en"
        #else
        return resolve(Locale.preferredLanguages)
        #endif
    }()

    static func resolve(_ preferences: [String]) -> String {
        for preference in preferences {
            let tag = preference.replacingOccurrences(of: "_", with: "-").lowercased()
            if tag == "ja" || tag.hasPrefix("ja-") { return "ja" }
            if tag == "zh" || tag.hasPrefix("zh-") {
                if tag.contains("hant") || (!tag.contains("hans") && (tag.contains("-tw") || tag.contains("-hk") || tag.contains("-mo"))) { return "zh-Hant" }
                return "zh-Hans"
            }
            if tag == "en" || tag.hasPrefix("en-") { return "en" }
        }
        return "en"
    }

    static var locale: Locale { Locale(identifier: language) }

    static func text(_ key: String, _ arguments: String...) -> String {
        let index = ["zh-Hant": 0, "zh-Hans": 1, "ja": 2][language]
        let format = index.flatMap { translations[key]?[$0] } ?? key
        return arguments.isEmpty ? format : String(format: format, locale: locale, arguments: arguments)
    }

    static let translations: [String: [String]] = [
        "Checking connection…": ["正在確認連線…", "正在检查连接…", "接続を確認中…"],
        "Sign-in required": ["需要重新登入", "需要重新登录", "再ログインが必要です"],
        "Queue status out of date": ["佇列資料已過期", "队列数据已过期", "キュー情報が古くなっています"],
        "Port %@": ["連接埠 %@", "端口 %@", "ポート %@"],
        "Confirm monitoring server": ["確認監控伺服器", "确认监控服务器", "監視するサーバーを確認"],
        "Reading queue and recent history…": ["正在讀取佇列與近期紀錄…", "正在读取队列与近期记录…", "キューと最近の履歴を読み込み中…"],
        "Your current monitoring server changes only after you confirm.": ["確認後才會切換目前監控的伺服器。", "确认后才会切换当前监控的服务器。", "確認後に監視先のサーバーを切り替えます。"],
        "Refresh details": ["重新讀取", "重新读取", "再読み込み"],
        "Monitor this server": ["監控此伺服器", "监控此服务器", "このサーバーを監視"],
        "Checked %@": ["確認時間 %@", "检查时间 %@", "確認時刻 %@"],
        "Counts show ComfyUI jobs, not GPU utilization.": ["數字代表 ComfyUI 工作數；GPU 使用率是另一項指標。", "数字代表 ComfyUI 任务数；GPU 使用率是另一项指标。", "数値は ComfyUI のジョブ数です。GPU 使用率とは別の指標です。"],
        "This queue is empty. If you expect a running job, check the port and recent work below.": ["此佇列目前沒有工作。如果你正在生成，請確認連接埠與下方近期紀錄。", "此队列当前没有任务。如果你正在生成，请检查端口与下方近期记录。", "このキューは空です。生成中のはずなら、ポートと下の最近の履歴を確認してください。"],
        "Found work on Port %@.": ["在連接埠 %@ 找到工作。", "在端口 %@ 找到任务。", "ポート %@ にジョブがあります。"],
        "No queued work on Port %@.": ["連接埠 %@ 目前也沒有排隊工作。", "端口 %@ 目前也没有排队任务。", "ポート %@ にもキュー内のジョブはありません。"],
        "Checking Port %@…": ["正在檢查連接埠 %@…", "正在检查端口 %@…", "ポート %@ を確認中…"],
        "GPUtw returned 404 on port %@. Enable it as an HTTP port in Network Ports, then open it from the dashboard's Other ports menu.": ["GPUtw 在連接埠 %@ 回傳 404。請先在 Network Ports 啟用 HTTP 連接埠，再從控制台的 Other ports 開啟一次。", "GPUtw 在端口 %@ 返回 404。请先在 Network Ports 启用 HTTP 端口，再从控制台的 Other ports 打开一次。", "ポート %@ で GPUtw が 404 を返しました。Network Ports で HTTP ポートを有効にし、ダッシュボードの Other ports から一度開いてください。"],
        "Port %@ needs an owner session. Open it from the GPUtw dashboard's Other ports menu.": ["連接埠 %@ 需要擁有者工作階段。請從 GPUtw 控制台的 Other ports 開啟。", "端口 %@ 需要所有者会话。请从 GPUtw 控制台的 Other ports 打开。", "ポート %@ には所有者セッションが必要です。GPUtw ダッシュボードの Other ports から開いてください。"],
        "Could not check GPUtw port %@. Check your connection and retry.": ["目前無法檢查 GPUtw 連接埠 %@。請確認連線後重試。", "目前无法检查 GPUtw 端口 %@。请检查连接后重试。", "GPUtw ポート %@ を確認できません。接続を確認して再試行してください。"],
        "Checking paired GPUtw port %@…": ["正在檢查配對的 GPUtw 連接埠 %@…", "正在检查配对的 GPUtw 端口 %@…", "GPUtw の対応ポート %@ を確認中…"],
        "Paired port %@ is also empty.": ["配對的連接埠 %@ 也沒有工作。", "配对的端口 %@ 也没有任务。", "対応ポート %@ にもジョブはありません。"],
        "Found work on paired port %@.": ["在配對的連接埠 %@ 找到工作。", "在配对的端口 %@ 找到任务。", "対応ポート %@ にジョブがあります。"],
        "GPUtw port %@ returned 404. Enable it as an HTTP port in Network Ports; private ports need one dashboard handoff from Other ports.": ["GPUtw 連接埠 %@ 回傳 404。請在 Network Ports 啟用 HTTP 連接埠；私人連接埠還需從控制台 Other ports 開啟一次。", "GPUtw 端口 %@ 返回 404。请在 Network Ports 启用 HTTP 端口；私有端口还需要从控制台 Other ports 打开一次。", "GPUtw ポート %@ が 404 を返しました。Network Ports で HTTP ポートを有効にし、非公開ポートは Other ports から一度開いてください。"],
        "GPUtw port %@ needs an owner session. Open it from the dashboard's Other ports menu.": ["GPUtw 連接埠 %@ 需要擁有者工作階段。請從控制台的 Other ports 開啟一次。", "GPUtw 端口 %@ 需要所有者会话。请从控制台的 Other ports 打开一次。", "GPUtw ポート %@ には所有者セッションが必要です。ダッシュボードの Other ports から一度開いてください。"],
        "Could not check paired GPUtw port %@. Check your connection and retry.": ["目前無法檢查配對的 GPUtw 連接埠 %@。請確認連線後重試。", "目前无法检查配对的 GPUtw 端口 %@。请检查连接后重试。", "GPUtw の対応ポート %@ を確認できません。接続を確認して再試行してください。"],
        "Open GPUtw dashboard": ["開啟 GPUtw 控制台", "打开 GPUtw 控制台", "GPUtw ダッシュボードを開く"],
        "Retry paired port check": ["重新檢查配對連接埠", "重新检查配对端口", "対応ポートを再確認"],
        "Port %@ could not be checked. Open it to sign in or review the service.": ["無法檢查連接埠 %@。請開啟該服務登入或查看狀態。", "无法检查端口 %@。请打开该服务登录或查看状态。", "ポート %@ を確認できません。開いてログインするか、状態を確認してください。"],
        "Running %@ · Waiting %@": ["執行中 %@ · 等待中 %@", "运行中 %@ · 等待中 %@", "実行中 %@・待機中 %@"],
        "Review Port %@": ["查看連接埠 %@", "查看端口 %@", "ポート %@ を確認"],
        "Open Port %@": ["開啟連接埠 %@", "打开端口 %@", "ポート %@ を開く"],
        "Recent successful jobs": ["近期成功工作", "近期成功任务", "最近成功したジョブ"],
        "History could not be read. Recent work is unknown.": ["無法讀取歷史，尚無法確認近期工作。", "无法读取历史，尚无法确认近期任务。", "履歴を読み込めないため、最近のジョブは不明です。"],
        "No successful jobs in the latest 20 history records.": ["最新 20 筆歷史中沒有成功工作。", "最新 20 条历史中没有成功任务。", "最新20件の履歴に成功したジョブはありません。"],
        "Review this ComfyUI": ["確認此 ComfyUI", "确认此 ComfyUI", "この ComfyUI を確認"],
        "Open your ComfyUI, then review its port and recent jobs before monitoring.": ["開啟 ComfyUI 後，先確認連接埠與近期工作，再開始監控。", "打开 ComfyUI 后，先检查端口与近期任务，再开始监控。", "ComfyUI を開き、ポートと最近のジョブを確認してから監視を開始してください。"],
        "ComfyUI job count": ["ComfyUI 工作數", "ComfyUI 任务数", "ComfyUI ジョブ数"],
        "Expecting a running job? Check the server port.": ["如果你正在生成，請確認伺服器連接埠。", "如果你正在生成，请检查服务器端口。", "生成中のはずなら、サーバーのポートを確認してください。"],
        "Review this connection": ["查看此連線", "查看此连接", "この接続を確認"],
        "No fresh queue response for 30 seconds. The job count is unknown.": ["已超過 30 秒未取得最新佇列，工作數目前未知。", "已超过 30 秒未取得最新队列，任务数当前未知。", "30秒以上キューが更新されていないため、ジョブ数は不明です。"],
        "Waiting for the first queue response.": ["正在等待首次佇列回應。", "正在等待首次队列响应。", "最初のキューレスポンスを待っています。"],
        "GPUtw sign-in": ["GPUtw 登入", "GPUtw 登录", "GPUtw ログイン"],
        "Sign in to GPUtw…": ["登入 GPUtw…", "登录 GPUtw…", "GPUtw にログイン…"],
        "Clear GPUtw sign-in": ["清除 GPUtw 登入", "清除 GPUtw 登录", "GPUtw ログインを消去"],
        "GPUtw sign-in cleared.": ["已清除 GPUtw 登入。", "已清除 GPUtw 登录。", "GPUtw のログインを消去しました。"],
        "For private or password-protected GPUtw ComfyUI instances.": ["適用於私人或密碼保護的 GPUtw ComfyUI 執行個體。", "适用于私有或密码保护的 GPUtw ComfyUI 实例。", "非公開またはパスワード保護された GPUtw ComfyUI に対応。"],
        "Sign in to GPUtw again, then open your ComfyUI Web UI.": ["請重新登入 GPUtw，再開啟 ComfyUI Web UI。", "请重新登录 GPUtw，再打开 ComfyUI Web UI。", "GPUtw に再ログインし、ComfyUI Web UI を開いてください。"],
        "Open a ComfyUI Web UI in this window before connecting.": ["請先在此視窗開啟 ComfyUI Web UI，再連線。", "请先在此窗口打开 ComfyUI Web UI，再连接。", "このウインドウで ComfyUI Web UI を開いてから接続してください。"],
        "Back": ["上一頁", "上一页", "戻る"],
        "GPUtw dashboard": ["GPUtw 控制台", "GPUtw 控制台", "GPUtw ダッシュボード"],
        "Checking ComfyUI…": ["正在確認 ComfyUI…", "正在检查 ComfyUI…", "ComfyUI を確認中…"],
        "Use this ComfyUI": ["使用此 ComfyUI", "使用此 ComfyUI", "この ComfyUI を使用"],
        "Sign in, open the instance's ComfyUI Web UI, then click Use this ComfyUI.": ["登入後開啟執行個體的 ComfyUI Web UI，再按「使用此 ComfyUI」。", "登录后打开实例的 ComfyUI Web UI，再点击“使用此 ComfyUI”。", "ログイン後、インスタンスの ComfyUI Web UI を開き、「この ComfyUI を使用」を押してください。"],
        "Could not open GPUtw. Check your connection and try again.": ["無法開啟 GPUtw，請確認網路連線後重試。", "无法打开 GPUtw，请检查网络连接后重试。", "GPUtw を開けません。接続を確認して再試行してください。"],
        "Observed %@ · estimate unavailable": ["已觀察 %@ · 暫無估計", "已观察 %@ · 暂无估计", "観測時間 %@・推定なし"],
        "Estimates need 3 similar successful jobs. Elapsed time starts when this app first observes the job.": ["估算需要 3 筆相似的成功工作。經過時間從 App 首次觀察到此工作起算。", "估算需要 3 条相似的成功任务。经过时间从 App 首次观察到此任务起算。", "推定には類似した成功ジョブ3件が必要です。経過時間はアプリがジョブを初めて観測した時点から計測します。"],
        "Allow notifications in macOS System Settings.": ["請在 macOS 系統設定允許通知。", "请在 macOS 系统设置允许通知。", "macOS のシステム設定で通知を許可してください。"],
        "Preview unavailable": ["無法預覽此格式", "无法预览此格式", "この形式はプレビューできません"],
        "Output": ["輸出檔案", "输出文件", "出力ファイル"],
        "Preview": ["預覽", "预览", "プレビュー"],
        "Download…": ["下載…", "下载…", "ダウンロード…"],
        "Downloaded": ["已下載", "已下载", "ダウンロード完了"],
        "Preview & download…": ["預覽與下載…", "预览与下载…", "プレビュー・ダウンロード…"],
        "Last hour": ["最近 1 小時", "最近 1 小时", "過去1時間"],
        "Last 24 hours": ["最近 24 小時", "最近 24 小时", "過去24時間"],
        "Today": ["今天", "今天", "今日"],
        "Loaded history": ["已載入的歷史", "已加载的历史", "取得済みの履歴"],
        "Job completed": ["工作已完成", "任务已完成", "ジョブが完了しました"],
        "Job failed": ["工作失敗", "任务失败", "ジョブが失敗しました"],
        "Server disconnected": ["伺服器已斷線", "服务器已断开", "サーバー接続が切れました"],
        "Queue finished": ["佇列已結束", "队列已结束", "キューの処理が終了しました"],
        "%@ completed · %@ failed": ["%@ 筆完成 · %@ 筆失敗", "%@ 条完成 · %@ 条失败", "完了%@件・失敗%@件"],
        "Estimating…": ["估算中…", "估算中…", "推定中…"],
        "Observed %@ · estimate needs 3 similar jobs": ["已觀察 %@ · 需 3 筆相似工作才能估算", "已观察 %@ · 需 3 条相似任务才能估算", "観測時間 %@・推定には類似ジョブ3件が必要です"],
        "Observed %@ · past estimated duration": ["已觀察 %@ · 已超過估計耗時", "已观察 %@ · 已超过估计耗时", "観測時間 %@・推定時間を超過しています"],
        "Observed %@ · estimated %@ remaining": ["已觀察 %@ · 預估剩餘 %@", "已观察 %@ · 预计剩余 %@", "観測時間 %@・推定残り %@"],
        "Server changed. Refresh before trying again.": ["伺服器已變更，請更新後重試。", "服务器已更改，请刷新后重试。", "サーバーが変更されました。更新して再試行してください。"],
        "Time range": ["時間範圍", "时间范围", "期間"],
        "Search history": ["搜尋歷史", "搜索历史", "履歴を検索"],
        "Newest 200 server records": ["伺服器最新 200 筆紀錄", "服务器最新 200 条记录", "サーバーの最新200件"],
        "No failures in this range": ["此範圍內沒有失敗紀錄", "此范围内没有失败记录", "この期間に失敗したジョブはありません"],
        "Interrupted": ["已中斷", "已中断", "中断"],
        "Failed": ["失敗", "失败", "失敗"],
        "No error details reported": ["未回報錯誤詳情", "未报告错误详情", "エラーの詳細は報告されていません"],
        "Failures & interruptions": ["失敗與中斷", "失败与中断", "失敗・中断"],
        "Copy absolute path": ["複製絕對路徑", "复制绝对路径", "絶対パスをコピー"],
        "Path copied": ["已複製路徑", "已复制路径", "パスをコピーしました"],
        "Set output folder…": ["設定輸出資料夾…", "设置输出文件夹…", "出力フォルダを設定…"],
        "Save folder": ["儲存資料夾", "保存文件夹", "フォルダを保存"],
        "Enter an absolute folder path.": ["請輸入資料夾的絕對路徑。", "请输入文件夹的绝对路径。", "フォルダの絶対パスを入力してください。"],
        "Enter this server's absolute output folder path. Remote paths refer to the server, not this Mac.": ["輸入此伺服器輸出資料夾的絕對路徑。遠端路徑指的是伺服器上的位置，而非這台 Mac。", "输入此服务器输出文件夹的绝对路径。远程路径指的是服务器上的位置，而非这台 Mac。", "このサーバーの出力フォルダの絶対パスを入力します。リモートパスはこのMacではなくサーバー上の場所です。"],
        "Servers": ["伺服器", "服务器", "サーバー"],
        "Remove server": ["移除伺服器", "移除服务器", "サーバーを削除"],
        "Server name": ["伺服器名稱", "服务器名称", "サーバー名"],
        "Save address": ["儲存位址", "保存地址", "アドレスを保存"],
        "Set up Claude and Codex": ["一鍵設定 Claude／Codex", "一键配置 Claude／Codex", "Claude／Codex を設定"],
        "Registers MCP and installs the shared skill for Claude Code and Codex. Replaced files are backed up; reopen agent sessions afterward.": ["註冊 MCP 並為 Claude Code 和 Codex 安裝共用 Skill。取代檔案前會先備份；完成後請重新開啟 Agent 工作階段。", "注册 MCP 并为 Claude Code 和 Codex 安装共用 Skill。替换文件前会先备份；完成后请重新打开 Agent 会话。", "MCP を登録し、Claude Code と Codex に共通スキルをインストールします。置き換えるファイルは事前にバックアップし、完了後にエージェントのセッションを開き直してください。"],
        "Configured %@. Reopen your agent chats.": ["已設定 %@。請重新開啟 Agent 對話。", "已配置 %@。请重新打开 Agent 对话。", "%@ を設定しました。チャットを開き直してください。"],
        "Installed ComfyQueueBar skill for %@.": ["已為 %@ 安裝 ComfyQueueBar Skill。", "已为 %@ 安装 ComfyQueueBar Skill。", "%@ に ComfyQueueBar スキルをインストールしました。"],
        "Copy MCP configuration": ["複製 MCP 設定", "复制 MCP 配置", "MCP 設定をコピー"],
        "Setup guide": ["設定指南", "配置指南", "設定ガイド"],
        "Node progress": ["節點進度", "节点进度", "ノード進捗"],
        "Install progress extension…": ["安裝進度擴充…", "安装进度扩展…", "進捗拡張機能をインストール…"],
        "Installs on this Mac only. For a remote ComfyUI server, install the extension on that server.": ["只會安裝到這台 Mac。本機連線遠端 ComfyUI 時，請在伺服器上安裝擴充。", "只会安装到这台 Mac。本机连接远程 ComfyUI 时，请在服务器上安装扩展。", "この Mac にのみインストールします。リモート ComfyUI の場合はサーバー側にインストールしてください。"],
        "Choose the ComfyUI folder": ["選擇 ComfyUI 資料夾", "选择 ComfyUI 文件夹", "ComfyUI フォルダを選択"],
        "Progress extension installed. Finish any active generation, then restart ComfyUI.": ["進度擴充已安裝。請等目前生成完成後重新啟動 ComfyUI。", "进度扩展已安装。请等当前生成完成后重新启动 ComfyUI。", "進捗拡張機能をインストールしました。生成完了後に ComfyUI を再起動してください。"],
        "Could not install the progress extension: %@": ["無法安裝進度擴充：%@", "无法安装进度扩展：%@", "進捗拡張機能をインストールできませんでした：%@"],
        "The progress extension already exists at %@. Remove or back it up before installing again.": ["進度擴充已存在於 %@。請先移除或備份，再重新安裝。", "进度扩展已存在于 %@。请先移除或备份，再重新安装。", "進捗拡張機能は %@ に既にあります。再インストールする前に削除するかバックアップしてください。"],
        "Shares queue IDs, output references, and errors with local agents. Desktop push requires host support.": ["與本機 Agent 分享佇列 ID、輸出參照和錯誤。桌面推送需要 Agent 支援。", "与本机 Agent 分享队列 ID、输出引用和错误。桌面推送需要 Agent 支持。", "キュー ID、出力参照、エラーをローカルエージェントと共有します。デスクトップ通知にはホストの対応が必要です。"],
        "AI agent integration": ["AI Agent 整合", "AI Agent 集成", "AI エージェント連携"],
        "Let agents delegate monitoring to this app using the local MCP bridge.": ["透過本機 MCP 橋接，讓 Agent 將監控交給此 App。", "通过本机 MCP 桥接，让 Agent 将监控交给此 App。", "ローカル MCP ブリッジで監視をこのアプリに委任できます。"],
        "Completion notifications": ["完成通知", "完成通知", "完了通知"],
        "Off": ["關閉", "关闭", "オフ"],
        "Every job": ["每個工作", "每个任务", "ジョブごと"],
        "Whole batch": ["整批結束", "整批结束", "バッチ終了時"],
        "Notify failures and disconnections": ["通知失敗與斷線", "通知失败与断线", "失敗・切断を通知"],

        "Recently completed": ["最近完成", "最近完成", "最近完了したジョブ"],
        "Last 24 hours · up to 20 jobs": ["最近 24 小時 · 最多 20 筆", "最近 24 小时 · 最多 20 条", "過去24時間・最大20件"],
        "No recently completed jobs": ["最近沒有完成的工作", "最近没有完成的任务", "最近完了したジョブはありません"],
        "History unavailable. Showing the last successful refresh.": ["無法讀取歷史紀錄，目前顯示上次成功更新的資料。", "无法读取历史记录，当前显示上次成功刷新的数据。", "履歴を読み込めません。最後に取得した内容を表示しています。"],
        "No output files reported": ["未回報輸出檔案", "未报告输出文件", "出力ファイルの報告はありません"],
        "Completion time unavailable": ["未提供完成時間（近期歷史）", "未提供完成时间（近期历史）", "完了時刻不明（直近の履歴）"],
        "Settings": ["設定", "设置", "設定"],
        "Automatically update the app": ["自動更新 App", "自动更新 App", "アプリを自動更新"],
        "Check for updates…": ["檢查更新…", "检查更新…", "アップデートを確認…"],
        "ComfyUI Queue": ["ComfyUI 佇列", "ComfyUI 队列", "ComfyUI キュー"],
        "Connected": ["已連線", "已连接", "接続済み"],
        "Disconnected": ["未連線", "未连接", "未接続"],
        "Refresh now": ["立即更新", "立即刷新", "今すぐ更新"],
        "Wake Mac": ["喚醒 Mac", "唤醒 Mac", "Macを起こす"],
        "MAC address": ["MAC 位址", "MAC 地址", "MACアドレス"],
        "Broadcast IPv4 address": ["廣播 IPv4 位址", "广播 IPv4 地址", "ブロードキャストIPv4アドレス"],
        "UDP port": ["UDP 連接埠", "UDP 端口", "UDPポート"],
        "Automatically wake when offline": ["離線時自動喚醒", "离线时自动唤醒", "オフライン時に自動で起こす"],
        "Save wake settings": ["儲存喚醒設定", "保存唤醒设置", "起動設定を保存"],
        "Wake now": ["立即喚醒", "立即唤醒", "今すぐ起こす"],
        "Wake settings saved": ["喚醒設定已儲存", "唤醒设置已保存", "起動設定を保存しました"],
        "Wake packet sent. Waiting for ComfyUI to reconnect.": ["已傳送喚醒封包，等待 ComfyUI 重新連線。", "已发送唤醒数据包，等待 ComfyUI 重新连接。", "起動パケットを送信しました。ComfyUIの再接続を待っています。"],
        "Enter a valid MAC address (AA:BB:CC:DD:EE:FF).": ["請輸入有效的 MAC 位址（AA:BB:CC:DD:EE:FF）。", "请输入有效的 MAC 地址（AA:BB:CC:DD:EE:FF）。", "有効なMACアドレスを入力してください（AA:BB:CC:DD:EE:FF）。"],
        "Enter a valid IPv4 destination and UDP port.": ["請輸入有效的 IPv4 目的位址與 UDP 連接埠。", "请输入有效的 IPv4 目标地址与 UDP 端口。", "有効なIPv4宛先とUDPポートを入力してください。"],
        "Checks the selected server only. Retries every 2 minutes. Enable Wake for network access on the target Mac; the network must allow wake packets.": ["僅檢查目前選取的伺服器，每 2 分鐘重試。目標 Mac 須啟用「喚醒以供網路存取」，網路須允許喚醒封包。", "仅检查当前选中的服务器，每 2 分钟重试。目标 Mac 须启用“唤醒以供网络访问”，网络须允许唤醒数据包。", "選択中のサーバーのみ確認し、2分ごとに再試行します。対象Macで「ネットワークアクセスによるスリープ解除」を有効にし、ネットワークで起動パケットを許可してください。"],
        "Address saved": ["位址已儲存", "地址已保存", "アドレスを保存しました"],
        "Saved addresses": ["已儲存的位址", "已保存的地址", "保存済みアドレス"],
        "ComfyUI address": ["ComfyUI 位址", "ComfyUI 地址", "ComfyUI アドレス"],
        "Connect": ["連線", "连接", "接続"],
        "Running": ["執行中", "运行中", "実行中"],
        "Waiting": ["等待中", "等待中", "待機中"],
        "Total": ["總計", "总计", "合計"],
        "Waiting queue": ["等待佇列", "等待队列", "待機キュー"],
        "No jobs are running": ["目前沒有執行中的工作", "当前没有运行中的任务", "実行中のジョブはありません"],
        "No waiting jobs": ["沒有等待中的工作", "没有等待中的任务", "待機中のジョブはありません"],
        "Confirm action": ["確認操作", "确认操作", "操作の確認"],
        "Prioritize and resubmit": ["優先執行並重新提交", "优先执行并重新提交", "優先して再送信"],
        "Stop running job": ["停止執行中的工作", "停止运行中的任务", "実行中のジョブを停止"],
        "Cancel": ["取消", "取消", "キャンセル"],
        "Moving job to the front…": ["正在移至佇列前端…", "正在移至队列前端…", "キューの先頭に移動中…"],
        "Stopping job…": ["正在停止工作…", "正在停止任务…", "ジョブを停止中…"],
        "Unable to read the queue": ["無法讀取佇列", "无法读取队列", "キューを読み込めません"],
        "Check that ComfyUI is running and the address is correct.": ["請確認 ComfyUI 已啟動且位址正確。", "请确认 ComfyUI 已启动且地址正确。", "ComfyUI が起動していることとアドレスを確認してください。"],
        "Refreshes every 4 seconds": ["每 4 秒更新", "每 4 秒刷新", "4 秒ごとに更新"],
        "Edit": ["編輯", "编辑", "編集"],
        "Cut": ["剪下", "剪切", "カット"],
        "Copy": ["複製", "复制", "コピー"],
        "Paste": ["貼上", "粘贴", "ペースト"],
        "Select All": ["全選", "全选", "すべてを選択"],
        "Quit": ["結束", "退出", "終了"],
        "Prioritize this job?": ["要優先執行這個工作嗎？", "要优先执行此任务吗？", "このジョブを優先しますか？"],
        "Stop this job?": ["要停止這個工作嗎？", "要停止此任务吗？", "このジョブを停止しますか？"],
        "Working": ["處理中", "处理中", "処理中"],
        "Prioritize": ["優先執行", "优先执行", "優先実行"],
        "Stopping": ["停止中", "停止中", "停止中"],
        "Stop": ["停止", "停止", "停止"],
        "Run next after the current job": ["目前工作結束後優先執行", "当前任务结束后优先执行", "現在のジョブの次に実行"],
        "Stop this job while keeping waiting jobs": ["停止此工作並保留等待工作", "停止此任务并保留等待任务", "待機ジョブを保持してこのジョブを停止"],
        "Node is processing": ["節點處理中", "节点处理中", "ノードを処理中"],
        "Fetching node progress…": ["正在取得節點進度…", "正在获取节点进度…", "ノードの進捗を取得中…"],
        "No progress reported for this node yet": ["此節點尚未回報進度", "此节点尚未报告进度", "このノードの進捗はまだ報告されていません"],
        "Install the progress extension and restart ComfyUI": ["請安裝進度擴充並重啟 ComfyUI", "请安装进度扩展并重启 ComfyUI", "進捗拡張機能をインストールして ComfyUI を再起動してください"],
        "Unable to read live progress": ["無法讀取即時進度", "无法读取实时进度", "現在の進捗を読み込めません"],
        "ComfyUI workflow": ["ComfyUI 工作流程", "ComfyUI 工作流", "ComfyUI ワークフロー"],
        "Waiting for node progress": ["等待節點進度", "等待节点进度", "ノードの進捗を待機中"],
        "Enter a valid http:// or https:// address.": ["請輸入有效的 http:// 或 https:// 位址。", "请输入有效的 http:// 或 https:// 地址。", "有効な http:// または https:// アドレスを入力してください。"],
        "ComfyUI returned an unrecognized queue response.": ["ComfyUI 回傳了無法辨識的佇列回應。", "ComfyUI 返回了无法识别的队列响应。", "ComfyUI から認識できないキューレスポンスが返されました。"],
        "This job is no longer waiting. Refresh and try again.": ["此工作已不在等待佇列，請更新後重試。", "此任务已不在等待队列，请刷新后重试。", "このジョブは待機中ではありません。更新して再試行してください。"],
        "The original job started. Prioritization was canceled; the running job will continue.": ["原工作已開始，已取消優先操作；執行中的工作將繼續。", "原任务已开始，已取消优先操作；运行中的任务将继续。", "元のジョブが開始されました。優先操作を取り消しました。実行中のジョブは継続します。"],
        "This job is no longer running. No stop request was sent.": ["此工作已不在執行中，未送出停止請求。", "此任务已不在运行中，未发送停止请求。", "このジョブは実行中ではありません。停止要求は送信していません。"],
        "ComfyUI did not remove the original job. Checking resubmission cleanup.": ["ComfyUI 未移除原工作，正在檢查重新提交項目的清理狀態。", "ComfyUI 未移除原任务，正在检查重新提交项的清理状态。", "ComfyUI が元のジョブを削除していません。再送信項目の削除を確認しています。"],
        "The job has stopped. The next waiting job can now run.": ["工作已停止，下一個等待工作可以開始執行。", "任务已停止，下一个等待任务可以开始运行。", "ジョブが停止しました。次の待機ジョブを実行できます。"],
        "Stop requested. ComfyUI has not yet reported that the job ended.": ["已請求停止，ComfyUI 尚未回報工作已結束。", "已请求停止，ComfyUI 尚未报告任务已结束。", "停止を要求しました。ComfyUI はまだジョブの終了を報告していません。"],
        "The original job started. The resubmitted entry was removed; the running job was not interrupted.": ["原工作已開始，重新提交的項目已移除；執行中的工作未被中斷。", "原任务已开始，重新提交的项已移除；运行中的任务未被中断。", "元のジョブが開始されました。再送信した項目を削除しました。実行中のジョブは中断していません。"],
        "Prioritization failed. The resubmitted entry was removed; the original job remains queued.": ["優先操作失敗，重新提交的項目已移除，原工作仍在佇列中。", "优先操作失败，重新提交的项已移除，原任务仍在队列中。", "優先操作に失敗しました。再送信した項目を削除しました。元のジョブはキューに残っています。"],
        "The original job left the waiting queue. The resubmitted entry was removed.": ["原工作已離開等待佇列，重新提交的項目已移除。", "原任务已离开等待队列，重新提交的项已移除。", "元のジョブは待機キューから離れました。再送信した項目を削除しました。"],
        "Updated %@": ["更新於 %@", "更新于 %@", "更新 %@"],
        "ComfyUI queue: %@ jobs": ["ComfyUI 佇列：%@ 個工作", "ComfyUI 队列：%@ 个任务", "ComfyUI キュー：%@ 件"],
        "%@ nodes": ["%@ 個節點", "%@ 个节点", "%@ ノード"],
        "Node %@": ["節點 %@", "节点 %@", "ノード %@"],
        "ComfyUI returned HTTP %@.": ["ComfyUI 回傳 HTTP %@。", "ComfyUI 返回 HTTP %@。", "ComfyUI から HTTP %@ が返されました。"],
        "Moved to the front of the waiting queue. New job ID: %@": ["已移至等待佇列前端。新工作 ID：%@", "已移至等待队列前端。新任务 ID：%@", "待機キューの先頭に移動しました。新しいジョブ ID：%@"],
        "Could not confirm the result. Refresh and check original ID %@ and new ID %@.": ["無法確認結果。請更新並檢查原 ID %@ 與新 ID %@。", "无法确认结果。请刷新并检查原 ID %@ 与新 ID %@。", "結果を確認できません。更新して元の ID %@ と新しい ID %@ を確認してください。"],
        "Could not confirm duplicate cleanup. Refresh now and check original ID %@ and new ID %@.": ["無法確認重複項目已清理。請更新並檢查原 ID %@ 與新 ID %@。", "无法确认重复项已清理。请刷新并检查原 ID %@ 与新 ID %@。", "重複項目の削除を確認できません。更新して元の ID %@ と新しい ID %@ を確認してください。"],
        "Could not confirm prioritization or cleanup. Refresh now and check original ID %@ and new ID %@.": ["無法確認優先操作或清理結果。請更新並檢查原 ID %@ 與新 ID %@。", "无法确认优先操作或清理结果。请刷新并检查原 ID %@ 与新 ID %@。", "優先操作または削除の結果を確認できません。更新して元の ID %@ と新しい ID %@ を確認してください。"],
        "The original job status is unknown, but the resubmitted job started. Refresh and check IDs %@ and %@.": ["原工作狀態未知，但重新提交的工作已開始。請更新並檢查 ID %@ 與 %@。", "原任务状态未知，但重新提交的任务已开始。请刷新并检查 ID %@ 与 %@。", "元のジョブの状態は不明ですが、再送信したジョブが開始されました。更新して ID %@ と %@ を確認してください。"],
        "The original job left the waiting queue. Refresh to check the result.": ["原工作已離開等待佇列，請更新以確認結果。", "原任务已离开等待队列，请刷新以确认结果。", "元のジョブは待機キューから離れました。更新して結果を確認してください。"],
        "Move \"%@\" to the front of the waiting queue. The running job continues. This resubmits the job and changes its prompt ID.": ["將「%@」移至等待佇列前端。執行中的工作會繼續。此操作會重新提交工作並變更 prompt ID。", "将“%@”移至等待队列前端。运行中的任务会继续。此操作会重新提交任务并更改 prompt ID。", "「%@」を待機キューの先頭に移します。実行中のジョブは継続します。ジョブが再送信され、prompt ID が変わります。"],
        "Stop generation for \"%@\". Waiting jobs remain queued and the next job can run.": ["停止「%@」的生成。等待工作會保留在佇列中，下一個工作可以開始執行。", "停止“%@”的生成。等待任务会保留在队列中，下一个任务可以开始运行。", "「%@」の生成を停止します。待機ジョブはキューに残り、次のジョブを実行できます。"],
    ]
}

enum PairedQueueStatus: Equatable {
    case checking
    case empty
    case work(running: Int, waiting: Int, title: String?)
    case issue(PairedPortIssue)
}

@MainActor
final class QueueViewModel: ObservableObject {
    static let connectionRetryInterval: TimeInterval = 4

    @Published var endpoint: String
    @Published private(set) var running: [QueueJob] = []
    @Published private(set) var pending: [QueueJob] = []
    @Published private(set) var pairedPortEndpoint: String?
    @Published private(set) var pairedQueueStatus: PairedQueueStatus?
    @Published private(set) var isConnected = false
    @Published private(set) var isLoading = false
    @Published private(set) var monitoringState: MonitoringState = .checking
    private var needsSignIn = false
    @Published private(set) var movingJobID: String?
    @Published private(set) var stoppingJobID: String?
    @Published private(set) var queueProgress: QueueProgress?
    @Published private(set) var progressBridgeStatus: ProgressBridgeStatus = .checking
    @Published private(set) var errorMessage: String?
    @Published private(set) var connectionMessage: String?
    @Published private(set) var connectionMessageIsError = false
    @Published private(set) var actionMessage: String?
    @Published private(set) var actionIsError = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var completed: [CompletedJob] = []
    @Published private(set) var historyUnavailable = false
    @Published private(set) var failures: [FailedJob] = []
    @Published private(set) var wakeMessages: [UUID: String] = [:]
    private var lastWakeAttempts: [UUID: Date] = [:]
    @Published private(set) var profiles: [ServerProfile] = []
    @Published private(set) var isClearingGPUTW = false
    @Published private(set) var observedStarts: [String: Date] = [:]
    @Published private(set) var permissionMessage: String?
    @Published private(set) var progressExtensionMessage: String?
    @Published private(set) var progressExtensionError: String?
    @Published var notificationMode = "off" {
        didSet { UserDefaults.standard.set(notificationMode, forKey: "notificationMode") }
    }
    @Published var notifyProblems = false {
        didSet { UserDefaults.standard.set(notifyProblems, forKey: "notifyProblems") }
    }
    @Published var agentIntegrationEnabled = false {
        didSet {
            UserDefaults.standard.set(agentIntegrationEnabled, forKey: "agentIntegrationEnabled")
            configureAgentBridge()
        }
    }
    @Published private(set) var agentBridgeError: String?
    @Published private(set) var agentSetupMessage: String?
    @Published private(set) var isSettingUpAgents = false
    private var agentBridge: AgentBridge?
    private var agentTimer: Timer?
    private var notificationTracker = NotificationTracker()
    private var connectionGeneration = UUID()
    private var lastHistoryPoll: Date?
    private var lastPairedPortCheck: Date?
    private var pairedPortCheckTask: Task<Void, Never>?
    private var pairedPortCheckToken = UUID()

    private var refreshTimer: Timer?
    private var progressTimer: Timer?
    private var isProgressLoading = false
    private var secondaryRefreshTask: Task<Void, Never>?
    private var secondaryRefreshForceHistory = false
    private var secondaryRefreshToken = UUID()

    var totalJobs: Int { running.count + pending.count }
    var hasFreshQueue: Bool { monitoringState == .connected }
    var queueBadge: String { monitoringState.badge(count: totalJobs) }

    private func updateMonitoringState() {
        let state = MonitoringState.resolve(connected: isConnected, loading: isLoading, needsSignIn: needsSignIn,
            lastUpdated: lastUpdated, hasError: errorMessage != nil, now: Date())
        if monitoringState != state { monitoringState = state }
    }

    init() {
        #if DOCUMENTATION_SCREENSHOT
        endpoint = "http://127.0.0.1:8188"
        let graph: [String: Any] = ["12": ["_meta": ["title": "KSampler"], "class_type": "KSampler"]]
        running = [QueueJob(id: "8f21a7c4-demo-running", title: "Ceramic lamp · turntable", nodeCount: 24, queueNumber: 1, position: 1, prompt: graph, extraData: [:])]
        pending = [QueueJob(id: "b390e612-demo-waiting", title: "Ceramic lamp · warm lighting", nodeCount: 18, queueNumber: 2, position: 1, prompt: [:], extraData: [:])]
        isConnected = true
        monitoringState = .connected
        progressBridgeStatus = .available
        queueProgress = QueueProgress(promptID: running[0].id, nodeID: "12", value: 21, maxValue: 30, percent: 70, state: "running")
        let demoNow = Calendar(identifier: .gregorian).startOfDay(for: Date()).addingTimeInterval(14 * 3600 + 32 * 60)
        lastUpdated = demoNow
        let fingerprint = HistoryDetails.fingerprint(graph)
        completed = (0..<3).map { index in
            let end = demoNow.addingTimeInterval(-Double(180 + index * 360))
            let output = MediaOutput(filename: "ceramic_lamp_studio_000\(42 - index).png", subfolder: "product", type: "output")
            return CompletedJob(id: "demo-completed-\(index)", title: index == 0 ? "Ceramic lamp · studio still" : "Ceramic lamp · lighting test \(3 - index)", finishedAt: end, filenames: [output.displayPath], queueNumber: Double(index), outputs: [output], startedAt: end.addingTimeInterval(-240), fingerprint: fingerprint)
        }
        profiles = [ServerProfile(name: "Studio Mac", endpoint: endpoint), ServerProfile(name: "Render PC", endpoint: "http://192.0.2.10:8188")]
        observedStarts[running[0].id] = Date().addingTimeInterval(-124)
        #else
        endpoint = UserDefaults.standard.string(forKey: "comfyEndpoint") ?? "http://127.0.0.1:8188"
        if let data = UserDefaults.standard.data(forKey: "serverProfiles"), let saved = try? JSONDecoder().decode([ServerProfile].self, from: data) { profiles = saved }
        notificationMode = UserDefaults.standard.string(forKey: "notificationMode") ?? "off"
        notifyProblems = UserDefaults.standard.bool(forKey: "notifyProblems")
        let refreshTimer = Timer(timeInterval: Self.connectionRetryInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        RunLoop.main.add(refreshTimer, forMode: .common)
        self.refreshTimer = refreshTimer
        let progressTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshProgress() }
        }
        RunLoop.main.add(progressTimer, forMode: .common)
        self.progressTimer = progressTimer
        agentIntegrationEnabled = UserDefaults.standard.bool(forKey: "agentIntegrationEnabled")
        configureAgentBridge()
        let agentTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateMonitoringState(); self?.tickAgentBridge() }
        }
        RunLoop.main.add(agentTimer, forMode: .common)
        self.agentTimer = agentTimer
        Task { await refresh() }
        #endif
    }

    func setupAgents() async {
        guard !isSettingUpAgents, let script = Bundle.main.url(forResource: "server", withExtension: "py", subdirectory: "AgentBridge") else { return }
        let skill = Bundle.main.url(forResource: "SKILL", withExtension: "md", subdirectory: "AgentBridge/skills/comfyqueuebar")
        isSettingUpAgents = true
        defer { isSettingUpAgents = false }
        agentSetupMessage = nil
        let outcome = await Task.detached { () -> Result<AgentSetup.Report, Error> in
            do {
                let python = AgentSetup.python()
                let customHome = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
                return .success(try AgentSetup.configure(script: script, python: python, codex: AgentSetup.codex(), codexHome: customHome, skill: skill))
            } catch { return .failure(error) }
        }.value
        switch outcome {
        case .success(let report):
            if !report.configured.isEmpty { agentIntegrationEnabled = true }
            var messages: [String] = []
            if !report.configured.isEmpty { messages.append(L10n.text("Configured %@. Reopen your agent chats.", report.configured.joined(separator: ", "))) }
            if !report.skillsInstalled.isEmpty { messages.append(L10n.text("Installed ComfyQueueBar skill for %@.", report.skillsInstalled.joined(separator: ", "))) }
            messages.append(contentsOf: report.failed)
            agentSetupMessage = messages.joined(separator: "\n")
        case .failure(let error): agentSetupMessage = error.localizedDescription
        }
    }

    private func configureAgentBridge() {
        #if !DOCUMENTATION_SCREENSHOT
        if agentIntegrationEnabled {
            do { agentBridge = try AgentBridge(); agentBridgeError = nil; tickAgentBridge() }
            catch { agentBridgeError = error.localizedDescription }
        } else { agentBridge?.stop(); agentBridge = nil; agentBridgeError = nil }
        #endif
    }

    private func tickAgentBridge() {
        guard let bridge = agentBridge else { return }
        do {
            try bridge.tick(endpoint: endpoint, connected: isConnected, historyAvailable: !historyUnavailable,
                lastUpdated: lastUpdated, running: running.map(\.id), pending: pending.map(\.id))
            agentBridgeError = nil
        } catch { agentBridgeError = error.localizedDescription }
    }

    private func ingestAgentHistory(_ history: [String: Any], endpoint source: String) {
        guard let bridge = agentBridge else { return }
        var results: [String: AgentJobResult] = [:]
        for job in CompletionHistory.parse(history, now: Date(), maxAge: nil, limit: history.count, title: Self.jobTitle) {
            results[job.id] = AgentJobResult(status: "completed", outputs: job.outputs.map {
                ["filename": $0.filename, "subfolder": $0.subfolder, "type": $0.type,
                 "url": $0.url(endpoint: source)?.absoluteString ?? ""]
            })
        }
        for job in HistoryDetails.failures(history, title: Self.jobTitle) {
            results[job.id] = AgentJobResult(status: job.interrupted ? "interrupted" : "failed", error: job.reason)
        }
        do { try bridge.ingest(endpoint: source, results: results) }
        catch { agentBridgeError = error.localizedDescription }
    }

    var serverName: String { profiles.first { $0.endpoint == endpoint }?.name ?? (URLComponents(string: endpoint)?.host ?? endpoint) }
    var canChangeServer: Bool { movingJobID == nil && stoppingJobID == nil }

    func signInToGPUTW(address: String) {
        guard canChangeServer, !isClearingGPUTW else { return }
        GPUTWLoginWindow.shared.open(address: address) { [weak self] address in
            guard let self, self.canChangeServer else { return }
            let port = URL(string: address)?.host?.split(separator: "-").first.map(String.init) ?? ""
            let name = self.profiles.first(where: { $0.endpoint == address })?.name ?? "GPUtw · " + port
            self.reviewConnection(to: address, profileName: name, fromGPUTW: true)
        }
    }

    func reviewConnection(to address: String, profileName: String? = nil, fromGPUTW: Bool = false) {
        guard canChangeServer, !isClearingGPUTW else { return }
        clearConnectionFeedback()
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: value), GPUTWAddress.isDashboard(url) { signInToGPUTW(address: value); return }
        do {
            let address = try ConnectionAddress.normalize(value)
            ConnectionReviewWindow.shared.open(address: address) { [weak self] selected in
                guard let self, self.canChangeServer, !self.isClearingGPUTW else { return }
                if fromGPUTW {
                    let name = self.profiles.first(where: { $0.endpoint == selected })?.name
                        ?? "GPUtw · " + ConnectionAddress.port(selected)
                    self.saveProfile(name: name, address: selected)
                } else if let profileName {
                    self.saveProfile(name: profileName, address: selected)
                }
                if fromGPUTW { GPUTWLoginWindow.shared.close() }
                Task { await self.connect(to: selected) }
            } onOpenAlternative: { [weak self] alternative in
                guard let self, self.canChangeServer, !self.isClearingGPUTW else { return }
                GPUTWLoginWindow.shared.open(address: alternative) { [weak self] service in
                    guard let self, self.canChangeServer, !self.isClearingGPUTW else { return }
                    self.reviewConnection(to: service, fromGPUTW: true)
                }
            }
        } catch {
            connectionMessage = error.localizedDescription
            connectionMessageIsError = true
        }
    }

    func clearGPUTWLogin() async {
        guard canChangeServer, !isClearingGPUTW else { return }
        isClearingGPUTW = true
        defer { isClearingGPUTW = false }
        GPUTWLoginWindow.shared.close()
        ConnectionReviewWindow.shared.close()
        ComfyHTTPClient.shared.beginClearingAuthentication()
        defer { ComfyHTTPClient.shared.finishClearingAuthentication() }
        let isGPUTW = URL(string: endpoint).flatMap { GPUTWAddress.serviceOrigin($0) } != nil
        if isGPUTW {
            connectionGeneration = UUID()
            setDisconnected(L10n.text("GPUtw sign-in cleared."), requiresSignIn: true)
        }
        // This is this app's WebKit store, never Safari/Chrome's browsing data.
        await WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        connectionMessage = L10n.text("GPUtw sign-in cleared.")
        connectionMessageIsError = false
    }

    @discardableResult
    func saveProfile(name: String, address: String) -> Bool {
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: value), GPUTWAddress.isDashboard(url) {
            signInToGPUTW(address: value)
            return false
        }
        let address: String
        do { address = try ConnectionAddress.normalize(value) }
        catch {
            connectionMessage = L10n.text("Enter a valid http:// or https:// address.")
            connectionMessageIsError = true
            return false
        }
        guard let url = URLComponents(string: address) else { return false }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = name.isEmpty ? (url.host ?? address) : name
        if let index = profiles.firstIndex(where: { $0.endpoint == address }) {
            if !name.isEmpty { profiles[index].name = label }
        }
        else { profiles.append(ServerProfile(name: label, endpoint: address)) }
        persistProfiles()
        connectionMessage = L10n.text("Address saved")
        connectionMessageIsError = false
        return true
    }
    func deleteProfile(_ id: UUID) { profiles.removeAll { $0.id == id }; persistProfiles() }

    func saveWakeSettings(_ settings: WakeSettings, for id: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        do {
            try WakeOnLAN.validate(settings)
            profiles[index].wake = settings
            persistProfiles()
            wakeMessages[id] = L10n.text("Wake settings saved")
        } catch { wakeMessages[id] = L10n.text(error.localizedDescription) }
    }

    func wakeServer(_ id: UUID, automatically: Bool = false) {
        guard let profile = profiles.first(where: { $0.id == id }), let settings = profile.wake else { return }
        let now = Date()
        if automatically {
            guard settings.automaticallyWake,
                  WakeOnLAN.canRetry(lastAttempt: lastWakeAttempts[id], now: now) else { return }
        }
        lastWakeAttempts[id] = now
        do {
            try WakeOnLAN.send(settings)
            wakeMessages[id] = L10n.text("Wake packet sent. Waiting for ComfyUI to reconnect.")
        } catch { wakeMessages[id] = L10n.text(error.localizedDescription) }
    }

    func installProgressExtension(in comfyRoot: URL) {
        progressExtensionMessage = nil
        progressExtensionError = nil
        let manager = FileManager.default
        let customNodes = comfyRoot.appendingPathComponent("custom_nodes", isDirectory: true)
        let destination = customNodes.appendingPathComponent("ComfyQueueBarProgress", isDirectory: true)
        guard manager.fileExists(atPath: customNodes.path) else {
            progressExtensionError = L10n.text("Could not install the progress extension: %@", "custom_nodes folder not found")
            return
        }
        guard !manager.fileExists(atPath: destination.path) else {
            progressExtensionError = L10n.text("The progress extension already exists at %@. Remove or back it up before installing again.", destination.path)
            return
        }
        guard let source = Bundle.main.resourceURL?.appendingPathComponent("ComfyQueueBarProgress", isDirectory: true),
              manager.fileExists(atPath: source.appendingPathComponent("__init__.py").path) else {
            progressExtensionError = L10n.text("Could not install the progress extension: %@", "extension files are missing from the app")
            return
        }
        do {
            try ProgressExtensionInstaller.install(from: source, to: destination)
            progressExtensionMessage = L10n.text("Progress extension installed. Finish any active generation, then restart ComfyUI.")
        } catch {
            progressExtensionError = L10n.text("Could not install the progress extension: %@", error.localizedDescription)
        }
    }
    private func persistProfiles() {
        if let data = try? JSONEncoder().encode(profiles) { UserDefaults.standard.set(data, forKey: "serverProfiles") }
    }
    func authorizeNotifications() async {
        await NotificationService.shared.authorize()
        permissionMessage = NotificationService.shared.permissionMessage
    }
    private func processHistoryNotifications(ids: Set<String>) {
        let delta = notificationTracker.ingest(ids: ids, successes: Set(completed.map(\.id)), failures: Set(failures.filter { !$0.interrupted }.map(\.id)), queueCount: totalJobs)
        if notificationMode == "each" {
            for job in completed where delta.successes.contains(job.id) {
                NotificationService.shared.send(id: endpoint + job.id, title: L10n.text("Job completed"), body: serverName + " · " + job.title)
            }
        }
        if notifyProblems {
            for job in failures where delta.failures.contains(job.id) {
                NotificationService.shared.send(id: endpoint + job.id, title: L10n.text("Job failed"), body: serverName + " · " + job.title + "\n" + job.reason)
            }
        }
        if let batch = delta.batch, notificationMode == "batch" {
            NotificationService.shared.send(id: UUID().uuidString, title: L10n.text("Queue finished"), body: serverName + " · " + L10n.text("%@ completed · %@ failed", String(batch.completed), String(batch.failed)))
        }
    }
    func timingText(for job: QueueJob, now: Date) -> String {
        guard let observed = observedStarts[job.id] else { return L10n.text("Estimating…") }
        let elapsed = max(0, now.timeIntervalSince(observed))
        let elapsedText = Self.durationText(elapsed)
        guard let duration = HistoryDetails.estimatedDuration(fingerprint: HistoryDetails.fingerprint(job.prompt), completed: completed) else {
            return L10n.text("Observed %@ · estimate unavailable", elapsedText)
        }
        let remaining = duration - elapsed
        if remaining <= 0 { return L10n.text("Observed %@ · past estimated duration", elapsedText) }
        return L10n.text("Observed %@ · estimated %@ remaining", elapsedText, Self.durationText(remaining))
    }
    static func durationText(_ seconds: Double) -> String {
        let value = Int(seconds)
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) : String(format: "%d:%02d", value / 60, value % 60)
    }

    func connect(to value: String) async {
        guard canChangeServer else { return }
        clearConnectionFeedback()
        actionMessage = nil
        actionIsError = false
        var cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let url = URL(string: cleaned) {
            if GPUTWAddress.isDashboard(url) { signInToGPUTW(address: cleaned); return }
            if let origin = GPUTWAddress.serviceOrigin(url) { cleaned = origin.absoluteString }
        }
        if endpoint != cleaned {
            connectionGeneration = UUID()
            secondaryRefreshTask?.cancel()
            secondaryRefreshTask = nil
            secondaryRefreshForceHistory = false
            secondaryRefreshToken = UUID()
            clearPairedPortCheck(resetThrottle: true)
            completed = []; failures = []; running = []; pending = []; observedStarts = [:]
            notificationTracker = NotificationTracker()
            isConnected = false
            needsSignIn = false
            lastUpdated = nil
            errorMessage = nil
            monitoringState = .checking
            lastHistoryPoll = nil
            historyUnavailable = false
        }
        endpoint = cleaned
        UserDefaults.standard.set(cleaned, forKey: "comfyEndpoint")
        await refresh(forceHistory: true)
    }

    private func clearConnectionFeedback() {
        connectionMessage = nil
        connectionMessageIsError = false
    }

    func refresh(forceHistory: Bool = false) async {
        guard !isLoading, !isClearingGPUTW, movingJobID == nil, stoppingJobID == nil else { return }
        isLoading = true
        updateMonitoringState()
        let generation = connectionGeneration
        defer {
            isLoading = false
            updateMonitoringState()
            if generation != connectionGeneration { Task { await refresh(forceHistory: true) } }
        }

        do {
            let snapshot = try await fetchQueue()
            guard generation == connectionGeneration else { return }
            apply(snapshot)
            isConnected = true
            needsSignIn = false
            errorMessage = nil
            lastUpdated = Date()
            updateMonitoringState()
            schedulePairedPortCheck(generation: generation)
            // Queue state is the primary monitor. Progress and history are
            // enrichment and must not hold isLoading across their network
            // requests; otherwise a slow history endpoint blocks the next
            // four-second queue retry.
            scheduleSecondaryRefresh(generation: generation, forceHistory: forceHistory)
        } catch {
            guard generation == connectionGeneration else { return }
            clearPairedPortCheck(resetThrottle: true)
            setDisconnected(error.localizedDescription, requiresSignIn: MonitoringState.requiresSignIn(error))
            if WakeOnLAN.isOfflineError(error),
               let profile = profiles.first(where: { $0.endpoint == endpoint }) {
                wakeServer(profile.id, automatically: true)
            }
        }
    }

    private func scheduleSecondaryRefresh(generation: UUID, forceHistory: Bool) {
        guard generation == connectionGeneration else { return }
        secondaryRefreshForceHistory = secondaryRefreshForceHistory || forceHistory
        guard secondaryRefreshTask == nil else { return }

        let token = UUID()
        secondaryRefreshToken = token
        let requestedForceHistory = secondaryRefreshForceHistory
        secondaryRefreshForceHistory = false
        secondaryRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.secondaryRefreshToken == token {
                    self.secondaryRefreshTask = nil
                    if self.secondaryRefreshForceHistory {
                        self.scheduleSecondaryRefresh(generation: self.connectionGeneration, forceHistory: true)
                    }
                }
            }
            await self.refreshProgress(forceBridgeCheck: true)
            guard !Task.isCancelled, self.connectionGeneration == generation else { return }
            await self.refreshHistory(force: requestedForceHistory)
        }
    }

    private func schedulePairedPortCheck(generation: UUID) {
        guard isConnected, let url = URL(string: endpoint),
              let paired = GPUTWAddress.pairedServiceOrigin(url) else {
            clearPairedPortCheck(resetThrottle: true)
            return
        }
        guard running.isEmpty, pending.isEmpty else {
            clearPairedPortCheck(resetThrottle: true)
            return
        }
        let source = endpoint
        let pairedAddress = paired.absoluteString
        if pairedPortEndpoint != pairedAddress {
            clearPairedPortCheck(resetThrottle: true)
            pairedPortEndpoint = pairedAddress
        }
        guard pairedPortCheckTask == nil else { return }
        if let lastPairedPortCheck, Date().timeIntervalSince(lastPairedPortCheck) < 30 { return }

        lastPairedPortCheck = Date()
        pairedQueueStatus = .checking
        let token = UUID()
        pairedPortCheckToken = token
        pairedPortCheckTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.pairedPortCheckToken == token { self.pairedPortCheckTask = nil }
            }
            do {
                let inspection = try await ConnectionInspector.inspectQueue(pairedAddress, timeout: 4)
                guard !Task.isCancelled, self.pairedPortCheckToken == token,
                      self.connectionGeneration == generation, self.endpoint == source,
                      self.isConnected, self.running.isEmpty, self.pending.isEmpty else { return }
                if inspection.isIdle {
                    self.pairedQueueStatus = .empty
                } else {
                    let firstJob = inspection.running.first ?? inspection.pending.first
                    self.pairedQueueStatus = .work(running: inspection.running.count,
                        waiting: inspection.pending.count, title: firstJob?.title)
                }
            } catch {
                guard !Task.isCancelled, self.pairedPortCheckToken == token,
                      self.connectionGeneration == generation, self.endpoint == source,
                      self.isConnected, self.running.isEmpty, self.pending.isEmpty else { return }
                self.pairedQueueStatus = .issue(PairedPortIssue.classify(error))
            }
        }
    }

    private func clearPairedPortCheck(resetThrottle: Bool) {
        pairedPortCheckToken = UUID()
        pairedPortCheckTask?.cancel()
        pairedPortCheckTask = nil
        pairedPortEndpoint = nil
        pairedQueueStatus = nil
        if resetThrottle { lastPairedPortCheck = nil }
    }

    func retryPairedPortCheck() {
        lastPairedPortCheck = nil
        schedulePairedPortCheck(generation: connectionGeneration)
    }

    private func refreshHistory(force: Bool) async {
        guard force || lastHistoryPoll.map({ Date().timeIntervalSince($0) >= 15 }) ?? true else { return }
        lastHistoryPoll = Date()
        let source = endpoint
        let generation = connectionGeneration
        do {
            let data = try await requestData(path: "history", queryItems: [URLQueryItem(name: "max_items", value: "200")])
            guard let history = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw QueueError.invalidResponse }
            guard source == endpoint, generation == connectionGeneration else { return }
            completed = CompletionHistory.parse(history, now: Date(), maxAge: nil, limit: 200, title: Self.jobTitle)
            failures = HistoryDetails.failures(history, title: Self.jobTitle)
            processHistoryNotifications(ids: Set(history.keys))
            historyUnavailable = false
            ingestAgentHistory(history, endpoint: source)
            // Individual history queries recover subscribed jobs outside the UI's 200-entry window.
            let ids = agentBridge?.historyCandidates(endpoint: source, queued: Set((running + pending).map(\.id))) ?? []
            await withTaskGroup(of: Data?.self) { group in
                for id in ids where history[id] == nil {
                    group.addTask { [weak self] in
                        guard let self else { return nil }
                        return try? await self.requestData(path: "history/" + id)
                    }
                }
                for await data in group {
                    guard source == endpoint, generation == connectionGeneration, let data,
                          let entry = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                    ingestAgentHistory(entry, endpoint: source)
                }
            }
        } catch {
            guard source == endpoint, generation == connectionGeneration else { return }
            // History errors never disconnect a working queue or imply that jobs completed.
            historyUnavailable = true
        }
    }

    func refreshProgress(forceBridgeCheck: Bool = false) async {
        guard !isProgressLoading else { return }
        guard isConnected, let job = running.first else {
            queueProgress = nil
            return
        }
        if progressBridgeStatus == .missing && !forceBridgeCheck { return }

        isProgressLoading = true
        let generation = connectionGeneration
        defer { isProgressLoading = false }

        do {
            let data = try await requestData(path: "comfyqueuebar/queue-progress")
            let snapshot = try JSONDecoder().decode(QueueProgress.self, from: data)
            // The queue can change while this request is in flight. Never let
            // a response for the previous running prompt overwrite the new
            // job's progress state.
            guard generation == connectionGeneration, running.first?.id == job.id else { return }
            progressBridgeStatus = .available
            queueProgress = snapshot.promptID == job.id ? snapshot : nil
        } catch QueueError.serverStatus(let status, _) where status == 404 {
            guard generation == connectionGeneration, running.first?.id == job.id else { return }
            progressBridgeStatus = .missing
            queueProgress = nil
        } catch {
            guard generation == connectionGeneration, running.first?.id == job.id else { return }
            progressBridgeStatus = .error
            queueProgress = nil
        }
    }

    func moveToFront(_ requestedJob: QueueJob) async {
        guard hasFreshQueue, movingJobID == nil, stoppingJobID == nil, !isLoading else { return }
        movingJobID = requestedJob.id
        actionMessage = nil
        actionIsError = false
        let generation = connectionGeneration
        var originalID: String?
        var originalShortID = requestedJob.shortID
        var replacementID: String?

        do {
            let before = try await fetchQueue()
            let currentPending = Self.parseJobs(before["queue_pending"])
            guard let job = currentPending.first(where: { $0.id == requestedJob.id }) else {
                throw QueueError.jobNoLongerPending
            }
            guard generation == connectionGeneration else { throw QueueError.serverChanged }
            originalID = job.id
            originalShortID = job.shortID

            let submittedData = try await requestData(
                path: "prompt",
                method: "POST",
                body: ["prompt": job.prompt, "extra_data": job.extraData, "front": true]
            )
            guard let submitted = try JSONSerialization.jsonObject(with: submittedData) as? [String: Any],
                  let newID = submitted["prompt_id"] as? String else {
                throw QueueError.invalidResponse
            }
            replacementID = newID

            guard generation == connectionGeneration else { throw QueueError.serverChanged }
            let afterSubmit = try await fetchQueue()
            let originalStarted = Self.parseJobs(afterSubmit["queue_running"]).contains { $0.id == job.id }
            if originalStarted {
                throw QueueError.jobAlreadyRunning
            }

            guard generation == connectionGeneration else { throw QueueError.serverChanged }
            try await deletePendingJob(id: job.id)
            let afterDelete = try await fetchQueue()
            let oldStillPending = Self.parseJobs(afterDelete["queue_pending"]).contains { $0.id == job.id }
            let oldNowRunning = Self.parseJobs(afterDelete["queue_running"]).contains { $0.id == job.id }
            if oldNowRunning { throw QueueError.jobAlreadyRunning }
            if oldStillPending { throw QueueError.originalStillPending }

            actionMessage = L10n.text("Moved to the front of the waiting queue. New job ID: %@", String(String(newID.prefix(8))))
        } catch {
            if let originalID, let replacementID, generation == connectionGeneration {
                let recovery = await recoverSubmission(
                    originalID: originalID,
                    originalShortID: originalShortID,
                    replacementID: replacementID,
                    reason: error.localizedDescription
                )
                actionMessage = recovery.message
                actionIsError = recovery.isError
            } else {
                actionMessage = error.localizedDescription
                actionIsError = true
            }
        }

        movingJobID = nil
        await refresh()
    }

    func stopRunning(_ requestedJob: QueueJob) async {
        guard hasFreshQueue, movingJobID == nil, stoppingJobID == nil, !isLoading else { return }
        let generation = connectionGeneration
        stoppingJobID = requestedJob.id
        actionMessage = nil
        actionIsError = false

        do {
            let snapshot = try await fetchQueue()
            let currentRunning = Self.parseJobs(snapshot["queue_running"])
            guard currentRunning.contains(where: { $0.id == requestedJob.id }) else {
                throw QueueError.jobNoLongerRunning
            }

            guard generation == connectionGeneration else { throw QueueError.serverChanged }
            _ = try await requestData(path: "interrupt", method: "POST", body: ["prompt_id": requestedJob.id])

            var stopped = false
            for _ in 0..<10 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard generation == connectionGeneration else { throw QueueError.serverChanged }
                let updated = try await fetchQueue()
                apply(updated)
                isConnected = true
                needsSignIn = false
                errorMessage = nil
                lastUpdated = Date()
                updateMonitoringState()
                if !Self.parseJobs(updated["queue_running"]).contains(where: { $0.id == requestedJob.id }) {
                    stopped = true
                    break
                }
            }

            if stopped {
                actionMessage = L10n.text("The job has stopped. The next waiting job can now run.")
            } else {
                actionMessage = L10n.text("Stop requested. ComfyUI has not yet reported that the job ended.")
                actionIsError = true
            }
        } catch {
            actionMessage = error.localizedDescription
            actionIsError = true
        }

        stoppingJobID = nil
        await refresh()
    }

    private func recoverSubmission(
        originalID: String,
        originalShortID: String,
        replacementID: String,
        reason: String
    ) async -> (message: String, isError: Bool) {
        let replacementShortID = String(replacementID.prefix(8))
        guard let snapshot = try? await fetchQueue() else {
            return (L10n.text("Could not confirm the result. Refresh and check original ID %@ and new ID %@.", originalShortID, replacementShortID) + "\n" + reason, true)
        }

        let originalPending = Self.parseJobs(snapshot["queue_pending"]).contains { $0.id == originalID }
        let originalRunning = Self.parseJobs(snapshot["queue_running"]).contains { $0.id == originalID }
        let replacementPending = Self.parseJobs(snapshot["queue_pending"]).contains { $0.id == replacementID }
        let replacementRunning = Self.parseJobs(snapshot["queue_running"]).contains { $0.id == replacementID }

        if originalRunning {
            if replacementPending {
                try? await deletePendingJob(id: replacementID)
                if let afterCleanup = try? await fetchQueue(),
                   !Self.parseJobs(afterCleanup["queue_pending"]).contains(where: { $0.id == replacementID }) {
                    return (L10n.text("The original job started. The resubmitted entry was removed; the running job was not interrupted."), false)
                }
            }
            return (L10n.text("Could not confirm duplicate cleanup. Refresh now and check original ID %@ and new ID %@.", String(originalShortID), String(replacementShortID)), true)
        }

        if originalPending {
            if !replacementRunning {
                try? await deletePendingJob(id: originalID)
                if let afterRetry = try? await fetchQueue() {
                    let originalStillPending = Self.parseJobs(afterRetry["queue_pending"]).contains { $0.id == originalID }
                    let originalNowRunning = Self.parseJobs(afterRetry["queue_running"]).contains { $0.id == originalID }
                    if !originalStillPending && !originalNowRunning {
                        return (L10n.text("Moved to the front of the waiting queue. New job ID: %@", String(replacementShortID)), false)
                    }
                }
            }

            if replacementPending {
                try? await deletePendingJob(id: replacementID)
                if let afterCleanup = try? await fetchQueue(),
                   !Self.parseJobs(afterCleanup["queue_pending"]).contains(where: { $0.id == replacementID }) {
                    return (L10n.text("Prioritization failed. The resubmitted entry was removed; the original job remains queued."), true)
                }
            }
            return (L10n.text("Could not confirm prioritization or cleanup. Refresh now and check original ID %@ and new ID %@.", String(originalShortID), String(replacementShortID)), true)
        }

        if replacementPending {
            try? await deletePendingJob(id: replacementID)
            if let afterCleanup = try? await fetchQueue(),
               !Self.parseJobs(afterCleanup["queue_pending"]).contains(where: { $0.id == replacementID }) {
                return (L10n.text("The original job left the waiting queue. The resubmitted entry was removed."), false)
            }
        }

        if replacementRunning {
            return (L10n.text("The original job status is unknown, but the resubmitted job started. Refresh and check IDs %@ and %@.", String(originalShortID), String(replacementShortID)), true)
        }
        return (L10n.text("The original job left the waiting queue. Refresh to check the result.") + "\n" + reason, true)
    }

    private func fetchQueue() async throws -> [String: Any] {
        let data = try await requestData(path: "queue")
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              ComfyQueuePayload.isValid(object) else {
            throw QueueError.invalidResponse
        }
        return object
    }

    private func requestData(path: String, method: String = "GET", body: [String: Any]? = nil, queryItems: [URLQueryItem] = []) async throws -> Data {
        #if DOCUMENTATION_SCREENSHOT
        throw QueueError.invalidEndpoint // Documentation builds never contact a server.
        #else
        guard var components = URLComponents(string: endpoint),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil, components.user == nil, components.password == nil else {
            throw QueueError.invalidEndpoint
        }

        let basePath = components.path.split(separator: "/").joined(separator: "/")
        components.path = "/" + [basePath, path].filter { !$0.isEmpty }.joined(separator: "/")
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        components.fragment = nil
        guard let url = components.url else { throw QueueError.invalidEndpoint }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await ComfyHTTPClient.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let detail = String(data: data.prefix(400), encoding: .utf8)
            throw QueueError.serverStatus(status, detail)
        }
        return data
        #endif
    }

    private func deletePendingJob(id: String) async throws {
        _ = try await requestData(path: "queue", method: "POST", body: ["delete": [id]])
    }

    private func apply(_ snapshot: [String: Any]) {
        running = Self.parseJobs(snapshot["queue_running"])
        pending = Self.parseJobs(snapshot["queue_pending"])
        for job in running where observedStarts[job.id] == nil { observedStarts[job.id] = Date() }
        observedStarts = observedStarts.filter { id, _ in running.contains { $0.id == id } }
        notificationTracker.observeQueue(count: totalJobs)
        if let queueProgress, running.first?.id != queueProgress.promptID {
            self.queueProgress = nil
        }
    }

    private func setDisconnected(_ message: String, requiresSignIn: Bool = false) {
        if isConnected && notifyProblems {
            NotificationService.shared.send(id: UUID().uuidString, title: L10n.text("Server disconnected"), body: serverName)
        }
        isConnected = false
        historyUnavailable = true
        running = []
        pending = []
        queueProgress = nil
        errorMessage = message
        needsSignIn = requiresSignIn
        updateMonitoringState()
    }

    static func parseJobs(_ value: Any?) -> [QueueJob] {
        guard let rows = value as? [[Any]] else { return [] }
        return rows.enumerated().compactMap { index, row in
            guard row.count > 1, let promptID = row[1] as? String else { return nil }
            let prompt = row.count > 2 ? row[2] as? [String: Any] ?? [:] : [:]
            let extra = row.count > 3 ? row[3] as? [String: Any] ?? [:] : [:]
            let title = jobTitle(prompt: prompt, extra: extra)
            let nodeCount = prompt.count
            let queueNumber = (row.first as? NSNumber)?.intValue
            return QueueJob(
                id: promptID,
                title: title,
                nodeCount: nodeCount,
                queueNumber: queueNumber,
                position: index + 1,
                prompt: prompt,
                extraData: extra
            )
        }
    }

    static func jobTitle(prompt: [String: Any], extra: [String: Any]) -> String {
        if let pngInfo = extra["extra_pnginfo"] as? [String: Any],
           let workflow = pngInfo["workflow"] as? [String: Any],
           let name = workflow["name"] as? String,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }

        for node in prompt.values {
            guard let node = node as? [String: Any],
                  let meta = node["_meta"] as? [String: Any],
                  let title = meta["title"] as? String,
                  !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            return title
        }

        for node in prompt.values {
            guard let node = node as? [String: Any],
                  let inputs = node["inputs"] as? [String: Any] else { continue }
            for key in ["filename_prefix", "file_prefix"] {
                if let value = displayValue(inputs[key]), !value.isEmpty { return value }
            }
        }
        return L10n.text("ComfyUI workflow")
    }

    private static func displayValue(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        if let object = value as? [String: Any], let text = object["value"] as? String { return text }
        return nil
    }
}

struct CompletedJob: Identifiable {
    let id: String
    let title: String
    let finishedAt: Date?
    let filenames: [String]
    let queueNumber: Double
    var outputs: [MediaOutput] = []
    var startedAt: Date? = nil
    var fingerprint: String = ""
}

// Only explicit successful, completed history records qualify. Never infer success from /queue.
enum CompletionHistory {
    static func parse(_ history: [String: Any], now: Date, maxAge: TimeInterval? = 86400, limit: Int = 20, title: ([String: Any], [String: Any]) -> String) -> [CompletedJob] {
        let cutoff = maxAge.map { now.addingTimeInterval(-$0) }
        let jobs: [CompletedJob] = history.compactMap { id, value in
            guard let entry = value as? [String: Any],
                  let status = entry["status"] as? [String: Any],
                  status["completed"] as? Bool == true,
                  status["status_str"] as? String == "success" else { return nil }
            let messages = status["messages"] as? [[Any]] ?? []
            guard !messages.contains(where: { ["execution_error", "execution_interrupted"].contains($0.first as? String ?? "") }) else { return nil }
            let milliseconds = messages.compactMap { message -> Double? in
                guard message.first as? String == "execution_success", message.count > 1,
                      let details = message[1] as? [String: Any], let timestamp = details["timestamp"] as? NSNumber else { return nil }
                let value = timestamp.doubleValue
                return value.isFinite && value > 0 ? value : nil
            }.max()
            let date = milliseconds.map { Date(timeIntervalSince1970: $0 / 1000) }
            if let date, let cutoff, date < cutoff { return nil }
            let prompt = entry["prompt"] as? [Any] ?? []
            let graph = prompt.count > 2 ? prompt[2] as? [String: Any] ?? [:] : [:]
            let extra = prompt.count > 3 ? prompt[3] as? [String: Any] ?? [:] : [:]
            var files = Set<String>()
            collectFiles(entry["outputs"] as Any, into: &files)
            let outputs = HistoryDetails.outputs(entry["outputs"] as Any)
            return CompletedJob(id: id, title: title(graph, extra), finishedAt: date, filenames: files.sorted(), queueNumber: (prompt.first as? NSNumber)?.doubleValue ?? 0, outputs: outputs, startedAt: HistoryDetails.eventDate(messages, events: ["execution_start"]), fingerprint: HistoryDetails.fingerprint(graph))
        }
        return Array(jobs.sorted {
            if $0.finishedAt != $1.finishedAt { return ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
            if $0.queueNumber != $1.queueNumber { return $0.queueNumber > $1.queueNumber }
            return $0.id < $1.id
        }.prefix(limit))
    }

    private static func collectFiles(_ value: Any, into files: inout Set<String>) {
        if let object = value as? [String: Any] {
            if let filename = object["filename"] as? String, !filename.isEmpty, object["type"] as? String != "temp" {
                let subfolder = object["subfolder"] as? String ?? ""
                files.insert(subfolder.isEmpty ? filename : subfolder + "/" + filename)
            }
            for nested in object.values { collectFiles(nested, into: &files) }
        } else if let array = value as? [Any] {
            for nested in array { collectFiles(nested, into: &files) }
        }
    }
}

struct QueueJob: Identifiable {
    let id: String
    let title: String
    let nodeCount: Int
    let queueNumber: Int?
    let position: Int
    let prompt: [String: Any]
    let extraData: [String: Any]

    var shortID: String { String(id.prefix(8)) }
}

struct QueueProgress: Decodable {
    let promptID: String?
    let nodeID: String?
    let value: Double?
    let maxValue: Double?
    let percent: Double?
    let state: String?

    enum CodingKeys: String, CodingKey {
        case promptID = "prompt_id"
        case nodeID = "node_id"
        case value
        case maxValue = "max"
        case percent
        case state
    }

    func nodeTitle(for job: QueueJob) -> String {
        guard let nodeID else { return L10n.text("Waiting for node progress") }
        if let node = job.prompt[nodeID] as? [String: Any],
           let meta = node["_meta"] as? [String: Any],
           let title = meta["title"] as? String,
           !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        return L10n.text("Node %@", String(nodeID))
    }
}

enum ProgressBridgeStatus: Equatable {
    case checking
    case available
    case missing
    case error
}

enum QueueError: LocalizedError {
    case invalidEndpoint
    case serverChanged
    case serverStatus(Int, String?)
    case invalidResponse
    case jobNoLongerPending
    case jobAlreadyRunning
    case jobNoLongerRunning
    case originalStillPending

    var errorDescription: String? {
        switch self {
        case .serverChanged: return L10n.text("Server changed. Refresh before trying again.")
        case .invalidEndpoint: return L10n.text("Enter a valid http:// or https:// address.")
        case .serverStatus(let status, let detail):
            return L10n.text("ComfyUI returned HTTP %@.", String(status)) + (detail.map { " \($0)" } ?? "")
        case .invalidResponse: return L10n.text("ComfyUI returned an unrecognized queue response.")
        case .jobNoLongerPending: return L10n.text("This job is no longer waiting. Refresh and try again.")
        case .jobAlreadyRunning: return L10n.text("The original job started. Prioritization was canceled; the running job will continue.")
        case .jobNoLongerRunning: return L10n.text("This job is no longer running. No stop request was sent.")
        case .originalStillPending: return L10n.text("ComfyUI did not remove the original job. Checking resubmission cleanup.")
        }
    }
}

enum QueueBrand {
    static let menuBarIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 19, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            // Three queue rows with a separate play marker, readable at menu-bar size.
            for y in [3.0, 8.0, 13.0] {
                NSBezierPath(roundedRect: NSRect(x: 1, y: y, width: 10, height: 2), xRadius: 1, yRadius: 1).fill()
            }
            let play = NSBezierPath()
            play.move(to: NSPoint(x: 13, y: 5))
            play.line(to: NSPoint(x: 13, y: 13))
            play.line(to: NSPoint(x: 18, y: 9))
            play.close()
            play.fill()
            return true
        }
        image.isTemplate = true
        return image
    }()

    static var panelIcon: Image {
        if let url = Bundle.main.url(forResource: "AppIconPreview", withExtension: "png"), let icon = NSImage(contentsOf: url) {
            return Image(nsImage: icon)
        }
        return Image(systemName: "square.stack.3d.up.fill")
    }
}

#if DOCUMENTATION_SCREENSHOT
@main
struct DocumentationCapture {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let dark = CommandLine.arguments.contains("--dark")
        app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        if CommandLine.arguments.contains("--menu-bar") {
            let status = NSStatusBar.system.statusItem(withLength: 52)
            guard let button = status.button else { fatalError("No status button") }
            button.image = QueueBrand.menuBarIcon
            button.imagePosition = .imageLeading
            button.title = " 2"
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .popUpMenu
            panel.contentView = NSHostingView(rootView: QueuePopover(queue: QueueViewModel()).frame(width: 360, height: 600).clipShape(RoundedRectangle(cornerRadius: 12)))
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 1))
            let anchor = button.window!.convertToScreen(button.convert(button.bounds, to: nil))
            panel.setFrameOrigin(NSPoint(x: anchor.midX - 180, y: anchor.minY - 608))
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            app.activate(ignoringOtherApps: true)
            panel.orderFrontRegardless()
            if let argument = CommandLine.arguments.firstIndex(of: "--desktop-output") {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 2))
                let region = "\(Int(panel.frame.minX)),\(Int(NSScreen.screens[0].frame.maxY - anchor.maxY)),360,\(Int(anchor.height) + 608)"
                let capture = Process()
                capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                capture.arguments = ["-x", "-R", region, CommandLine.arguments[argument + 1]]
                try! capture.run(); capture.waitUntilExit()
                precondition(capture.terminationStatus == 0)
                panel.close()
                return
            }
            withExtendedLifetime((status, panel)) { app.run() }
            return
        }
        let queue = QueueViewModel()
        let settings = CommandLine.arguments.contains("--settings")
        let preview = CommandLine.arguments.contains("--preview")
        let width: CGFloat = preview ? 440 : 360
        let height: CGFloat = preview ? 460 : (settings ? 480 : 600)
        let previewModel = MediaPreviewModel()
        let root = preview ? AnyView(MediaPreview(job: queue.completed[0], endpoint: queue.endpoint, model: previewModel).frame(width: 440, height: 460).background(.regularMaterial)) : settings ? AnyView(QueuePopover(queue: queue).settingsContent.frame(width: 360, height: 480, alignment: .top).background(.regularMaterial)) : AnyView(QueuePopover(queue: queue))
        let view = NSHostingView(rootView: root.frame(width: width, height: height))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.center()
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 2))
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("Cannot capture view") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode PNG") }
        try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        window.close()
    }
}
#else
@main
struct ComfyQueueBarApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = StatusBarController()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

#endif

@MainActor
final class QueuePopoverState: ObservableObject {
    @Published var urlInput = ""
    @Published var confirmation: QueueConfirmation?
    @Published var showsSettings = false
    @Published var profileName = ""
    @Published var historyRange: HistoryRange = .day
    @Published var historySearch = ""
    @Published var showsFailures = false
}

struct QueuePopover: View {
    @ObservedObject var queue: QueueViewModel
    @StateObject private var panel = QueuePopoverState()
    #if !DOCUMENTATION_SCREENSHOT
    @ObservedObject private var updater = AppUpdater.shared
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !queue.isConnected { connectionSettings }
                    actionFeedback
                    runningSection
                    pendingSection
                    completedSection
                    failureSection
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            footer
        }
        .background(.regularMaterial)
        .onAppear { panel.urlInput = queue.endpoint }
        .onChange(of: queue.endpoint) { panel.urlInput = $0 }
        .confirmationDialog(panel.confirmation?.title ?? L10n.text("Confirm action"), isPresented: Binding(
            get: { panel.confirmation.map { _ in true } ?? false },
            set: { if !$0 { panel.confirmation = nil } }
        ), titleVisibility: .visible) {
            if let confirmation = panel.confirmation {
                switch confirmation {
                case .prioritize(let job):
                    Button(L10n.text("Prioritize and resubmit")) {
                        panel.confirmation = nil
                        Task { await queue.moveToFront(job) }
                    }
                case .stop(let job):
                    Button(L10n.text("Stop running job"), role: .destructive) {
                        panel.confirmation = nil
                        Task { await queue.stopRunning(job) }
                    }
                }
            }
            Button(L10n.text("Cancel"), role: .cancel) { panel.confirmation = nil }
        } message: {
            Text(panel.confirmation?.message ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            QueueBrand.panelIcon
                .resizable()
                .scaledToFit()
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("ComfyQueueBar")
                    .font(.system(size: 13, weight: .semibold))
                HStack(spacing: 5) {
                    Circle()
                        .fill(queue.hasFreshQueue ? Color.green : Color.orange)
                        .frame(width: 5, height: 5)
                    Menu {
                        ForEach(queue.profiles) { profile in
                            Button(profile.name + " · " + ConnectionAddress.portLabel(profile.endpoint)) {
                                panel.urlInput = profile.endpoint; panel.profileName = profile.name
                                queue.reviewConnection(to: profile.endpoint)
                            }
                        }
                    } label: {
                        Text(queue.serverName)
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .menuStyle(.borderlessButton)
                    .disabled(queue.profiles.isEmpty || !queue.canChangeServer)
                }
                .accessibilityLabel(queue.serverName + " · " + queue.monitoringState.label)
                Text(ConnectionAddress.portLabel(queue.endpoint) + " · " + (queue.hasFreshQueue ? L10n.text("ComfyUI job count") : queue.monitoringState.label))
                    .font(.system(size: 10)).foregroundStyle(queue.hasFreshQueue ? Color.secondary : Color.orange)
                    .help(queue.endpoint)
            }
            Spacer()
            Button {
                Task { await queue.refresh(forceHistory: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(queue.isLoading || queue.movingJobID != nil || queue.stoppingJobID != nil)
            .help(L10n.text("Refresh now"))
            .accessibilityLabel(L10n.text("Refresh now"))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Divider() }
    }

    #if !DOCUMENTATION_SCREENSHOT
    private var updateSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(L10n.text("Automatically update the app"), isOn: $updater.automaticallyUpdates)
            .toggleStyle(.checkbox)
            Button(L10n.text("Check for updates…")) { AppUpdater.shared.check() }
                .controlSize(.small)
        }
        .font(.system(size: 11))
    }
    #endif

    private var serverSettings: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(L10n.text("Saved addresses")).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            ForEach(queue.profiles) { profile in
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Button {
                            panel.urlInput = profile.endpoint
                            panel.profileName = profile.name
                            queue.reviewConnection(to: profile.endpoint)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(profile.name).fontWeight(.medium)
                                Text(profile.endpoint).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                                    .lineLimit(2).textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain).disabled(!queue.canChangeServer)
                        if profile.endpoint == queue.endpoint { Image(systemName: "checkmark").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Button { queue.deleteProfile(profile.id) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.plain).help(L10n.text("Remove server"))
                    }
                    WakeSettingsView(queue: queue, profile: profile)
                }
            }
        }.font(.system(size: 11))
    }

    private var progressExtensionSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("Node progress")).font(.subheadline).fontWeight(.medium)
            Button(L10n.text("Install progress extension…")) {
                let panel = NSOpenPanel()
                panel.title = L10n.text("Choose the ComfyUI folder")
                panel.message = L10n.text("Installs on this Mac only. For a remote ComfyUI server, install the extension on that server.")
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                guard panel.runModal() == .OK, let folder = panel.url else { return }
                let didAccess = folder.startAccessingSecurityScopedResource()
                defer { if didAccess { folder.stopAccessingSecurityScopedResource() } }
                queue.installProgressExtension(in: folder)
            }
            .controlSize(.small)
            Text(L10n.text("Installs on this Mac only. For a remote ComfyUI server, install the extension on that server."))
                .font(.caption).foregroundStyle(.secondary)
            if let message = queue.progressExtensionMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
            if let error = queue.progressExtensionError { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
        }
        .font(.system(size: 11))
    }
    private var notificationSettings: some View {
        VStack(alignment: .leading, spacing: 9) {
            Picker(L10n.text("Completion notifications"), selection: $queue.notificationMode) {
                Text(L10n.text("Off")).tag("off")
                Text(L10n.text("Every job")).tag("each")
                Text(L10n.text("Whole batch")).tag("batch")
            }.controlSize(.small)
            .onChange(of: queue.notificationMode) { mode in
                if mode != "off" { Task { await queue.authorizeNotifications() } }
            }
            Toggle(L10n.text("Notify failures and disconnections"), isOn: $queue.notifyProblems).toggleStyle(.checkbox)
                .onChange(of: queue.notifyProblems) { enabled in if enabled { Task { await queue.authorizeNotifications() } } }
            if let message = queue.permissionMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
        }.font(.system(size: 11))
    }

    private var connectionSettings: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L10n.text("ComfyUI address"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("http://127.0.0.1:8188", text: $panel.urlInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit { queue.reviewConnection(to: panel.urlInput) }
                Button(L10n.text("Connect")) {
                    queue.reviewConnection(to: panel.urlInput)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!queue.canChangeServer)
            }
            HStack(spacing: 8) {
                TextField(L10n.text("Server name"), text: $panel.profileName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                Button(L10n.text("Save address")) {
                    if queue.saveProfile(name: panel.profileName, address: panel.urlInput) {
                        panel.profileName = ""
                    }
                }.controlSize(.small)
            }
            HStack {
                Button(L10n.text("Sign in to GPUtw…")) { queue.signInToGPUTW(address: panel.urlInput) }
                Button(L10n.text("Clear GPUtw sign-in")) { Task { await queue.clearGPUTWLogin() } }
            }.controlSize(.small).disabled(!queue.canChangeServer || queue.isClearingGPUTW)
            Text(L10n.text("For private or password-protected GPUtw ComfyUI instances."))
                .font(.caption).foregroundStyle(.secondary)
            if let message = queue.connectionMessage {
                Text(message).font(.caption)
                    .foregroundStyle(queue.connectionMessageIsError ? Color.red : Color.secondary)
            }
            if !queue.profiles.isEmpty { serverSettings.padding(.top, 6) }
        }
    }

    private var runningSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionHeading(L10n.text("Running"), count: queue.hasFreshQueue ? queue.running.count : nil, symbol: "waveform.path")
            if !queue.hasFreshQueue {
                connectionError
            } else if queue.running.isEmpty {
                emptyState(L10n.text("No jobs are running"), symbol: "checkmark.circle")
                if queue.pending.isEmpty {
                    if let pairedEndpoint = queue.pairedPortEndpoint {
                        pairedPortStatus(endpoint: pairedEndpoint)
                    } else {
                        Text(L10n.text("Expecting a running job? Check the server port.")).font(.caption).foregroundStyle(.secondary)
                        Button(L10n.text("Review this connection")) { queue.reviewConnection(to: queue.endpoint) }
                            .buttonStyle(.link).font(.caption)
                    }
                }
            } else {
                VStack(spacing: 0) {
                ForEach(queue.running) { job in
                    JobCard(
                        job: job,
                        state: .running,
                        progress: queue.queueProgress,
                        progressBridgeStatus: queue.progressBridgeStatus,
                        isMoving: false,
                        isStopping: queue.stoppingJobID == job.id,
                        isActionEnabled: queue.movingJobID == nil && queue.stoppingJobID == nil && !queue.isLoading,
                        onPrioritize: nil,
                        onStop: { panel.confirmation = .stop(job) },
                        timing: { now in queue.timingText(for: job, now: now) }
                    )
                    if job.id != queue.running.last?.id { Divider().padding(.leading, 14) }
                }
                }
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5) }
            }
        }
    }

    @ViewBuilder
    private func pairedPortStatus(endpoint: String) -> some View {
        let port = ConnectionAddress.port(endpoint)
        VStack(alignment: .leading, spacing: 6) {
            switch queue.pairedQueueStatus {
            case .checking:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(L10n.text("Checking paired GPUtw port %@…", port))
                }.font(.caption).foregroundStyle(.secondary)
            case .empty:
                Text(L10n.text("Paired port %@ is also empty.", port))
                    .font(.caption).foregroundStyle(.secondary)
            case .work(let running, let waiting, let title):
                Label(L10n.text("Found work on paired port %@.", port), systemImage: "arrow.left.arrow.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                Text(L10n.text("Running %@ · Waiting %@", String(running), String(waiting)))
                    .font(.caption).foregroundStyle(.secondary)
                if let title {
                    Text(title).font(.caption).lineLimit(2).help(title)
                }
            case .issue(.portNotEnabled):
                Text(L10n.text("GPUtw port %@ returned 404. Enable it as an HTTP port in Network Ports; private ports need one dashboard handoff from Other ports.", port))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(L10n.text("Open GPUtw dashboard")) {
                    queue.signInToGPUTW(address: GPUTWAddress.dashboard.absoluteString)
                }.buttonStyle(.link).font(.caption)
            case .issue(.signInRequired):
                Text(L10n.text("GPUtw port %@ needs an owner session. Open it from the dashboard's Other ports menu.", port))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(L10n.text("Open GPUtw dashboard")) {
                    queue.signInToGPUTW(address: GPUTWAddress.dashboard.absoluteString)
                }.buttonStyle(.link).font(.caption)
            case .issue(.unavailable):
                Text(L10n.text("Could not check paired GPUtw port %@. Check your connection and retry.", port))
                    .font(.caption).foregroundStyle(.secondary)
                Button(L10n.text("Retry paired port check"), action: queue.retryPairedPortCheck)
                    .buttonStyle(.link).font(.caption)
            case nil:
                Text(L10n.text("Expecting a running job? Check the server port."))
                    .font(.caption).foregroundStyle(.secondary)
                Button(L10n.text("Review this connection")) { queue.reviewConnection(to: queue.endpoint) }
                    .buttonStyle(.link).font(.caption)
            }
            if case .work = queue.pairedQueueStatus {
                Button(L10n.text("Review Port %@", port)) { queue.reviewConnection(to: endpoint) }
                    .buttonStyle(.link).font(.caption)
            } else if case .empty = queue.pairedQueueStatus {
                Button(L10n.text("Review this connection")) { queue.reviewConnection(to: queue.endpoint) }
                    .buttonStyle(.link).font(.caption)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionHeading(L10n.text("Waiting queue"), count: queue.hasFreshQueue ? queue.pending.count : nil, symbol: "list.number")
            if queue.hasFreshQueue && queue.pending.isEmpty {
                emptyState(L10n.text("No waiting jobs"), symbol: "tray")
            } else if queue.hasFreshQueue {
                VStack(spacing: 0) {
                ForEach(queue.pending) { job in
                    JobCard(
                        job: job,
                        state: .pending,
                        progress: nil,
                        progressBridgeStatus: .checking,
                        isMoving: queue.movingJobID == job.id,
                        isStopping: false,
                        isActionEnabled: queue.movingJobID == nil && queue.stoppingJobID == nil && !queue.isLoading,
                        onPrioritize: { panel.confirmation = .prioritize(job) },
                        onStop: nil
                    )
                    if job.id != queue.pending.last?.id { Divider().padding(.leading, 14) }
                }
                }
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5) }
            }
        }
    }

    private var filteredCompleted: [CompletedJob] {
        queue.completed.filter { job in
            panel.historyRange.includes(job.finishedAt) && (panel.historySearch.isEmpty || ([job.title] + job.filenames).joined(separator: " ").localizedCaseInsensitiveContains(panel.historySearch))
        }
    }
    private var filteredFailures: [FailedJob] {
        queue.failures.filter { job in
            panel.historyRange.includes(job.date) && (panel.historySearch.isEmpty || (job.title + " " + job.reason).localizedCaseInsensitiveContains(panel.historySearch))
        }
    }
    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionHeading(L10n.text("Recently completed"), count: filteredCompleted.count, symbol: "checkmark")
            HStack {
                Picker(L10n.text("Time range"), selection: $panel.historyRange) {
                    ForEach(HistoryRange.allCases, id: \.self) { range in Text(L10n.text(range.label)).tag(range) }
                }.labelsHidden().controlSize(.small).frame(width: 140)
                TextField(L10n.text("Search history"), text: $panel.historySearch).textFieldStyle(.roundedBorder).font(.system(size: 11))
            }
            Text(L10n.text("Newest 200 server records"))
                .font(.system(size: 10)).foregroundStyle(.tertiary)
            if queue.historyUnavailable {
                Text(L10n.text("History unavailable. Showing the last successful refresh.")).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if filteredCompleted.isEmpty && !queue.historyUnavailable {
                emptyState(L10n.text("No recently completed jobs"), symbol: "checkmark.circle")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filteredCompleted) { job in
                        CompletionRow(job: job, endpoint: queue.endpoint)
                        if job.id != filteredCompleted.last?.id { Divider().padding(.leading, 14) }
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5) }
            }
        }
    }
    private var failureSection: some View {
        DisclosureGroup(isExpanded: $panel.showsFailures) {
            if filteredFailures.isEmpty {
                Text(L10n.text("No failures in this range")).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(filteredFailures) { job in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(job.title).font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text(L10n.text(job.interrupted ? "Interrupted" : "Failed")).font(.caption).foregroundStyle(.secondary)
                    }
                    if let date = job.date { Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                    Text(job.reason.isEmpty ? L10n.text("No error details reported") : job.reason).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Text(String(job.id.prefix(8))).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                }.padding(.vertical, 8)
                Divider()
            }
        } label: {
            Text(L10n.text("Failures & interruptions") + " · " + String(filteredFailures.count)).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actionFeedback: some View {
        if let message = queue.actionMessage {
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(queue.actionIsError ? Color.red : Color.green)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background((queue.actionIsError ? Color.red : Color.green).opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
        } else if queue.movingJobID != nil || queue.stoppingJobID != nil {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(queue.movingJobID != nil ? L10n.text("Moving job to the front…") : L10n.text("Stopping job…"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
        }
    }

    private var connectionError: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(queue.monitoringState.label)
                .font(.system(size: 12, weight: .semibold))
            Text(queue.monitoringState == .stale ? L10n.text("No fresh queue response for 30 seconds. The job count is unknown.")
                 : queue.monitoringState == .checking ? L10n.text("Waiting for the first queue response.")
                 : queue.errorMessage ?? L10n.text("Check that ComfyUI is running and the address is correct."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if queue.monitoringState == .signInRequired, let url = URL(string: queue.endpoint), GPUTWAddress.serviceOrigin(url) != nil {
                Button(L10n.text("Sign in to GPUtw…")) { queue.signInToGPUTW(address: queue.endpoint) }
                    .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
    }

    private var agentSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(L10n.text("AI agent integration"), isOn: $queue.agentIntegrationEnabled)
            Text(L10n.text("Let agents delegate monitoring to this app using the local MCP bridge."))
                .font(.caption).foregroundStyle(.secondary)
            Text(L10n.text("Shares queue IDs, output references, and errors with local agents. Desktop push requires host support."))
                .font(.caption).foregroundStyle(.secondary)
            if let script = Bundle.main.url(forResource: "server", withExtension: "py", subdirectory: "AgentBridge") {
                Button(L10n.text("Set up Claude and Codex")) { Task { await queue.setupAgents() } }
                    .disabled(queue.isSettingUpAgents)
                Text(L10n.text("Registers MCP and installs the shared skill for Claude Code and Codex. Replaced files are backed up; reopen agent sessions afterward."))
                    .font(.caption).foregroundStyle(.secondary)
                if queue.isSettingUpAgents { ProgressView().controlSize(.small) }
                HStack {
                    Button(L10n.text("Copy MCP configuration")) {
                        let python = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
                            .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/absolute/path/to/python3"
                        let configuration = ["mcpServers": ["comfyqueuebar": ["command": python, "args": [script.path]] as [String: Any]]]
                        if let data = try? JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted, .sortedKeys]),
                           let text = String(data: data, encoding: .utf8) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        }
                    }
                    if let guide = Bundle.main.url(forResource: "README", withExtension: "md", subdirectory: "AgentBridge") {
                        Button(L10n.text("Setup guide")) { NSWorkspace.shared.open(guide) }
                    }
                }
            }
            if let message = queue.agentSetupMessage { Text(message).font(.caption).textSelection(.enabled) }
            if let error = queue.agentBridgeError { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }

    var settingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("Settings")).font(.headline)
            connectionSettings
            Divider()
            progressExtensionSettings
            Divider()
            notificationSettings
            Divider()
            agentSettings
            #if !DOCUMENTATION_SCREENSHOT
            Divider()
            updateSettings
            #endif
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button { panel.showsSettings.toggle() } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(L10n.text("Settings"))
            .accessibilityLabel(L10n.text("Settings"))
            .popover(isPresented: $panel.showsSettings, arrowEdge: .bottom) {
                ScrollView { settingsContent }
                    .frame(width: 360, height: 480)
            }
            Text(queue.lastUpdated.map { L10n.text("Updated %@", $0.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(L10n.locale))) } ?? L10n.text("Refreshes every 4 seconds"))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
            Button(L10n.text("Quit")) { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .overlay(alignment: .top) { Divider() }
    }

    private func sectionHeading(_ title: String, count: Int?, symbol: String) -> some View {
        HStack(spacing: 7) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            Spacer()
            Text(count.map(String.init) ?? "—")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func emptyState(_ text: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.secondary)
            Text(text).foregroundStyle(.secondary)
        }
        .font(.system(size: 11))
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }
}

enum JobState {
    case running
    case pending

    var label: String { self == .running ? L10n.text("Running") : L10n.text("Waiting") }
    var color: Color { self == .running ? .cyan : .orange }
    var symbol: String { self == .running ? "bolt.fill" : "clock" }
}

enum QueueConfirmation {
    case prioritize(QueueJob)
    case stop(QueueJob)

    var title: String {
        switch self {
        case .prioritize: return L10n.text("Prioritize this job?")
        case .stop: return L10n.text("Stop this job?")
        }
    }

    var message: String {
        switch self {
        case .prioritize(let job):
            return L10n.text("Move \"%@\" to the front of the waiting queue. The running job continues. This resubmits the job and changes its prompt ID.", String(job.title))
        case .stop(let job):
            return L10n.text("Stop generation for \"%@\". Waiting jobs remain queued and the next job can run.", String(job.title))
        }
    }
}

struct JobCard: View {
    let job: QueueJob
    let state: JobState
    let progress: QueueProgress?
    let progressBridgeStatus: ProgressBridgeStatus
    let isMoving: Bool
    let isStopping: Bool
    let isActionEnabled: Bool
    let onPrioritize: (() -> Void)?
    let onStop: (() -> Void)?
    var timing: ((Date) -> String)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                if case .pending = state {
                    Text(String(job.position))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 14)
                        .padding(.top, 2)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(job.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(job.title)
                    HStack(spacing: 5) {
                        Text(L10n.text("%@ nodes", String(job.nodeCount)))
                        Text("·")
                        Text(job.shortID).font(.system(size: 10, design: .monospaced))
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if case .pending = state {
                    Button(action: { onPrioritize?() }) {
                        Image(systemName: "arrow.up.to.line")
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(!isActionEnabled || isMoving)
                    .help(L10n.text("Run next after the current job"))
                    .accessibilityLabel(isMoving ? L10n.text("Working") : L10n.text("Prioritize"))
                } else {
                    Button(action: { onStop?() }) {
                        Image(systemName: "stop.circle")
                            .font(.system(size: 18, weight: .regular))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(!isActionEnabled || isStopping)
                    .help(L10n.text("Stop this job while keeping waiting jobs"))
                    .accessibilityLabel(isStopping ? L10n.text("Stopping") : L10n.text("Stop"))
                }
            }
            if case .running = state {
                progressDetails
                if let timing {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(timing(context.date)).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            .help(L10n.text("Estimates need 3 similar successful jobs. Elapsed time starts when this app first observes the job."))
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var progressDetails: some View {
        if let progress {
            VStack(alignment: .leading, spacing: 4) {
                Text(progress.nodeTitle(for: job))
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary.opacity(0.8))
                HStack(spacing: 6) {
                    if let percent = progress.percent {
                        ProgressView(value: min(max(percent / 100, 0), 1))
                            .controlSize(.mini)
                            .frame(maxWidth: .infinity)
                        Text("\(Int(percent.rounded()))%")
                            .font(.system(size: 11))
                            .monospacedDigit()
                    } else {
                        ProgressView().controlSize(.mini)
                        Text(L10n.text("Node is processing"))
                            .font(.system(size: 10))
                    }
                }
                .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        } else {
            HStack(spacing: 5) {
                if progressBridgeStatus == .checking {
                    ProgressView().controlSize(.mini)
                }
                Text(progressStatusText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.top, 2)
        }
    }

    private var progressStatusText: String {
        switch progressBridgeStatus {
        case .checking: return L10n.text("Fetching node progress…")
        case .available: return L10n.text("No progress reported for this node yet")
        case .missing: return L10n.text("Install the progress extension and restart ComfyUI")
        case .error: return L10n.text("Unable to read live progress")
        }
    }
}


@MainActor
final class WakeSettingsDraft: ObservableObject {
    @Published var settings = WakeSettings()
    @Published var portInput = "9"
}

struct WakeSettingsView: View {
    @ObservedObject var queue: QueueViewModel
    let profile: ServerProfile
    @StateObject private var draft = WakeSettingsDraft()

    var body: some View {
        DisclosureGroup(L10n.text("Wake Mac")) {
            VStack(alignment: .leading, spacing: 8) {
                TextField(L10n.text("MAC address"), text: $draft.settings.macAddress)
                TextField(L10n.text("Broadcast IPv4 address"), text: $draft.settings.broadcastAddress)
                TextField(L10n.text("UDP port"), text: $draft.portInput)
                Toggle(L10n.text("Automatically wake when offline"), isOn: $draft.settings.automaticallyWake)
                    .toggleStyle(.checkbox)
                Text(L10n.text("Checks the selected server only. Retries every 2 minutes. Enable Wake for network access on the target Mac; the network must allow wake packets."))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(L10n.text("Save wake settings")) { save() }
                    Button(L10n.text("Wake now")) {
                        guard save() else { return }
                        queue.wakeServer(profile.id)
                    }
                }.controlSize(.small)
                if let message = queue.wakeMessages[profile.id] {
                    Text(message).font(.caption).textSelection(.enabled)
                }
            }.textFieldStyle(.roundedBorder).padding(.top, 6)
        }
        .onAppear {
            draft.settings = profile.wake ?? WakeSettings()
            draft.portInput = String(draft.settings.port)
        }
    }

    @discardableResult
    private func save() -> Bool {
        draft.settings.port = UInt16(draft.portInput) ?? 0
        queue.saveWakeSettings(draft.settings, for: profile.id)
        return (try? WakeOnLAN.validate(draft.settings)) != nil
    }
}
