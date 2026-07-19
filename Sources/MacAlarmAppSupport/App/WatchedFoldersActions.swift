import AppKit
import MacAlarmCore

extension MacAlarmApplicationDelegate {
    @objc func showWatchedFolders(_ sender: Any?) {
        let controller: WatchedFoldersWindowController
        if let existing = watchedFoldersWindowController {
            controller = existing
        } else {
            controller = WatchedFoldersWindowController(
                bookmarks: watchedFolders,
                onChange: { [weak self] in
                    self?.watchService.reload()
                }
            )
            watchedFoldersWindowController = controller
        }
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Management window for user-selected watched folders. Lists the current
/// folders, adds one via an open panel (security-scoped bookmark), and removes
/// the selection. Honest copy states the inherent sandbox property: watching is
/// active only while MacAlarm is running.
@MainActor
final class WatchedFoldersWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let bookmarks: WatchedFolderBookmarks
    private let onChange: () -> Void
    private let tableView = NSTableView()
    private var folders: [WatchedFolderBookmark] = []

    init(bookmarks: WatchedFolderBookmarks, onChange: @escaping () -> Void) {
        self.bookmarks = bookmarks
        self.onChange = onChange

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 340),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Watched Folders"
        super.init(window: window)

        buildContent()
        reloadFolders()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func buildContent() {
        guard let window else {
            return
        }
        let content = NSView(frame: window.contentLayoutRect)
        content.autoresizingMask = [.width, .height]

        let note = NSTextField(
            wrappingLabelWithString:
                "MacAlarm watches these folders while the app is running. Because macOS grants folder "
                + "access to this app only, the background recorder cannot watch them on its own — keep "
                + "MacAlarm open (or reopen it) to record changes.")
        note.translatesAutoresizingMaskIntoConstraints = false
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: 11)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        column.title = "Folder"
        column.width = 480
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 22
        scroll.documentView = tableView

        let addButton = NSButton(title: "Add Folder…", target: self, action: #selector(addFolder))
        addButton.translatesAutoresizingMaskIntoConstraints = false
        let removeButton = NSButton(title: "Remove", target: self, action: #selector(removeSelected))
        removeButton.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(note)
        content.addSubview(scroll)
        content.addSubview(addButton)
        content.addSubview(removeButton)

        NSLayoutConstraint.activate([
            note.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            note.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            note.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            scroll.topAnchor.constraint(equalTo: note.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scroll.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -12),

            addButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            addButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            removeButton.leadingAnchor.constraint(equalTo: addButton.trailingAnchor, constant: 8),
            removeButton.centerYAnchor.constraint(equalTo: addButton.centerYAnchor),
        ])

        window.contentView = content
    }

    private func reloadFolders() {
        folders = bookmarks.bookmarks()
        tableView.reloadData()
    }

    @objc private func addFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Folder to Watch"
        panel.prompt = "Watch"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            do {
                try self?.bookmarks.add(url: url)
                self?.reloadFolders()
                self?.onChange()
            } catch {
                self?.presentWatchError(error)
            }
        }

        if let window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    @objc private func removeSelected() {
        let row = tableView.selectedRow
        guard folders.indices.contains(row) else {
            return
        }
        bookmarks.remove(id: folders[row].id)
        reloadFolders()
        onChange()
    }

    private func presentWatchError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Could Not Watch Folder"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    // MARK: NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        folders.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("cell")
        let cell =
            (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField)
            ?? {
                let field = NSTextField()
                field.identifier = identifier
                field.isBordered = false
                field.isEditable = false
                field.drawsBackground = false
                field.lineBreakMode = .byTruncatingMiddle
                return field
            }()
        cell.stringValue = folders[row].displayPath
        return cell
    }
}
