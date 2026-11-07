import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a link from text the app shows (a pin) in another app: the browser
/// or the mail app. Only web and mail links are opened.
abstract class LinkOpener {
  /// Opens [uri]; false when it is not a web or mail link or no app took it.
  Future<bool> open(Uri uri);
}

/// Whether [uri] is a link the app hands on: http, https or mailto.
bool isOpenableLink(Uri uri) =>
    const {'http', 'https', 'mailto'}.contains(uri.scheme.toLowerCase());

class UrlLauncherLinkOpener implements LinkOpener {
  const UrlLauncherLinkOpener();

  @override
  Future<bool> open(Uri uri) async {
    if (!isOpenableLink(uri)) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on PlatformException {
      return false;
    }
  }
}

final linkOpenerProvider =
    Provider<LinkOpener>((ref) => const UrlLauncherLinkOpener());
