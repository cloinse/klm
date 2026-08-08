import 'dart:convert';
import 'dart:io';

class FeedbackSubmission {
  const FeedbackSubmission({
    required this.type,
    required this.message,
    this.email,
    this.appVersion,
    this.platform,
    this.locale,
  });

  final String type;
  final String message;
  final String? email;
  final String? appVersion;
  final String? platform;
  final String? locale;
}

abstract interface class FeedbackService {
  Future<void> submit(FeedbackSubmission submission);
}

class FeedbackSubmissionException implements Exception {
  const FeedbackSubmissionException(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'Feedback submission failed ($statusCode).';
}

class HttpFeedbackService implements FeedbackService {
  const HttpFeedbackService({this.endpoint = _defaultEndpoint});

  static const _defaultEndpoint =
      'https://klm-feedback-api.ciscode.workers.dev/feedback';

  final String endpoint;

  @override
  Future<void> submit(FeedbackSubmission submission) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);

    try {
      final request = await client.postUrl(Uri.parse(endpoint));
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'type': submission.type,
          'message': submission.message,
          'email': submission.email,
          'app_version': submission.appVersion,
          'platform': submission.platform,
          'locale': submission.locale,
        }),
      );

      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      await response.drain<void>();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw FeedbackSubmissionException(response.statusCode);
      }
    } finally {
      client.close(force: true);
    }
  }
}
