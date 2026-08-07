/// Runtime config for the Mutande macOS shell (v1 plumbing).
///
/// Hub URL / Auth0 client id are passed into daemon RPCs; tokens stay in core.
class AppConfig {
  const AppConfig({
    required this.hubUrl,
    this.auth0Domain = defaultAuth0Domain,
    this.auth0NativeClientId = defaultAuth0NativeClientId,
    this.auth0Audience = defaultAuth0Audience,
    this.webAppUrl = defaultWebAppUrl,
    this.sentryDsn = defaultSentryDsn,
  });

  /// Deployed hub (Deno Deploy).
  static const defaultHubUrl = 'https://mutande.6lackknight.deno.net';

  /// Prod web (signup, invites). Override with `--dart-define=MUTANDE_WEB_APP_URL=…`.
  static const defaultWebAppUrl = 'https://mutande.online';

  /// Auth0 tenant host (no scheme). Matches core `auth0_defaults`.
  static const defaultAuth0Domain = 'auth.mutande.online';

  /// Auth0 Native Application client id (public).
  static const defaultAuth0NativeClientId =
      '2cbPq8c2JelRxBRkvKlSHTmrM91ItUUm';

  /// Auth0 API identifier (must match hub).
  static const defaultAuth0Audience = 'https://hub.mutande.app';

  /// GlitchTip (Sentry-compatible) DSN. Empty disables reporting.
  /// Override with `--dart-define=SENTRY_DSN=` or a different DSN.
  static const defaultSentryDsn =
      'https://2c06fb0fcf2c4390ae727b548aeba5cd@app.glitchtip.com/26609';

  /// pubspec `version:` before `+`. Override with `--dart-define=APP_VERSION=`.
  static const appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.0.0',
  );

  /// Override with `--dart-define=MUTANDE_HUB_URL=https://...` at build/run time.
  /// Auth0 `--dart-define`s override the hardcoded defaults when non-empty.
  static AppConfig fromEnvironment() {
    const hubUrl = String.fromEnvironment(
      'MUTANDE_HUB_URL',
      defaultValue: defaultHubUrl,
    );
    const auth0Domain = String.fromEnvironment(
      'AUTH0_DOMAIN',
      defaultValue: defaultAuth0Domain,
    );
    const auth0NativeClientId = String.fromEnvironment(
      'AUTH0_NATIVE_CLIENT_ID',
      defaultValue: defaultAuth0NativeClientId,
    );
    const auth0Audience = String.fromEnvironment(
      'AUTH0_AUDIENCE',
      defaultValue: defaultAuth0Audience,
    );
    const webAppUrl = String.fromEnvironment(
      'MUTANDE_WEB_APP_URL',
      defaultValue: defaultWebAppUrl,
    );
    const sentryDsn = String.fromEnvironment(
      'SENTRY_DSN',
      defaultValue: defaultSentryDsn,
    );
    return AppConfig(
      hubUrl: hubUrl,
      auth0Domain: auth0Domain,
      auth0NativeClientId: auth0NativeClientId,
      auth0Audience: auth0Audience,
      webAppUrl: webAppUrl,
      sentryDsn: sentryDsn,
    );
  }

  final String hubUrl;
  final String? auth0Domain;
  final String? auth0NativeClientId;
  final String? auth0Audience;
  final String webAppUrl;
  final String sentryDsn;
}
