import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/app_state_provider.dart';
import 'providers/theme_provider.dart';
import 'services/debug_log_service.dart';
import 'services/subscription_service.dart';
import 'services/storage_service.dart';
import 'services/reminder_manager.dart';
import 'services/analytics_service.dart';
import 'services/share_handler_service.dart';
import 'screens/main/main_navigation.dart';
import 'screens/onboarding/activate_bubble_screen.dart';
import 'screens/onboarding/permissions_screen.dart';
import 'screens/onboarding/feature_showcase_screen.dart';
import 'screens/onboarding/first_recording_screen.dart';
import 'screens/import/import_content_screen.dart';
import 'services/retention_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await DebugLogService().log('App', 'main() entered (main isolate)');

  // Initialize Firebase - REQUIRED for App Store
  await Firebase.initializeApp();
  debugPrint('✅ Firebase initialized successfully');
  
  // Initialize Firebase Analytics
  final analytics = AnalyticsService();
  debugPrint('✅ Firebase Analytics initialized successfully');
  
  // Initialize Hive storage - CRITICAL FOR SAVING!
  await StorageService.initialize();
  debugPrint('✅ Hive storage initialized successfully');

  // Initialize reminder system
  await ReminderManager().initialize();
  debugPrint('✅ Reminder system initialized');

  // Initialize In-App Purchase system
  await SubscriptionService().initialize();
  debugPrint('✅ Subscription service initialized');

  // Initialize share handler for receiving shared files from other apps
  ShareHandlerService().initialize();
  debugPrint('✅ Share handler initialized');

  runApp(const MyApp());
}

/// Lightweight no-op entry point used by `MyApplication.kt` to keep
/// a long-lived Flutter engine alive in the background. We don't run
/// the full main app inside this engine — we just need an isolate
/// that has all pubspec plugins (especially flutter_overlay_window)
/// auto-registered, so the bubble's native service can invoke
/// `showOverlay` on the plugin's method channel without bringing
/// MainActivity to the foreground (avoids the visible flash).
@pragma('vm:entry-point')
void bgEngineMain() {
  WidgetsFlutterBinding.ensureInitialized();
  // Keep the isolate alive forever — plugins are now reachable from
  // any Service in the same process via FlutterEngineCache.
  // No UI, no Firebase init, no app state. Pure plumbing.
  DebugLogService().log(
    'BgEngine',
    'bgEngineMain entry-point reached — plugins ready on cached engine',
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const _overlayChannel = MethodChannel('voicebubble/overlay');

  final _navigatorKey = GlobalKey<NavigatorState>();
  SharedContent? _pendingShareContent;

  @override
  void initState() {
    super.initState();
    _setupShareListener();
    _setupOverlayFallbackListener();
  }

  /// Fallback path for the bubble. Primary path is direct invocation
  /// on the cached bg Flutter engine from native (zero flash). If that
  /// fails (cold start without MyApplication, etc.), OverlayService
  /// re-routes through MainActivity which hits this listener.
  void _setupOverlayFallbackListener() {
    _overlayChannel.setMethodCallHandler((call) async {
      if (call.method == 'showOverlayWindow') {
        await DebugLogService()
            .log('Bridge', 'Dart received showOverlayWindow (fallback path)');
        try {
          final isShowing = await FlutterOverlayWindow.isActive();
          await DebugLogService()
              .log('Bridge', 'FlutterOverlayWindow.isActive=$isShowing');
          if (isShowing == true) return null;
          await FlutterOverlayWindow.showOverlay(
            height: 220,
            width: WindowSize.matchParent,
            alignment: OverlayAlignment.center,
            flag: OverlayFlag.defaultFlag,
            overlayTitle: 'VoiceBubble',
            overlayContent: 'Recording',
            enableDrag: false,
          );
          await DebugLogService()
              .log('Bridge', 'FlutterOverlayWindow.showOverlay returned');
        } catch (e) {
          debugPrint('❌ Overlay fallback path failed: $e');
          await DebugLogService()
              .log('Bridge', 'Fallback showOverlay threw: $e');
        }
      }
      return null;
    });
  }

  void _setupShareListener() {
    // Check for buffered content from cold start (arrived before we subscribed)
    final buffered = ShareHandlerService().consumeBufferedContent();
    if (buffered != null) {
      debugPrint('📥 Found buffered share content from cold start: ${buffered.type.name}');
      _pendingShareContent = buffered;
    }

    // Listen for future shares (warm start or late cold start delivery)
    ShareHandlerService().pendingShares.listen((content) {
      debugPrint('📥 Stream received shared content: ${content.type.name}');
      _pendingShareContent = content;

      // For warm start: navigate after a delay (no splash race)
      // For cold start: _navigateToImportIfPending() will handle it after splash
      Future.delayed(const Duration(milliseconds: 1500), () {
        // Only navigate if still pending (cold start handler may have consumed it)
        if (_pendingShareContent != null && _navigatorKey.currentState != null) {
          final pendingContent = _pendingShareContent!;
          _pendingShareContent = null;
          debugPrint('📥 Warm start: navigating to ImportContentScreen');
          _navigatorKey.currentState!.push(
            MaterialPageRoute(
              builder: (_) => ImportContentScreen(content: pendingContent),
            ),
          );
        }
      });
    });
  }

  /// Called after MainNavigation is loaded to handle any pending share from cold start
  void _navigateToImportIfPending() {
    final content = _pendingShareContent;
    if (content == null) return;

    _pendingShareContent = null;
    debugPrint('📥 Cold start: navigating to ImportContentScreen after splash');

    // Delay to ensure MainNavigation is fully built and mounted
    Future.delayed(const Duration(milliseconds: 500), () {
      if (_navigatorKey.currentState != null) {
        _navigatorKey.currentState!.push(
          MaterialPageRoute(
            builder: (_) => ImportContentScreen(content: content),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) {
            final provider = AppStateProvider();
            // Initialize in the background, don't block UI
            provider.initialize();
            return provider;
          },
        ),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            navigatorKey: _navigatorKey,
            title: 'VoiceBubble',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              brightness: Brightness.dark, // Always dark mode
              primaryColor: const Color(0xFF3B82F6), // Blue
              scaffoldBackgroundColor: const Color(0xFF000000),
              useMaterial3: true,
            ),
            navigatorObservers: [
              AnalyticsService().observer, // Track screen views
            ],
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkOnboardingStatus();
  }

  Future<void> _checkOnboardingStatus() async {
    await Future.delayed(const Duration(seconds: 1));
    
    final prefs = await SharedPreferences.getInstance();
    final hasCompletedOnboarding = prefs.getBool('hasCompletedOnboarding') ?? false;
    
    if (mounted) {
      if (hasCompletedOnboarding) {
        // Track app open and cancel retention notifications if subscribed
        RetentionNotificationService().recordAppOpen();
        RetentionNotificationService().cancelIfSubscribed();

        // Onboarding complete — go straight to home, regardless of auth state
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const MainNavigation()),
        );
        // After MainNavigation is loaded, handle any pending share intent
        final myAppState = context.findAncestorStateOfType<_MyAppState>();
        myAppState?._navigateToImportIfPending();
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => OnboardingFlow(
              onComplete: (BuildContext navContext) async {
                debugPrint('✅ ONBOARDING COMPLETE - Navigating to HomeScreen');
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('hasCompletedOnboarding', true);
                debugPrint('✅ Saved hasCompletedOnboarding = true');
                
                // Use pushAndRemoveUntil to clear the entire navigation stack
                debugPrint('✅ Clearing navigation stack and going to MainNavigation...');
                Navigator.of(navContext).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const MainNavigation()),
                  (Route<dynamic> route) => false, // Remove all previous routes
                );
              },
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: const LinearGradient(
                  colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Icon(
                Icons.mic,
                size: 60,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'VoiceBubble',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OnboardingFlow extends StatefulWidget {
  final void Function(BuildContext) onComplete;

  const OnboardingFlow({super.key, required this.onComplete});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  int _currentStep = 0;

  void _nextStep() {
    if (_currentStep < 2) {
      setState(() {
        _currentStep++;
      });
    }
    // After permissions (step 1 → 2), finish onboarding immediately
    if (_currentStep >= 2) {
      widget.onComplete(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_currentStep) {
      case 0:
        return FeatureShowcaseScreen(onComplete: _nextStep);
      case 1:
        // The mission of the entire onboarding: activate the bubble
        // and use it once. Voice-only is available as a secondary
        // link inside this screen but the primary CTA is bubble.
        return ActivateBubbleScreen(onComplete: _nextStep);
      case 2:
        return const MainNavigation();
      default:
        return const MainNavigation();
    }
  }
}
// Build trigger Wed Feb  4 04:01:23 GMT 2026
