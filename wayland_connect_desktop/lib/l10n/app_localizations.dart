import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_id.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('id'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Wayland Connect'**
  String get appName;

  /// No description provided for @dashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get dashboard;

  /// No description provided for @systemControlCenter.
  ///
  /// In en, this message translates to:
  /// **'System Control Center'**
  String get systemControlCenter;

  /// No description provided for @pairedDevices.
  ///
  /// In en, this message translates to:
  /// **'Paired Devices'**
  String get pairedDevices;

  /// No description provided for @blockedDevices.
  ///
  /// In en, this message translates to:
  /// **'Blocked Devices'**
  String get blockedDevices;

  /// No description provided for @securityTrust.
  ///
  /// In en, this message translates to:
  /// **'Security & Trust'**
  String get securityTrust;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @restoreWindow.
  ///
  /// In en, this message translates to:
  /// **'Restore Window'**
  String get restoreWindow;

  /// No description provided for @minimizeWindow.
  ///
  /// In en, this message translates to:
  /// **'Minimize Window'**
  String get minimizeWindow;

  /// No description provided for @exit.
  ///
  /// In en, this message translates to:
  /// **'Exit'**
  String get exit;

  /// No description provided for @mirroringRequest.
  ///
  /// In en, this message translates to:
  /// **'Mirroring Request'**
  String get mirroringRequest;

  /// No description provided for @wantsToShareScreen.
  ///
  /// In en, this message translates to:
  /// **'wants to share their screen here. Allow?'**
  String get wantsToShareScreen;

  /// No description provided for @deny.
  ///
  /// In en, this message translates to:
  /// **'Deny'**
  String get deny;

  /// No description provided for @allow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get allow;

  /// No description provided for @startOnBoot.
  ///
  /// In en, this message translates to:
  /// **'Start on Boot'**
  String get startOnBoot;

  /// No description provided for @minimizeToTray.
  ///
  /// In en, this message translates to:
  /// **'Minimize to Tray'**
  String get minimizeToTray;

  /// No description provided for @darkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark Mode'**
  String get darkMode;

  /// No description provided for @requireApproval.
  ///
  /// In en, this message translates to:
  /// **'Require Approval'**
  String get requireApproval;

  /// No description provided for @encryptionEnabled.
  ///
  /// In en, this message translates to:
  /// **'Encryption Enabled'**
  String get encryptionEnabled;

  /// No description provided for @selectedMonitor.
  ///
  /// In en, this message translates to:
  /// **'Selected Monitor'**
  String get selectedMonitor;

  /// No description provided for @servicePort.
  ///
  /// In en, this message translates to:
  /// **'Service Port'**
  String get servicePort;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// No description provided for @success.
  ///
  /// In en, this message translates to:
  /// **'Success!'**
  String get success;

  /// No description provided for @failed.
  ///
  /// In en, this message translates to:
  /// **'Failed!'**
  String get failed;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @minimize.
  ///
  /// In en, this message translates to:
  /// **'Minimize'**
  String get minimize;

  /// No description provided for @pausing.
  ///
  /// In en, this message translates to:
  /// **'Pausing...'**
  String get pausing;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @inactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get inactive;

  /// No description provided for @connected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

  /// No description provided for @disconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get disconnected;

  /// No description provided for @requireApprovalNew.
  ///
  /// In en, this message translates to:
  /// **'Require Approval for New Devices'**
  String get requireApprovalNew;

  /// No description provided for @alwaysAskPairing.
  ///
  /// In en, this message translates to:
  /// **'Always ask before pairing a new device.'**
  String get alwaysAskPairing;

  /// No description provided for @accessControl.
  ///
  /// In en, this message translates to:
  /// **'Access Control'**
  String get accessControl;

  /// No description provided for @revokeAllAccess.
  ///
  /// In en, this message translates to:
  /// **'Revoke All Access'**
  String get revokeAllAccess;

  /// No description provided for @revokeAllDetails.
  ///
  /// In en, this message translates to:
  /// **'Disconnect all devices and clear trust database.'**
  String get revokeAllDetails;

  /// No description provided for @revokeAllBtn.
  ///
  /// In en, this message translates to:
  /// **'Revoke All'**
  String get revokeAllBtn;

  /// No description provided for @startOnBootDetails.
  ///
  /// In en, this message translates to:
  /// **'Automatically start server when you login.'**
  String get startOnBootDetails;

  /// No description provided for @minimizeToTrayDetails.
  ///
  /// In en, this message translates to:
  /// **'Keep running in background when closed.'**
  String get minimizeToTrayDetails;

  /// No description provided for @darkModeDetails.
  ///
  /// In en, this message translates to:
  /// **'Use dark theme for dashboard.'**
  String get darkModeDetails;

  /// No description provided for @enableZoom.
  ///
  /// In en, this message translates to:
  /// **'Enable Zoom Feature'**
  String get enableZoom;

  /// No description provided for @enableZoomDetails.
  ///
  /// In en, this message translates to:
  /// **'Enable screen magnifier (Requires screen capture permission).'**
  String get enableZoomDetails;

  /// No description provided for @pointerOverlay.
  ///
  /// In en, this message translates to:
  /// **'Pointer Overlay'**
  String get pointerOverlay;

  /// No description provided for @selectMonitorDetails.
  ///
  /// In en, this message translates to:
  /// **'Select which monitor the laser pointer should appear on.'**
  String get selectMonitorDetails;

  /// No description provided for @detectingMonitors.
  ///
  /// In en, this message translates to:
  /// **'Detecting Monitors...'**
  String get detectingMonitors;

  /// No description provided for @serverConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Server Configuration'**
  String get serverConfiguration;

  /// No description provided for @portEmptyError.
  ///
  /// In en, this message translates to:
  /// **'Port cannot be empty'**
  String get portEmptyError;

  /// No description provided for @restartServiceApply.
  ///
  /// In en, this message translates to:
  /// **'Restart Service & Apply Port'**
  String get restartServiceApply;

  /// No description provided for @systemUpdate.
  ///
  /// In en, this message translates to:
  /// **'System Update'**
  String get systemUpdate;

  /// No description provided for @updateDetails.
  ///
  /// In en, this message translates to:
  /// **'Checking for updates ensures you have the latest features and security fixes.'**
  String get updateDetails;

  /// No description provided for @checkForUpdates.
  ///
  /// In en, this message translates to:
  /// **'Check for Updates'**
  String get checkForUpdates;

  /// No description provided for @githubRepo.
  ///
  /// In en, this message translates to:
  /// **'Github Repo'**
  String get githubRepo;

  /// No description provided for @serviceStopped.
  ///
  /// In en, this message translates to:
  /// **'Service Stopped'**
  String get serviceStopped;

  /// No description provided for @serviceActive.
  ///
  /// In en, this message translates to:
  /// **'Service Active'**
  String get serviceActive;

  /// No description provided for @searchingBackend.
  ///
  /// In en, this message translates to:
  /// **'Searching Backend...'**
  String get searchingBackend;

  /// No description provided for @screenShareRequest.
  ///
  /// In en, this message translates to:
  /// **'Screen Share Request'**
  String get screenShareRequest;

  /// No description provided for @secureLinkPending.
  ///
  /// In en, this message translates to:
  /// **'Secure Link Pending'**
  String get secureLinkPending;

  /// No description provided for @decline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get decline;

  /// No description provided for @approve.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get approve;

  /// No description provided for @reject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get reject;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @block.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get block;

  /// No description provided for @rePair.
  ///
  /// In en, this message translates to:
  /// **'Re-pair'**
  String get rePair;

  /// No description provided for @unblock.
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get unblock;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @serverIp.
  ///
  /// In en, this message translates to:
  /// **'Server IP'**
  String get serverIp;

  /// No description provided for @port.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get port;

  /// No description provided for @paired.
  ///
  /// In en, this message translates to:
  /// **'Paired'**
  String get paired;

  /// No description provided for @request.
  ///
  /// In en, this message translates to:
  /// **'Request'**
  String get request;

  /// No description provided for @recentActivity.
  ///
  /// In en, this message translates to:
  /// **'Recent Activity'**
  String get recentActivity;

  /// No description provided for @noPairedDevices.
  ///
  /// In en, this message translates to:
  /// **'No paired devices'**
  String get noPairedDevices;

  /// No description provided for @noBlockedDevices.
  ///
  /// In en, this message translates to:
  /// **'No blocked devices'**
  String get noBlockedDevices;

  /// No description provided for @noRecentConnections.
  ///
  /// In en, this message translates to:
  /// **'No Recent Connections'**
  String get noRecentConnections;

  /// No description provided for @connectAndroidToGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Connect your Android device to get started'**
  String get connectAndroidToGetStarted;

  /// No description provided for @revokedAccessFor.
  ///
  /// In en, this message translates to:
  /// **'Revoked access for'**
  String get revokedAccessFor;

  /// No description provided for @devices.
  ///
  /// In en, this message translates to:
  /// **'devices'**
  String get devices;

  /// No description provided for @manageDevicesAccess.
  ///
  /// In en, this message translates to:
  /// **'Manage all devices that have access to this PC.'**
  String get manageDevicesAccess;

  /// No description provided for @permanentlyBlocked.
  ///
  /// In en, this message translates to:
  /// **'Devices that are permanently blocked from connecting.'**
  String get permanentlyBlocked;

  /// No description provided for @monitor.
  ///
  /// In en, this message translates to:
  /// **'Monitor'**
  String get monitor;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @selectLanguage.
  ///
  /// In en, this message translates to:
  /// **'Select Language'**
  String get selectLanguage;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @indonesian.
  ///
  /// In en, this message translates to:
  /// **'Indonesian'**
  String get indonesian;

  /// No description provided for @autoConnect.
  ///
  /// In en, this message translates to:
  /// **'Auto Connect'**
  String get autoConnect;

  /// No description provided for @autoConnectDetails.
  ///
  /// In en, this message translates to:
  /// **'Automatically accept connections from trusted devices.'**
  String get autoConnectDetails;

  /// No description provided for @allowAutoReconnect.
  ///
  /// In en, this message translates to:
  /// **'Allow Auto-Reconnect'**
  String get allowAutoReconnect;

  /// No description provided for @autoReconnectWarning.
  ///
  /// In en, this message translates to:
  /// **'This device can connect silently without approval.'**
  String get autoReconnectWarning;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'id'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'id':
      return AppLocalizationsId();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
