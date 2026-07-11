import AppKit

enum MacAlarmAlertPresenter {
    @MainActor
    static func confirm(
        title: String,
        message: String,
        confirmButtonTitle: String = "Continue",
        cancelButtonTitle: String = "Cancel"
    ) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirmButtonTitle)
        alert.addButton(withTitle: cancelButtonTitle)
        return alert.runModal() == .alertFirstButtonReturn
    }

    @MainActor
    static func showInfo(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    @MainActor
    static func showInfoWithAction(
        title: String,
        message: String,
        actionButtonTitle: String,
        cancelButtonTitle: String = "Later"
    ) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: actionButtonTitle)
        alert.addButton(withTitle: cancelButtonTitle)
        return alert.runModal() == .alertFirstButtonReturn
    }

    @MainActor
    static func showError(title: String, error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = title
        alert.runModal()
    }
}

extension MacAlarmApplicationDelegate {
    func confirm(
        title: String,
        message: String,
        confirmButtonTitle: String = "Continue",
        cancelButtonTitle: String = "Cancel"
    ) -> Bool {
        MacAlarmAlertPresenter.confirm(
            title: title,
            message: message,
            confirmButtonTitle: confirmButtonTitle,
            cancelButtonTitle: cancelButtonTitle
        )
    }

    func showInfo(title: String, message: String) {
        MacAlarmAlertPresenter.showInfo(title: title, message: message)
    }

    func showInfoWithAction(
        title: String,
        message: String,
        actionButtonTitle: String,
        cancelButtonTitle: String = "Later"
    ) -> Bool {
        MacAlarmAlertPresenter.showInfoWithAction(
            title: title,
            message: message,
            actionButtonTitle: actionButtonTitle,
            cancelButtonTitle: cancelButtonTitle
        )
    }

    func showError(title: String, error: Error) {
        MacAlarmAlertPresenter.showError(title: title, error: error)
    }
}
