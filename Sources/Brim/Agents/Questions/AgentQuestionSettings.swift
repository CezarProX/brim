import Foundation

extension AppSettings {
  /// Off until the user switches it on in Settings > Agents; hooks installed earlier then do nothing.
  var agentQuestionsEnabled: Bool {
    get { defaults.object(forKey: "agents.questions.enabled") as? Bool ?? false }
    set { defaults.set(newValue, forKey: "agents.questions.enabled") }
  }
}
