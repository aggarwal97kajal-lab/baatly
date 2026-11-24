/// Backend base URL (Cloudflare Worker). Can be overridden at build time:
///   flutter build apk --dart-define=API_BASE=https://...
/// When empty, the app falls back to the offline demo login.
const String kApiBase = String.fromEnvironment('API_BASE', defaultValue: kDefaultApiBase);

/// Filled in after the first server deploy.
const String kDefaultApiBase = 'https://baatly-api.pitaragames.workers.dev';

bool get kHasBackend => kApiBase.isNotEmpty;
