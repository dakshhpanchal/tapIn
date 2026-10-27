import 'dart:io' show Platform;
import 'package:package_info_plus/package_info_plus.dart';

class AppConst {
  static const userAgentAppName = "tapIn";
  static const platformNameAndroid = "Android";
  static const platformNameIOS = "iOS";
  static const sourceCodeUrl = "https://github.com/dakshhpanchal/tapIn";

  static Future<String> getVersionNumber() async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.version;
  }

  static String getPlatformName() {
    if (Platform.isAndroid) {
      return platformNameAndroid;
    } else if (Platform.isIOS) {
      return platformNameIOS;
    } else {
      return "";
    }
  }

  static Future<String> getUserAgentString() async {
    final versionNumber = await getVersionNumber();
    final platformVersion = getPlatformName();
    // Open Food Facts asks for `AppName/Version (contact or URL)`.
    return '$userAgentAppName/$versionNumber ($platformVersion; $sourceCodeUrl)';
  }
}
