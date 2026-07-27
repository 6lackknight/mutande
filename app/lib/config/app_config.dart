/// Runtime config for the Mutande macOS shell (v1 plumbing).
///
/// Hub URL is display-only here; auth and E2E stay in `mutande-core`.
class AppConfig {
  const AppConfig({required this.hubUrl});

  /// Default local hub from [hub/README.md].
  static const defaultHubUrl = 'http://localhost:8000';

  /// Override with `--dart-define=MUTANDE_HUB_URL=https://...` at build/run time.
  static AppConfig fromEnvironment() {
    const hubUrl = String.fromEnvironment(
      'MUTANDE_HUB_URL',
      defaultValue: defaultHubUrl,
    );
    return AppConfig(hubUrl: hubUrl);
  }

  final String hubUrl;
}
