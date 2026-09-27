bool isUnavailableTrack(Object error) => RegExp(
  r'VideoUnplayableException|VideoRequiresPurchaseException|not available|unavailable|region|country|private video|removed|purchase',
  caseSensitive: false,
).hasMatch(error.toString());
String trackFailureMessage(Object error) => isUnavailableTrack(error)
    ? "This track isn't available in your region"
    : 'Could not load this track. Check your connection and try again.';
