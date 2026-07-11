enum RecorderInstallCopy {
    static let confirmationTitle = "Install MacAlarm Recorder?"

    static let confirmationMessage =
        """
        MacAlarm can keep recording important local events after you close the window by adding a visible macOS background item named MacAlarm.

        What happens:
        - MacAlarm records to your local ledger in your user account.
        - macOS may ask you to approve MacAlarm in Background Items.
        - You can stop or uninstall the recorder later from the Recorder menu.

        No admin password or Keychain access is required.
        """

    static let confirmationButtonTitle = "Install & Start"
}
