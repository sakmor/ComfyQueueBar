import AppKit
import Foundation
import SwiftUI
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
        "Servers": ["伺服器", "服务器", "サーバー"],
        "Remove server": ["移除伺服器", "移除服务器", "サーバーを削除"],
        "Server name": ["伺服器名稱", "服务器名称", "サーバー名"],
        "Save address": ["儲存位址", "保存地址", "アドレスを保存"],
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

@MainActor
final class QueueViewModel: ObservableObject {
    @Published var endpoint: String
    @Published private(set) var running: [QueueJob] = []
    @Published private(set) var pending: [QueueJob] = []
    @Published private(set) var isConnected = false
    @Published private(set) var isLoading = false
    @Published private(set) var movingJobID: String?
    @Published private(set) var stoppingJobID: String?
    @Published private(set) var queueProgress: QueueProgress?
    @Published private(set) var progressBridgeStatus: ProgressBridgeStatus = .checking
    @Published private(set) var errorMessage: String?
    @Published private(set) var actionMessage: String?
    @Published private(set) var actionIsError = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var completed: [CompletedJob] = []
    @Published private(set) var historyUnavailable = false
    @Published private(set) var failures: [FailedJob] = []
    @Published private(set) var profiles: [ServerProfile] = []
    @Published private(set) var observedStarts: [String: Date] = [:]
    @Published private(set) var permissionMessage: String?
    @Published var notificationMode = "off" {
        didSet { UserDefaults.standard.set(notificationMode, forKey: "notificationMode") }
    }
    @Published var notifyProblems = false {
        didSet { UserDefaults.standard.set(notifyProblems, forKey: "notifyProblems") }
    }
    private var notificationTracker = NotificationTracker()
    private var connectionGeneration = UUID()
    private var lastHistoryPoll: Date?

    private var refreshTimer: Timer?
    private var progressTimer: Timer?
    private var isProgressLoading = false

    var totalJobs: Int { running.count + pending.count }

    init() {
        #if DOCUMENTATION_SCREENSHOT
        endpoint = "http://127.0.0.1:8188"
        let graph: [String: Any] = ["12": ["_meta": ["title": "KSampler"], "class_type": "KSampler"]]
        running = [QueueJob(id: "8f21a7c4-demo-running", title: "Neon city portrait", nodeCount: 24, queueNumber: 1, position: 1, prompt: graph, extraData: [:])]
        pending = [QueueJob(id: "b390e612-demo-waiting", title: "Product lighting study", nodeCount: 18, queueNumber: 2, position: 1, prompt: [:], extraData: [:])]
        isConnected = true
        progressBridgeStatus = .available
        queueProgress = QueueProgress(promptID: running[0].id, nodeID: "12", value: 21, maxValue: 30, percent: 70, state: "running")
        lastUpdated = Date(timeIntervalSince1970: 1790814600)
        completed = [CompletedJob(id: "demo-completed", title: "Sunrise establishing shot", finishedAt: Date(timeIntervalSince1970: 1790814180), filenames: ["sunrise_shot_00012.mp4"], queueNumber: 0, outputs: [MediaOutput(filename: "sunrise_shot_00012.mp4", subfolder: "", type: "output")])]
        profiles = [ServerProfile(name: "Local Mac", endpoint: endpoint)]
        observedStarts[running[0].id] = Date().addingTimeInterval(-124)
        #else
        endpoint = UserDefaults.standard.string(forKey: "comfyEndpoint") ?? "http://127.0.0.1:8188"
        if let data = UserDefaults.standard.data(forKey: "serverProfiles"), let saved = try? JSONDecoder().decode([ServerProfile].self, from: data) { profiles = saved }
        notificationMode = UserDefaults.standard.string(forKey: "notificationMode") ?? "off"
        notifyProblems = UserDefaults.standard.bool(forKey: "notifyProblems")
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshProgress() }
        }
        Task { await refresh() }
        #endif
    }

    var serverName: String { profiles.first { $0.endpoint == endpoint }?.name ?? (URLComponents(string: endpoint)?.host ?? endpoint) }
    var canChangeServer: Bool { movingJobID == nil && stoppingJobID == nil }

    func saveProfile(name: String, address: String) {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URLComponents(string: address), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil, url.user == nil, url.password == nil else {
            actionMessage = L10n.text("Enter a valid http:// or https:// address."); actionIsError = true; return
        }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = name.isEmpty ? (url.host ?? address) : name
        if let index = profiles.firstIndex(where: { $0.endpoint == address }) { profiles[index].name = label }
        else { profiles.append(ServerProfile(name: label, endpoint: address)) }
        persistProfiles()
    }
    func deleteProfile(_ id: UUID) { profiles.removeAll { $0.id == id }; persistProfiles() }
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
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if endpoint != cleaned {
            connectionGeneration = UUID()
            completed = []; failures = []; running = []; pending = []; observedStarts = [:]
            notificationTracker = NotificationTracker()
            isConnected = false
            lastHistoryPoll = nil
            historyUnavailable = false
        }
        endpoint = cleaned
        UserDefaults.standard.set(cleaned, forKey: "comfyEndpoint")
        await refresh(forceHistory: true)
    }

    func refresh(forceHistory: Bool = false) async {
        guard !isLoading, movingJobID == nil, stoppingJobID == nil else { return }
        isLoading = true
        let generation = connectionGeneration
        defer {
            isLoading = false
            if generation != connectionGeneration { Task { await refresh(forceHistory: true) } }
        }

        do {
            let snapshot = try await fetchQueue()
            guard generation == connectionGeneration else { return }
            apply(snapshot)
            isConnected = true
            errorMessage = nil
            lastUpdated = Date()
            await refreshProgress(forceBridgeCheck: true)
            guard generation == connectionGeneration else { return }
            await refreshHistory(force: forceHistory)
        } catch {
            guard generation == connectionGeneration else { return }
            setDisconnected(error.localizedDescription)
        }
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
            guard generation == connectionGeneration else { return }
            progressBridgeStatus = .available
            queueProgress = snapshot.promptID == job.id ? snapshot : nil
        } catch QueueError.serverStatus(let status, _) where status == 404 {
            guard generation == connectionGeneration else { return }
            progressBridgeStatus = .missing
            queueProgress = nil
        } catch {
            guard generation == connectionGeneration else { return }
            progressBridgeStatus = .error
            queueProgress = nil
        }
    }

    func moveToFront(_ requestedJob: QueueJob) async {
        guard isConnected, movingJobID == nil, stoppingJobID == nil, !isLoading else { return }
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
        guard isConnected, movingJobID == nil, stoppingJobID == nil, !isLoading else { return }
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
                errorMessage = nil
                lastUpdated = Date()
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
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
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
              components.host != nil else {
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
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
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

    private func setDisconnected(_ message: String) {
        if isConnected && notifyProblems {
            NotificationService.shared.send(id: UUID().uuidString, title: L10n.text("Server disconnected"), body: serverName)
        }
        isConnected = false
        historyUnavailable = true
        running = []
        pending = []
        queueProgress = nil
        errorMessage = message
    }

    private static func parseJobs(_ value: Any?) -> [QueueJob] {
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

    private static func jobTitle(prompt: [String: Any], extra: [String: Any]) -> String {
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
            let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
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
            withExtendedLifetime((status, panel)) { app.run() }
            return
        }
        let queue = QueueViewModel()
        let settings = CommandLine.arguments.contains("--settings")
        let width: CGFloat = settings ? 360 : 360
        let height: CGFloat = settings ? 480 : 600
        let root = settings ? AnyView(QueuePopover(queue: queue).settingsContent.frame(width: 360, height: 480, alignment: .top).background(.regularMaterial)) : AnyView(QueuePopover(queue: queue))
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
struct ComfyQueueBarApp: App {
    @StateObject private var queue = QueueViewModel()
    private let updater = AppUpdater.shared

    var body: some Scene {
        MenuBarExtra {
            QueuePopover(queue: queue)
                .frame(width: 360, height: 600)
        } label: {
            HStack(spacing: 5) {
                Image(nsImage: QueueBrand.menuBarIcon)
                Text(L10n.text("%@", String(queue.totalJobs)))
                    .monospacedDigit()
            }
            .foregroundStyle(queue.isConnected ? Color.accentColor : Color.secondary)
            .accessibilityLabel(L10n.text("ComfyUI queue: %@ jobs", String(queue.totalJobs)))
        }
        .menuBarExtraStyle(.window)
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
                        .fill(queue.isConnected ? Color.green : Color.orange)
                        .frame(width: 5, height: 5)
                    Menu {
                        ForEach(queue.profiles) { profile in
                            Button(profile.name) { panel.urlInput = profile.endpoint; panel.profileName = profile.name; Task { await queue.connect(to: profile.endpoint) } }
                        }
                    } label: {
                        Text(queue.isConnected ? queue.serverName : L10n.text("Disconnected"))
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(queue.profiles.isEmpty || !queue.canChangeServer)
                }
                .accessibilityLabel(queue.isConnected ? L10n.text("Connected") : L10n.text("Disconnected"))
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
            Text(L10n.text("Servers")).font(.subheadline).fontWeight(.medium)
            ForEach(queue.profiles) { profile in
                HStack {
                    Button(profile.name) {
                        panel.urlInput = profile.endpoint
                        panel.profileName = profile.name
                        Task { await queue.connect(to: profile.endpoint) }
                    }.buttonStyle(.link).disabled(!queue.canChangeServer)
                    if profile.endpoint == queue.endpoint { Image(systemName: "checkmark").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button { queue.deleteProfile(profile.id) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.plain).help(L10n.text("Remove server"))
                }
            }
            HStack {
                TextField(L10n.text("Server name"), text: $panel.profileName).textFieldStyle(.roundedBorder)
                Button(L10n.text("Save address")) { queue.saveProfile(name: panel.profileName, address: panel.urlInput); panel.profileName = "" }.controlSize(.small)
            }
        }.font(.system(size: 11))
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
                    .onSubmit { Task { await queue.connect(to: panel.urlInput) } }
                Button(L10n.text("Connect")) {
                    Task { await queue.connect(to: panel.urlInput) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!queue.canChangeServer)
            }
        }
    }

    private var runningSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionHeading(L10n.text("Running"), count: queue.running.count, symbol: "waveform.path")
            if !queue.isConnected {
                connectionError
            } else if queue.running.isEmpty {
                emptyState(L10n.text("No jobs are running"), symbol: "checkmark.circle")
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

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionHeading(L10n.text("Waiting queue"), count: queue.pending.count, symbol: "list.number")
            if queue.isConnected && queue.pending.isEmpty {
                emptyState(L10n.text("No waiting jobs"), symbol: "tray")
            } else if queue.isConnected {
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
            Text(L10n.text("Unable to read the queue"))
                .font(.system(size: 12, weight: .semibold))
            Text(queue.errorMessage ?? L10n.text("Check that ComfyUI is running and the address is correct."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
    }

    var settingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("Settings")).font(.headline)
            connectionSettings
            Divider()
            serverSettings
            Divider()
            notificationSettings
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

    private func sectionHeading(_ title: String, count: Int, symbol: String) -> some View {
        HStack(spacing: 7) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            Spacer()
            Text(L10n.text("%@", String(count)))
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
