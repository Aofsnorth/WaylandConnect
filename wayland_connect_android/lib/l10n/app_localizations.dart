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
    Locale('id')
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'WaylandConnect'**
  String get appName;

  /// No description provided for @touchpad.
  ///
  /// In en, this message translates to:
  /// **'Touchpad'**
  String get touchpad;

  /// No description provided for @keyboard.
  ///
  /// In en, this message translates to:
  /// **'Keyboard'**
  String get keyboard;

  /// No description provided for @mediaControl.
  ///
  /// In en, this message translates to:
  /// **'Media Control'**
  String get mediaControl;

  /// No description provided for @presentation.
  ///
  /// In en, this message translates to:
  /// **'Presentation'**
  String get presentation;

  /// No description provided for @screenShare.
  ///
  /// In en, this message translates to:
  /// **'Screen Share'**
  String get screenShare;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @connected.
  ///
  /// In en, this message translates to:
  /// **'CONNECTED'**
  String get connected;

  /// No description provided for @disconnected.
  ///
  /// In en, this message translates to:
  /// **'DISCONNECTED'**
  String get disconnected;

  /// No description provided for @disconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnect;

  /// No description provided for @resetConnection.
  ///
  /// In en, this message translates to:
  /// **'RESET CONNECTION'**
  String get resetConnection;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'CONNECT'**
  String get connect;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'CANCEL'**
  String get cancel;

  /// No description provided for @syncing.
  ///
  /// In en, this message translates to:
  /// **'SYNCING...'**
  String get syncing;

  /// No description provided for @waitingForApproval.
  ///
  /// In en, this message translates to:
  /// **'WAITING FOR APPROVAL'**
  String get waitingForApproval;

  /// No description provided for @checkPcNotifications.
  ///
  /// In en, this message translates to:
  /// **'CHECK PC NOTIFICATIONS TO APPROVE'**
  String get checkPcNotifications;

  /// No description provided for @accessBlocked.
  ///
  /// In en, this message translates to:
  /// **'ACCESS BLOCKED'**
  String get accessBlocked;

  /// No description provided for @accessDeclined.
  ///
  /// In en, this message translates to:
  /// **'ACCESS DECLINED'**
  String get accessDeclined;

  /// No description provided for @permissionsRevoked.
  ///
  /// In en, this message translates to:
  /// **'PERMISSIONS REVOKED BY HOST MACHINE'**
  String get permissionsRevoked;

  /// No description provided for @systemBackground.
  ///
  /// In en, this message translates to:
  /// **'System & Background'**
  String get systemBackground;

  /// No description provided for @securityAccess.
  ///
  /// In en, this message translates to:
  /// **'Security & Access'**
  String get securityAccess;

  /// No description provided for @startOnBoot.
  ///
  /// In en, this message translates to:
  /// **'Start on Boot'**
  String get startOnBoot;

  /// No description provided for @automateService.
  ///
  /// In en, this message translates to:
  /// **'Automate service initialization'**
  String get automateService;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @persistentLink.
  ///
  /// In en, this message translates to:
  /// **'Persistent link stability'**
  String get persistentLink;

  /// No description provided for @virtual.
  ///
  /// In en, this message translates to:
  /// **'VIRTUAL'**
  String get virtual;

  /// No description provided for @trackpad.
  ///
  /// In en, this message translates to:
  /// **'TRACKPAD'**
  String get trackpad;

  /// No description provided for @left.
  ///
  /// In en, this message translates to:
  /// **'LEFT'**
  String get left;

  /// No description provided for @middle.
  ///
  /// In en, this message translates to:
  /// **'MIDDLE'**
  String get middle;

  /// No description provided for @right.
  ///
  /// In en, this message translates to:
  /// **'RIGHT'**
  String get right;

  /// No description provided for @exit.
  ///
  /// In en, this message translates to:
  /// **'Exit'**
  String get exit;

  /// No description provided for @exitApp.
  ///
  /// In en, this message translates to:
  /// **'Exit App'**
  String get exitApp;

  /// No description provided for @exitConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to exit WaylandConnect?'**
  String get exitConfirmation;

  /// No description provided for @remote.
  ///
  /// In en, this message translates to:
  /// **'REMOTE'**
  String get remote;

  /// No description provided for @inputHint.
  ///
  /// In en, this message translates to:
  /// **'INPUT...'**
  String get inputHint;

  /// No description provided for @esc.
  ///
  /// In en, this message translates to:
  /// **'ESC'**
  String get esc;

  /// No description provided for @tab.
  ///
  /// In en, this message translates to:
  /// **'TAB'**
  String get tab;

  /// No description provided for @enter.
  ///
  /// In en, this message translates to:
  /// **'ENTER'**
  String get enter;

  /// No description provided for @ctrl.
  ///
  /// In en, this message translates to:
  /// **'CTRL'**
  String get ctrl;

  /// No description provided for @alt.
  ///
  /// In en, this message translates to:
  /// **'ALT'**
  String get alt;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'DELETE'**
  String get delete;

  /// No description provided for @superKey.
  ///
  /// In en, this message translates to:
  /// **'SUPER'**
  String get superKey;

  /// No description provided for @spacebar.
  ///
  /// In en, this message translates to:
  /// **'SPACEBAR'**
  String get spacebar;

  /// No description provided for @nowPlaying.
  ///
  /// In en, this message translates to:
  /// **'NOW PLAYING'**
  String get nowPlaying;

  /// No description provided for @secureLink.
  ///
  /// In en, this message translates to:
  /// **'SECURE_LINK'**
  String get secureLink;

  /// No description provided for @volume.
  ///
  /// In en, this message translates to:
  /// **'VOL'**
  String get volume;

  /// No description provided for @fastTrackJump.
  ///
  /// In en, this message translates to:
  /// **'FAST TRACK JUMP'**
  String get fastTrackJump;

  /// No description provided for @systemNode.
  ///
  /// In en, this message translates to:
  /// **'SYS_NODE'**
  String get systemNode;

  /// No description provided for @linked.
  ///
  /// In en, this message translates to:
  /// **'LINKED'**
  String get linked;

  /// No description provided for @buffer.
  ///
  /// In en, this message translates to:
  /// **'BUFFER'**
  String get buffer;

  /// No description provided for @stable.
  ///
  /// In en, this message translates to:
  /// **'STABLE'**
  String get stable;

  /// No description provided for @abstractText1.
  ///
  /// In en, this message translates to:
  /// **'DYNAMIC ABSTRACT'**
  String get abstractText1;

  /// No description provided for @abstractText2.
  ///
  /// In en, this message translates to:
  /// **'ENCRYPTED SIGNAL STABLE'**
  String get abstractText2;

  /// No description provided for @abstractText3.
  ///
  /// In en, this message translates to:
  /// **'CORE FLUID LINK ACTIVE'**
  String get abstractText3;

  /// No description provided for @abstractText4.
  ///
  /// In en, this message translates to:
  /// **'NEURAL PATH SYNCHRONIZED'**
  String get abstractText4;

  /// No description provided for @abstractText5.
  ///
  /// In en, this message translates to:
  /// **'QUANTUM AUDIO DECODED'**
  String get abstractText5;

  /// No description provided for @abstractText6.
  ///
  /// In en, this message translates to:
  /// **'SYSTEM INTEGRITY'**
  String get abstractText6;

  /// No description provided for @abstractText7.
  ///
  /// In en, this message translates to:
  /// **'RECURSIVE PLAYBACK INIT'**
  String get abstractText7;

  /// No description provided for @colorDynamic.
  ///
  /// In en, this message translates to:
  /// **'DYNAMIC'**
  String get colorDynamic;

  /// No description provided for @colorCrimson.
  ///
  /// In en, this message translates to:
  /// **'CRIMSON'**
  String get colorCrimson;

  /// No description provided for @colorNeon.
  ///
  /// In en, this message translates to:
  /// **'NEON'**
  String get colorNeon;

  /// No description provided for @colorRose.
  ///
  /// In en, this message translates to:
  /// **'ROSE'**
  String get colorRose;

  /// No description provided for @colorAmber.
  ///
  /// In en, this message translates to:
  /// **'AMBER'**
  String get colorAmber;

  /// No description provided for @colorPurple.
  ///
  /// In en, this message translates to:
  /// **'PURPLE'**
  String get colorPurple;

  /// No description provided for @presentationController.
  ///
  /// In en, this message translates to:
  /// **'PRESENTATION CONTROLLER'**
  String get presentationController;

  /// No description provided for @updateRate.
  ///
  /// In en, this message translates to:
  /// **'UPDATE RATE'**
  String get updateRate;

  /// No description provided for @batteryWarning.
  ///
  /// In en, this message translates to:
  /// **'Higher = smoother, more battery use'**
  String get batteryWarning;

  /// No description provided for @pointerSettings.
  ///
  /// In en, this message translates to:
  /// **'POINTER SETTINGS'**
  String get pointerSettings;

  /// No description provided for @color.
  ///
  /// In en, this message translates to:
  /// **'COLOR'**
  String get color;

  /// No description provided for @image.
  ///
  /// In en, this message translates to:
  /// **'IMAGE'**
  String get image;

  /// No description provided for @shape.
  ///
  /// In en, this message translates to:
  /// **'SHAPE'**
  String get shape;

  /// No description provided for @magnifier.
  ///
  /// In en, this message translates to:
  /// **'MAGNIFIER'**
  String get magnifier;

  /// No description provided for @zoomActive.
  ///
  /// In en, this message translates to:
  /// **'ZOOM ENGINE ACTIVE'**
  String get zoomActive;

  /// No description provided for @enableZoomWarning.
  ///
  /// In en, this message translates to:
  /// **'Enable Zoom in Desktop App settings first'**
  String get enableZoomWarning;

  /// No description provided for @sensitivity.
  ///
  /// In en, this message translates to:
  /// **'SENSITIVITY'**
  String get sensitivity;

  /// No description provided for @size.
  ///
  /// In en, this message translates to:
  /// **'SIZE'**
  String get size;

  /// No description provided for @pulseIntensity.
  ///
  /// In en, this message translates to:
  /// **'PULSE INTENSITY'**
  String get pulseIntensity;

  /// No description provided for @pulseSpeed.
  ///
  /// In en, this message translates to:
  /// **'PULSE SPEED'**
  String get pulseSpeed;

  /// No description provided for @stopMirroring.
  ///
  /// In en, this message translates to:
  /// **'STOP MIRRORING'**
  String get stopMirroring;

  /// No description provided for @mirrorRejected.
  ///
  /// In en, this message translates to:
  /// **'MIRROR REJECTED'**
  String get mirrorRejected;

  /// No description provided for @waitingForPc.
  ///
  /// In en, this message translates to:
  /// **'WAITING FOR PC...'**
  String get waitingForPc;

  /// No description provided for @startMirroring.
  ///
  /// In en, this message translates to:
  /// **'START MIRRORING'**
  String get startMirroring;

  /// No description provided for @acceptOnPc.
  ///
  /// In en, this message translates to:
  /// **'PLEASE ACCEPT ON YOUR PC'**
  String get acceptOnPc;

  /// No description provided for @waitingForVideo.
  ///
  /// In en, this message translates to:
  /// **'WAITING FOR VIDEO FEED'**
  String get waitingForVideo;

  /// No description provided for @tapToConnect.
  ///
  /// In en, this message translates to:
  /// **'TAP TO CONNECT TO HOST'**
  String get tapToConnect;

  /// No description provided for @cancelRequest.
  ///
  /// In en, this message translates to:
  /// **'CANCEL REQUEST'**
  String get cancelRequest;

  /// No description provided for @systemMirror.
  ///
  /// In en, this message translates to:
  /// **'SYSTEM MIRROR'**
  String get systemMirror;

  /// No description provided for @liveFeedActive.
  ///
  /// In en, this message translates to:
  /// **'LIVE FEED ACTIVE'**
  String get liveFeedActive;

  /// No description provided for @standbyMode.
  ///
  /// In en, this message translates to:
  /// **'STANDBY MODE'**
  String get standbyMode;

  /// No description provided for @stream.
  ///
  /// In en, this message translates to:
  /// **'STREAM'**
  String get stream;

  /// No description provided for @ping.
  ///
  /// In en, this message translates to:
  /// **'PING'**
  String get ping;

  /// No description provided for @launching.
  ///
  /// In en, this message translates to:
  /// **'LAUNCHING'**
  String get launching;

  /// No description provided for @switchingToMonitor.
  ///
  /// In en, this message translates to:
  /// **'SWITCHING TO MONITOR'**
  String get switchingToMonitor;

  /// No description provided for @equalizerSystem.
  ///
  /// In en, this message translates to:
  /// **'EQUALIZER SYSTEM'**
  String get equalizerSystem;

  /// No description provided for @visualIntensity.
  ///
  /// In en, this message translates to:
  /// **'VISUAL INTENSITY'**
  String get visualIntensity;

  /// No description provided for @min.
  ///
  /// In en, this message translates to:
  /// **'MIN'**
  String get min;

  /// No description provided for @max.
  ///
  /// In en, this message translates to:
  /// **'MAX'**
  String get max;

  /// No description provided for @particleEnvironment.
  ///
  /// In en, this message translates to:
  /// **'PARTICLE ENVIRONMENT'**
  String get particleEnvironment;

  /// No description provided for @density.
  ///
  /// In en, this message translates to:
  /// **'DENSITY'**
  String get density;

  /// No description provided for @speed.
  ///
  /// In en, this message translates to:
  /// **'SPEED'**
  String get speed;

  /// No description provided for @colorVariants.
  ///
  /// In en, this message translates to:
  /// **'COLOR VARIANTS'**
  String get colorVariants;

  /// No description provided for @particleGeometry.
  ///
  /// In en, this message translates to:
  /// **'PARTICLE GEOMETRY'**
  String get particleGeometry;

  /// No description provided for @presets.
  ///
  /// In en, this message translates to:
  /// **'PRESETS'**
  String get presets;

  /// No description provided for @cosmic.
  ///
  /// In en, this message translates to:
  /// **'COSMIC'**
  String get cosmic;

  /// No description provided for @rain.
  ///
  /// In en, this message translates to:
  /// **'RAIN'**
  String get rain;

  /// No description provided for @neon.
  ///
  /// In en, this message translates to:
  /// **'NEON'**
  String get neon;

  /// No description provided for @heartbeat.
  ///
  /// In en, this message translates to:
  /// **'HEARTBEAT'**
  String get heartbeat;

  /// No description provided for @cyber.
  ///
  /// In en, this message translates to:
  /// **'CYBER'**
  String get cyber;

  /// No description provided for @live.
  ///
  /// In en, this message translates to:
  /// **'LIVE'**
  String get live;

  /// No description provided for @paused.
  ///
  /// In en, this message translates to:
  /// **'PAUSED'**
  String get paused;

  /// No description provided for @noSignal.
  ///
  /// In en, this message translates to:
  /// **'NO SIGNAL'**
  String get noSignal;

  /// No description provided for @dataStreaming.
  ///
  /// In en, this message translates to:
  /// **'DATA_STREAMING'**
  String get dataStreaming;

  /// No description provided for @synchronizingPaths.
  ///
  /// In en, this message translates to:
  /// **'SYNCHRONIZING PATHS'**
  String get synchronizingPaths;

  /// No description provided for @locatingMediaSignal.
  ///
  /// In en, this message translates to:
  /// **'LOCATING MEDIA SIGNAL...'**
  String get locatingMediaSignal;

  /// No description provided for @noActiveSessions.
  ///
  /// In en, this message translates to:
  /// **'NO ACTIVE SESSIONS'**
  String get noActiveSessions;

  /// No description provided for @pleaseStartPlayer.
  ///
  /// In en, this message translates to:
  /// **'PLEASE START A MEDIA PLAYER ON YOUR PC'**
  String get pleaseStartPlayer;

  /// No description provided for @pointerManifestation.
  ///
  /// In en, this message translates to:
  /// **'Choose the manifestation of the pointer'**
  String get pointerManifestation;

  /// No description provided for @circle.
  ///
  /// In en, this message translates to:
  /// **'CIRCLE'**
  String get circle;

  /// No description provided for @celestial.
  ///
  /// In en, this message translates to:
  /// **'CELESTIAL'**
  String get celestial;

  /// No description provided for @plasma.
  ///
  /// In en, this message translates to:
  /// **'PLASMA'**
  String get plasma;

  /// No description provided for @kinetic.
  ///
  /// In en, this message translates to:
  /// **'KINETIC'**
  String get kinetic;

  /// No description provided for @dimensionalScale.
  ///
  /// In en, this message translates to:
  /// **'DIMENSIONAL SCALE'**
  String get dimensionalScale;

  /// No description provided for @magnification.
  ///
  /// In en, this message translates to:
  /// **'MAGNIFICATION'**
  String get magnification;

  /// No description provided for @custom.
  ///
  /// In en, this message translates to:
  /// **'CUSTOM'**
  String get custom;

  /// No description provided for @laser.
  ///
  /// In en, this message translates to:
  /// **'LASER'**
  String get laser;

  /// No description provided for @spotlight.
  ///
  /// In en, this message translates to:
  /// **'SPOTLIGHT'**
  String get spotlight;

  /// No description provided for @pointerSize.
  ///
  /// In en, this message translates to:
  /// **'POINTER SIZE'**
  String get pointerSize;

  /// No description provided for @horiStretch.
  ///
  /// In en, this message translates to:
  /// **'HORIZONTAL STRETCH'**
  String get horiStretch;

  /// No description provided for @vertStretch.
  ///
  /// In en, this message translates to:
  /// **'VERTICAL STRETCH'**
  String get vertStretch;

  /// No description provided for @customTextureActive.
  ///
  /// In en, this message translates to:
  /// **'Custom Texture Active'**
  String get customTextureActive;

  /// No description provided for @application.
  ///
  /// In en, this message translates to:
  /// **'APPLICATION'**
  String get application;

  /// No description provided for @launcher.
  ///
  /// In en, this message translates to:
  /// **'LAUNCHER'**
  String get launcher;

  /// No description provided for @searchApplications.
  ///
  /// In en, this message translates to:
  /// **'SEARCH APPLICATIONS...'**
  String get searchApplications;

  /// No description provided for @noAppsFound.
  ///
  /// In en, this message translates to:
  /// **'NO APPS FOUND'**
  String get noAppsFound;

  /// No description provided for @streamQuality.
  ///
  /// In en, this message translates to:
  /// **'STREAM QUALITY'**
  String get streamQuality;

  /// No description provided for @resolution.
  ///
  /// In en, this message translates to:
  /// **'RESOLUTION'**
  String get resolution;

  /// No description provided for @framerate.
  ///
  /// In en, this message translates to:
  /// **'FRAMERATE'**
  String get framerate;

  /// No description provided for @saveSettings.
  ///
  /// In en, this message translates to:
  /// **'SAVE SETTINGS'**
  String get saveSettings;

  /// No description provided for @selectMonitor.
  ///
  /// In en, this message translates to:
  /// **'Select Monitor'**
  String get selectMonitor;

  /// No description provided for @noMonitorsDetected.
  ///
  /// In en, this message translates to:
  /// **'No Monitors Detected'**
  String get noMonitorsDetected;

  /// No description provided for @screenShareInstructions.
  ///
  /// In en, this message translates to:
  /// **'Drag to move • Tap to click • Long press for right click'**
  String get screenShareInstructions;

  /// No description provided for @updateRequired.
  ///
  /// In en, this message translates to:
  /// **'Update Required'**
  String get updateRequired;

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

  /// No description provided for @mirroringRequest.
  ///
  /// In en, this message translates to:
  /// **'Mirroring Request'**
  String get mirroringRequest;

  /// No description provided for @wantsToMirrorYourScreen.
  ///
  /// In en, this message translates to:
  /// **'wants to mirror your screen'**
  String get wantsToMirrorYourScreen;

  /// No description provided for @media.
  ///
  /// In en, this message translates to:
  /// **'Media'**
  String get media;

  /// No description provided for @present.
  ///
  /// In en, this message translates to:
  /// **'Present'**
  String get present;

  /// No description provided for @desktop.
  ///
  /// In en, this message translates to:
  /// **'Desktop'**
  String get desktop;

  /// No description provided for @configuration.
  ///
  /// In en, this message translates to:
  /// **'Configuration'**
  String get configuration;

  /// No description provided for @powerLogic.
  ///
  /// In en, this message translates to:
  /// **'Power Logic'**
  String get powerLogic;

  /// No description provided for @bypassBattery.
  ///
  /// In en, this message translates to:
  /// **'Bypass battery optimizations'**
  String get bypassBattery;

  /// No description provided for @establishConnection.
  ///
  /// In en, this message translates to:
  /// **'Establish Connection'**
  String get establishConnection;

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

  /// No description provided for @autoConnectSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Automatically connect to trusted devices'**
  String get autoConnectSubtitle;

  /// No description provided for @autoReconnect.
  ///
  /// In en, this message translates to:
  /// **'Auto Reconnect'**
  String get autoReconnect;

  /// No description provided for @autoReconnectSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Let this PC reconnect without manual approval'**
  String get autoReconnectSubtitle;

  /// No description provided for @requestAutoReconnect.
  ///
  /// In en, this message translates to:
  /// **'Request Auto-reconnect'**
  String get requestAutoReconnect;

  /// No description provided for @autoReconnectStatus.
  ///
  /// In en, this message translates to:
  /// **'Status: {status}'**
  String autoReconnectStatus(Object status);

  /// No description provided for @revokeAutoReconnect.
  ///
  /// In en, this message translates to:
  /// **'Revoke Auto-reconnect'**
  String get revokeAutoReconnect;

  /// No description provided for @approvalRequired.
  ///
  /// In en, this message translates to:
  /// **'Approval Required on PC'**
  String get approvalRequired;
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
      'that was used.');
}
