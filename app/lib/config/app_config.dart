/// Runtime config for the Mutande macOS shell (v1 plumbing).
///
/// Hub URL / Auth0 client id are passed into daemon RPCs; tokens stay in core.
class AppConfig {
  const AppConfig({
    required this.hubUrl,
    this.auth0Domain,
    this.auth0NativeClientId,
    this.auth0Audience,
  });

  /// Deployed hub (Deno Deploy).
  static const defaultHubUrl = 'https://mutande.6lackknight.deno.net';

  /// Override with `--dart-define=MUTANDE_HUB_URL=https://...` at build/run time.
  static AppConfig fromEnvironment() {
    const hubUrl = String.fromEnvironment(
      'MUTANDE_HUB_URL',
      defaultValue: defaultHubUrl,
    );
    const auth0Domain = String.fromEnvironment('AUTH0_DOMAIN');
    const auth0NativeClientId = String.fromEnvironment('AUTH0_NATIVE_CLIENT_ID');
    const auth0Audience = String.fromEnvironment(
      'AUTH0_AUDIENCE',
      defaultValue: 'https://hub.mutande.app',
    );
    return AppConfig(
      hubUrl: hubUrl,
      auth0Domain: auth0Domain.isEmpty ? null : auth0Domain,
      auth0NativeClientId:
          auth0NativeClientId.isEmpty ? null : auth0NativeClientId,
      auth0Audience: auth0Audience.isEmpty ? null : auth0Audience,
    );
  }

  final String hubUrl;
  final String? auth0Domain;
  final String? auth0NativeClientId;
  final String? auth0Audience;
}
