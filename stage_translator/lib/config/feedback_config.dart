// lib/config/feedback_config.dart
//
// Where tester feedback goes: a Google Form. Every answer lands in the form's
// Responses tab (and a Google Sheet if you link one). No server or database.
// Set-up steps are in FEEDBACK_SETUP.md.
//
// Until formId is filled in, "Send" opens the phone's share sheet instead, so
// testers can still send their comment on Telegram or WhatsApp.

class FeedbackConfig {
  /// The long id in the form's link: https://docs.google.com/forms/d/e/<THIS>/viewform
  static const formId = '1FAIpQLSfcsTFNJ5AEVJ5vP-3XMQ1BgCed2kUWCcvQ_6c32XOTcKYr5g';

  /// The entry ids from the form's "Get pre-filled link" (entry.123456789).
  static const messageEntry = 'entry.340559771'; // Paragraph: "Your feedback"
  static const ratingEntry = 'entry.1959921931'; // Linear scale 1 to 5: "Rating" (optional)
  static const nameEntry = 'entry.1977723544'; // Short answer: "Name" (optional)
  static const detailsEntry = 'entry.659193179'; // Paragraph: "Details" (app version, phone, screen)

  static bool get isSet => formId.isNotEmpty && messageEntry.isNotEmpty;

  static String get submitUrl => 'https://docs.google.com/forms/d/e/$formId/formResponse';
}