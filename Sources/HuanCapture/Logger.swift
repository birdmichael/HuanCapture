//
//  Logger.swift
//  HuanCapture
//
//  Created by BM on 5/6/25.
//

import AlertKit
import Foundation
import OSLog
import UIKit

private enum LoggerConfig {
    static let logFileName = "logs.txt"
    
    enum Alert {
        enum Title {
            static let success = "ALERT_SUCCESS"
            static let error = "ALERT_ERROR"
            static let trace = "ALERT_TRACE"
            static let critical = "ALERT_CRITICAL"
        }
        
        enum Action {
            static let ok = "OK"
        }
    }
}

public enum LogType {
    /// Default
    case notice
    /// Call this function to capture information that may be helpful, but isn't essential, for troubleshooting.
    case info
    /// Debug-level messages to use in a development environment while actively debugging.
    case debug
    /// Equivalent of the debug method.
    case trace
    /// Warning-level messages for reporting unexpected non-fatal failures.
    case warning
    /// Error-level messages for reporting critical errors and failures.
    case error
    /// Fault-level messages for capturing system-level or multi-process errors only.
    case fault
    /// Functional equivalent of the fault method.
    case critical
    
    case success
}

final class Debug {
    static let shared = Debug()
    private let subsystem = Bundle.main.bundleIdentifier!
    
    var logFilePath: URL {
        return getDocumentsDirectory().appendingPathComponent(LoggerConfig.logFileName)
    }
    
    private func appendLogToFile(_ message: String) {
        do {
            if FileManager.default.fileExists(atPath: logFilePath.path) {
                let fileHandle = try FileHandle(forUpdating: logFilePath)
                fileHandle.seekToEndOfFile()
                if let data = message.data(using: .utf8) {
                    fileHandle.write(data)
                }
                fileHandle.closeFile()
            }
        } catch {
            Debug.shared.log(message: "Error writing to logs.txt: \(error)")
        }
    }
    
    func log(message: String, type: LogType? = nil, function: String = #function, file: String = #file, line: Int = #line) {
        lazy var logger = Logger(subsystem: subsystem, category: file + "->" + function)

        // Prepare the emoji based on the log type
        var emoji: String
        switch type {
        case .success:
            emoji = "✅"
            logger.info("\(message)")
            showSuccessAlert(with: LoggerConfig.Alert.Title.success, subtitle: message)
        case .info:
            emoji = "ℹ️"
            logger.info("\(message)")
        case .debug:
            emoji = "🐛"
            logger.debug("\(message)")
        case .trace:
            emoji = "🔍"
            logger.trace("\(message)")
            showErrorUIAlert(with: LoggerConfig.Alert.Title.trace, subtitle: message)
        case .warning:
            emoji = "⚠️"
            logger.warning("\(message)")
            showErrorAlert(with: LoggerConfig.Alert.Title.error, subtitle: message)
        case .error:
            emoji = "❌"
            logger.error("\(message)")
            showErrorAlert(with: LoggerConfig.Alert.Title.error, subtitle: message)
        case .critical:
            emoji = "🔥"
            logger.critical("\(message)")
            showErrorUIAlert(with: LoggerConfig.Alert.Title.critical, subtitle: message)
        default:
            emoji = "📝"
            logger.log("\(message)")
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"
        let timeString = dateFormatter.string(from: Date())

        let logMessage = "[\(timeString)] \(emoji) \(message)\n"
        appendLogToFile(logMessage)
    }

    func showSuccessAlert(with title: String, subtitle: String) {
        DispatchQueue.main.async {
            let alertView = AlertAppleMusic17View(title: LoggerConfig.Alert.Title.success, subtitle: subtitle, icon: .done)
            let keyWindow = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.last
            if let viewController = keyWindow?.rootViewController {
                alertView.present(on: viewController.view)
            }
            #if os(iOS)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            #endif
        }
    }
    
    func showErrorAlert(with title: String, subtitle: String) {
        DispatchQueue.main.async {
            let alertView = AlertAppleMusic17View(title: LoggerConfig.Alert.Title.error, subtitle: subtitle, icon: .error)
            let keyWindow = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.last
            if let viewController = keyWindow?.rootViewController {
                alertView.present(on: viewController.view)
            }
            #if os(iOS)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
            #endif
        }
    }
    
    func showErrorUIAlert(with title: String, subtitle: String) {
        DispatchQueue.main.async {
            let keyWindow = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.last
            if let rootViewController = keyWindow?.rootViewController {
                let alert = UIAlertController.error(title: LoggerConfig.Alert.Title.error, message: subtitle, actions: [])
                rootViewController.present(alert, animated: true)
            }
            
            #if os(iOS)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
            #endif
        }
    }
}

extension UIAlertController {
    static func error(title: String, message: String, actions: [UIAlertAction]) -> UIAlertController {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        alertController.addAction(UIAlertAction(title: LoggerConfig.Alert.Action.ok, style: .cancel) { _ in
            alertController.dismiss(animated: true)
        })

        for action in actions {
            alertController.addAction(action)
        }
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
        #endif
        return alertController
    }
    
    static func coolAlert(title: String, message: String, actions: [UIAlertAction]) -> UIAlertController {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)

        for action in actions {
            alertController.addAction(action)
        }
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
        #endif
        return alertController
    }
}

func getDocumentsDirectory() -> URL {
    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    let documentsDirectory = paths[0]
    return documentsDirectory
}

extension Debug {
    static func setupLogFile() {
        let logFilePath = Debug.shared.logFilePath
        if FileManager.default.fileExists(atPath: logFilePath.path) {
            do {
                try FileManager.default.removeItem(at: logFilePath)
            } catch {
                Debug.shared.log(message: "Error removing existing logs.txt: \(error)", type: .error)
            }
        }

        do {
            try "".write(to: logFilePath, atomically: true, encoding: .utf8)
        } catch {
            Debug.shared.log(message: "Error removing existing logs.txt: \(error)", type: .error)
        }
    }
}
LogsViewController.swift
import UIKit

// MARK: - View Configuration
private enum LogsViewSection: Int, CaseIterable {
    case error
    case actions
    
    var numberOfRows: Int {
        switch self {
        case .error: return 1
        case .actions: return 2
        }
    }
    
    enum Row {
        case error
        case share
        case copy
        
        var index: Int {
            switch self {
            case .error: return 0
            case .share: return 0
            case .copy: return 1
            }
        }
    }
}

private enum StringConfig {
    enum LogsView {
        static let sectionTitleError = "个严重错误。"
        static let sectionTitleShare = "分享日志"
        static let sectionTitleCopy = "复制日志"
        static let successDescription = "日志内容已复制到剪贴板。"
        static let errorDescription = "无法复制日志内容。"
    }
    
    enum Alert {
        static let copied = "已复制"
        static let error = "错误"
        static let ok = "好的"
    }
}

class LogsViewController: UIViewController {
    // MARK: - Properties
    var tableView: UITableView!
    private var logTextView: UITextView!
    private var logFileObserver: DispatchSourceFileSystemObject?
    private var currentFileSize: UInt64 = 0
    private var errCount = 0
    
    // MARK: - Lifecycle Methods
    override func viewDidLoad() {
        super.viewDidLoad()
        setupNavigation()
        setupViews()
        startObservingLogFile()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(false)
        parseLogFile()
        tableView.reloadSections(IndexSet([LogsViewSection.error.rawValue]), with: .automatic)
    }
    
    // MARK: - Setup Methods
    fileprivate func setupNavigation() {
        self.navigationItem.largeTitleDisplayMode = .never
    }
    
    fileprivate func setupViews() {
        view.backgroundColor = .systemBackground
        logTextView = UITextView()
        logTextView.isEditable = false
        logTextView.translatesAutoresizingMaskIntoConstraints = false
        logTextView.font = UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        logTextView.textContainerInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        view.addSubview(logTextView)
        
        self.tableView = UITableView(frame: .zero, style: .insetGrouped)
        self.tableView.translatesAutoresizingMaskIntoConstraints = false
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.backgroundColor = .systemBackground
        
        self.tableView.layer.cornerRadius = 12
        self.tableView.layer.cornerCurve = .continuous
        self.tableView.layer.masksToBounds = true
        
        self.view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            logTextView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            logTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            logTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            logTextView.heightAnchor.constraint(equalToConstant: 400),
            
            tableView.topAnchor.constraint(equalTo: logTextView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        loadInitialLogContents()
    }
    
    private func loadInitialLogContents() {
        let logFilePath = Debug.shared.logFilePath
        
        guard let fileHandle = try? FileHandle(forReadingFrom: logFilePath) else {
            logTextView.text = "Failed to open logs"
            return
        }
        
        let data = fileHandle.readDataToEndOfFile()
        logTextView.text = String(data: data, encoding: .utf8) ?? "Failed to load logs"
        currentFileSize = UInt64(data.count)
        
        fileHandle.closeFile()
    }
    
    private func startObservingLogFile() {
        let logFilePath = Debug.shared.logFilePath.path
        
        let fileDescriptor = open(logFilePath, O_EVTONLY)
        if fileDescriptor == -1 {
            print("Failed to open file for observation")
            return
        }
        
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fileDescriptor, eventMask: .write, queue: DispatchQueue.main)
        source.setEventHandler { [weak self] in
            self?.loadNewLogContents()
        }
        source.setCancelHandler {
            close(fileDescriptor)
        }
        source.resume()
        logFileObserver = source
    }
    
    private func loadNewLogContents() {
        let logFilePath = Debug.shared.logFilePath
        
        guard let fileHandle = try? FileHandle(forReadingFrom: logFilePath) else {
            logTextView.text.append("\nFailed to read logs")
            return
        }
        
        fileHandle.seek(toFileOffset: currentFileSize)
        
        let newData = fileHandle.readDataToEndOfFile()
        if let newContent = String(data: newData, encoding: .utf8) {
            logTextView.text.append(newContent)
            let range = NSMakeRange(logTextView.text.count - 1, 0)
            logTextView.scrollRangeToVisible(range)
            scrollToBottom()
        }
        
        currentFileSize += UInt64(newData.count)
        
        fileHandle.closeFile()
    }
    
    deinit {
        logFileObserver?.cancel()
    }
    
    private func scrollToBottom() {
        let bottomRange = NSMakeRange(logTextView.text.count - 1, 1)
        logTextView.scrollRangeToVisible(bottomRange)
    }
    
    private func parseLogFile() {
        let logFilePath = Debug.shared.logFilePath
        do {
            let logContents = try String(contentsOf: logFilePath)

            let logEntries = logContents.components(separatedBy: .newlines)

            for entry in logEntries {
                if entry.contains("🔍") {
                    errCount += 1
                } else if entry.contains("⚠️") {
                    errCount += 1
                } else if entry.contains("❌") {
                    errCount += 1
                } else if entry.contains("🔥") {
                    errCount += 1
                }
            }

        } catch {
            Debug.shared.log(message: "Error reading log file: \(error)")
        }
    }
    
    
}

extension LogsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        return LogsViewSection.allCases.count
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 0
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        let headerView = InsetGroupedSectionHeader(title: "")
        return headerView
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = LogsViewSection(rawValue: section) else { return 0 }
        return section.numberOfRows
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let reuseIdentifier = "Cell"
        let cell = UITableViewCell(style: .value1, reuseIdentifier: reuseIdentifier)
        cell.accessoryType = .none
        cell.selectionStyle = .none

        guard let section = LogsViewSection(rawValue: indexPath.section) else {
            return cell
        }

        switch section {
        case .error:
            if indexPath.row == LogsViewSection.Row.error.index {
                cell.textLabel?.text = "\(errCount)" + StringConfig.LogsView.sectionTitleError
                cell.textLabel?.textColor = .white
                cell.textLabel?.font = .boldSystemFont(ofSize: 14)
                cell.backgroundColor = .systemRed
            }
        case .actions:
            switch indexPath.row {
            case LogsViewSection.Row.share.index:
                cell.textLabel?.text = StringConfig.LogsView.sectionTitleShare
                cell.textLabel?.textColor = .tintColor
                cell.selectionStyle = .default
                cell.setAccessoryIcon(with: "square.and.arrow.up")
            case LogsViewSection.Row.copy.index:
                cell.textLabel?.text = StringConfig.LogsView.sectionTitleCopy
                cell.textLabel?.textColor = .tintColor
                cell.selectionStyle = .default
                cell.setAccessoryIcon(with: "arrow.up.right")
            default:
                break
            }
        }
        
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let section = LogsViewSection(rawValue: indexPath.section) else {
            return
        }

        switch section {
        case .actions:
            switch indexPath.row {
            case LogsViewSection.Row.share.index:
                let logFilePath = Debug.shared.logFilePath
                let activityVC = UIActivityViewController(activityItems: [logFilePath], applicationActivities: nil)
                
                if let sheet = activityVC.sheetPresentationController {
                    sheet.detents = [.medium()]
                    sheet.prefersGrabberVisible = true
                }
                
                present(activityVC, animated: true)
            case LogsViewSection.Row.copy.index:
                let logFilePath = Debug.shared.logFilePath
                
                do {
                    let logContents = try String(contentsOf: logFilePath, encoding: .utf8)
                    UIPasteboard.general.string = logContents
                    let alert = UIAlertController(
                        title: StringConfig.Alert.copied,
                        message: StringConfig.LogsView.successDescription,
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: StringConfig.Alert.ok, style: .default))
                    present(alert, animated: true)
                } catch {
                    let alert = UIAlertController(
                        title: StringConfig.Alert.error,
                        message: StringConfig.LogsView.errorDescription,
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: StringConfig.Alert.ok, style: .default))
                    present(alert, animated: true)
                }
            default:
                break
            }
        default:
            break
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

extension UITableViewCell {
    fileprivate func setAccessoryIcon(with symbolName: String, tintColor: UIColor = .tertiaryLabel, renderingMode: UIImage.RenderingMode = .alwaysOriginal) {
        if let image = UIImage(systemName: symbolName)?.withTintColor(tintColor, renderingMode: renderingMode) {
            let imageView = UIImageView(image: image)
            self.accessoryView = imageView
        } else {
            self.accessoryView = nil
        }
    }
}

private class InsetGroupedSectionHeader: UIView {
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 19, weight: .bold)
        label.textColor = UIColor.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let topAnchorConstant: CGFloat
    
    init(title: String, topAnchorConstant: CGFloat = 7) {
        self.topAnchorConstant = topAnchorConstant
        
        super.init(frame: .zero)
        setupUI()
        self.title = title
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    var title: String {
        get { return titleLabel.text ?? "" }
        set { titleLabel.text = newValue }
    }
    
    private func setupUI() {
        addSubview(titleLabel)
        
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: topAnchorConstant)
        ])
    }
}
