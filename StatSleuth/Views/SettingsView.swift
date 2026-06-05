import SwiftUI

struct SettingsView: View {

    @Environment(UserProgressService.self) private var progressService
    @Environment(\.dismiss) private var dismiss

    @State private var notificationsEnabled = false
    @State private var notificationHour = 9

    var body: some View {
        NavigationStack {
            List {
                statsSection
                notificationsSection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private var statsSection: some View {
        Section("Your Stats") {
            LabeledContent("Current Streak", value: "\(progressService.progress.currentStreak) days")
            LabeledContent("Longest Streak", value: "\(progressService.progress.longestStreak) days")
            LabeledContent("Games Played", value: "\(progressService.progress.totalGamesPlayed)")
            LabeledContent("Games Won", value: "\(progressService.progress.totalGamesWon)")
            LabeledContent("Win Rate", value: "\(Int(progressService.progress.winRate * 100))%")
        }
    }

    private var notificationsSection: some View {
        Section("Daily Reminder") {
            Toggle("Remind me to play", isOn: $notificationsEnabled)
                .onChange(of: notificationsEnabled) { _, enabled in
                    if enabled { requestNotificationPermission() }
                }

            if notificationsEnabled {
                Picker("Reminder time", selection: $notificationHour) {
                    ForEach(6..<23, id: \.self) { hour in
                        Text(formatHour(hour)).tag(hour)
                    }
                }
                .onChange(of: notificationHour) { _, _ in
                    scheduleNotification()
                }
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: appVersion)
            Link("Rate StatSleuth", destination: URL(string: "https://apps.apple.com")!)
            Link("Privacy Policy", destination: URL(string: "https://statsleuth.app/privacy")!)
            Link("Contact Us", destination: URL(string: "mailto:hello@statsleuth.app")!)
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private func formatHour(_ hour: Int) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = 0
        guard let date = Calendar.current.date(from: comps) else { return "\(hour):00" }
        return fmt.string(from: date)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                notificationsEnabled = granted
                if granted { scheduleNotification() }
            }
        }
    }

    private func scheduleNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["daily-reminder"])

        let content = UNMutableNotificationContent()
        content.title = "⚾ StatSleuth"
        content.body = streakBody
        content.sound = .default
        content.badge = 1

        var dateComponents = DateComponents()
        dateComponents.hour = notificationHour
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "daily-reminder", content: content, trigger: trigger)
        center.add(request)
    }

    private var streakBody: String {
        let streak = progressService.progress.currentStreak
        if streak == 0 { return "Start your streak today! Guess the mystery player." }
        if streak < 7  { return "You're on a \(streak)-day streak! Keep it going." }
        return "🔥 \(streak)-day streak! Don't break it now."
    }
}


