# Sidify media integration

The Flutter catalog uses Sidify-V2 `/api/media/browse`, `/search`, `/title/{kind}/{slug}` and POST `/resolve`. Default origin: `https://sidify.vercel.app`. To use your own deployment of https://github.com/dastaanenajdik/Sidify-V2, build with `--dart-define=SIDIFY_MEDIA_API=https://your-deployment`.

Deploy Sidify-V2 according to its README (including its provider environment configuration). This change does not deploy or copy its backend into the Go listen-together service. No external download service is introduced: resolved media bytes download on the phone. External/captcha fallback pages are not treated as files. Existing Eon title bookmarks and Eon/Dotflix download links retain their old resolver.

Quality sheets offer Play beta (existing media_kit native player), Play in VLC (Android VLC must be installed), and Download. Archive packs remain download-only. Beta re-enables automatic audio selection on source changes; language/subtitle controls remain in the player. Device testing is still required for codecs, audio routing, VLC intents, and background transfers.

Validation: `flutter analyze --no-fatal-infos`, `flutter test`, release Android build via CI. Live provider reachability is not covered by mocked API tests.
