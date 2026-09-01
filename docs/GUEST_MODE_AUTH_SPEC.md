# Implementation Spec — Guest Mode, Deferred Login & Theme Selection
**Customer app only (`main_customer.dart` flavor). Written Aug 11 2026.**

This spec is self-contained. You do **not** need prior conversation history.

---

## 0. Context you need before writing any code

**Project:** Flutter monorepo at `C:\Projects\Allin1`. Four flavors share one
codebase: `main_customer.dart`, `main_hero.dart`, `main_seller.dart`,
`main_admin.dart`. This spec touches the **customer** flavor only.

**Backend:** Firebase Spark (free) plan. **No Cloud Functions available.**
Firestore + Realtime Database + Firebase Auth.

**Verification convention (important — there is no compiler in the authoring
sandbox):** after editing any Dart file, run a bracket-balance check:

```bash
python3 -c "s=open('FILE').read(); print('parens',s.count('('),s.count(')'),'braces',s.count('{'),s.count('}'))"
```

Then have the user run `flutter analyze` before building. A few files have a
harmless pre-existing 1-paren imbalance caused by an unmatched `(` inside
comment prose — verify against `git show HEAD:FILE` before assuming you broke it.

---

## 1. CRITICAL — read this before designing auth

`firestore.rules` defines:

```
function isAuth() { return request.auth != null; }
```

**Anonymous users satisfy `isAuth()`.** They are indistinguishable from
registered customers in every rule in the file. This has two consequences you
must design around:

1. If you implement guest mode via **anonymous sign-in**, guests immediately
   get the same read/write access as registered users.
2. Anonymous accounts are free and unlimited to create, so this is also a
   denial-of-wallet risk against the Spark daily quota.

**Required rules work (do this as part of this task):** add a helper and use it
to gate write-type collections so anonymous users can browse but not write:

```
function isRealUser() {
  return request.auth != null && request.auth.token.firebase.sign_in_provider != 'anonymous';
}
```

Apply `isRealUser()` to create/update on: `rides`, `service_requests`,
`orders`, `app_bug_reports`, and any wallet/payment collection. Leave read
access on catalogue collections (`erode_offers`, `sellers`, `products`) as-is
so guests can browse.

Deploy with `firebase deploy --only firestore:rules`.

---

## 2. Architecture decision (do it this way)

**Use silent anonymous sign-in for guests, then `linkWithCredential` to
upgrade.**

Rationale: many existing screens call `FirebaseAuth.instance.currentUser!` or
gate RTDB reads on `auth != null`. Letting `currentUser` be `null` while the
dashboard is live would require auditing and null-hardening dozens of call
sites — high risk, days of work. Anonymous sign-in gives every guest a real
`uid` from the first frame, so **existing screens keep working unchanged**.

Upgrading via `linkWithCredential` preserves that same `uid`, so any activity
a guest accumulated before signing in (cart, recent places, Hive cache keyed by
uid) carries over instead of being orphaned. Do **not** sign out and sign in
fresh — that silently loses their data.

---

## 3. Files to touch

| # | File | Change |
|---|---|---|
| 1 | `lib/main_customer.dart` | Remove login wall from `_CustomerHomeGate`; add silent anonymous sign-in |
| 2 | `lib/services/auth_service.dart` | Add `ensureGuestSession()`, `isRealUser`, `upgradeGuestWithGoogle()` |
| 3 | **NEW** `lib/widgets/auth/auth_gate_sheet.dart` | The login+theme modal |
| 4 | **NEW** `lib/services/auth_prompt_service.dart` | `requireRealAuth()` wrapper + 30s timer logic |
| 5 | `lib/screens/dashboard_screen.dart` | Start the 30s timer |
| 6 | Booking screens (§7) | Call `requireRealAuth()` before submit |
| 7 | `firestore.rules` | Add `isRealUser()` (§1) |

---

## 4. File 1 — `lib/main_customer.dart`

**Locate `_CustomerHomeGateState.build()`** (search `class _CustomerHomeGateState`,
approx. line 854). It currently ends with:

```dart
if (user == null) {
  return const CustomerWelcomeLoginScreen(next: DashboardScreen());
}
return const DashboardScreen();
```

**Replace with:**

```dart
// GUEST MODE (Aug 2026): no login wall on boot. A null user here means
// anonymous sign-in has not completed yet — that is a sub-second gap, not
// a state worth showing a login screen for. Returning DashboardScreen
// unconditionally guarantees exactly ONE transition: HTML splash -> Home.
// Any screen that genuinely needs a real (non-anonymous) account calls
// requireRealAuth() at the moment of the action instead. See
// lib/services/auth_prompt_service.dart.
return const DashboardScreen();
```

**Keep the `_lastUid` / `AiActivationService.refreshForUser` block above it
unchanged** — it must still fire when the uid changes (guest → real user).

**Do NOT delete** `customer_welcome_login_screen.dart`; it is still used by
other flavors via `lib/screens/login_screen.dart`.

**Add silent guest sign-in.** In `main()`, in the repeat-launch branch (search
`runApp(const CustomerApp());` followed by `unawaited(_runBootPhase1());`), add:

```dart
unawaited(AuthService().ensureGuestSession());
```

Must be `unawaited` — it is a network call and must never block first paint.

---

## 5. File 2 — `lib/services/auth_service.dart`

`AuthService` is a singleton with an existing `loginAsGuest()` that calls
`signInAnonymously()`. Add three members:

```dart
/// True only for a fully registered account. Anonymous guests return false.
bool get isRealUser {
  final u = _auth.currentUser;
  return u != null && !u.isAnonymous;
}

/// Idempotent. Signs in anonymously ONLY if nobody is signed in, so it never
/// disturbs an existing real session on relaunch.
Future<void> ensureGuestSession() async {
  if (_auth.currentUser != null) return;
  try {
    await _auth.signInAnonymously();
  } catch (e) {
    debugPrint('[AuthService] ensureGuestSession failed: $e');
    // Non-fatal: the app still runs, screens needing auth will prompt.
  }
}

/// Upgrades the CURRENT anonymous session to a real Google account,
/// PRESERVING the uid so guest activity is not orphaned.
/// Falls back to a normal sign-in if there is no anonymous session to link.
Future<AuthResult> upgradeGuestWithGoogle() async {
  // 1. Obtain GoogleAuthCredential exactly as the existing
  //    signInWithGoogle() does — reuse that code path, do not duplicate it.
  // 2. If _auth.currentUser?.isAnonymous == true:
  //       await _auth.currentUser!.linkWithCredential(credential)
  //    On FirebaseAuthException code 'credential-already-in-use':
  //       that Google account already exists -> fall back to
  //       signInWithCredential(credential). The guest uid is discarded;
  //       this is correct and unavoidable.
  // 3. Else: await _auth.signInWithCredential(credential)
  // 4. Write users/{uid} with phoneNumber/phone/isSetupComplete: true,
  //    matching what customer_login_screen.dart's _signUpWithGoogle() writes.
  //    _CustomerHomeGate assumes any real user has a complete profile.
}
```

---

## 6. File 3 — NEW `lib/widgets/auth/auth_gate_sheet.dart`

A modal bottom sheet, used for **both** the 30s prompt and action-triggered
auth. One widget, two entry points.

**API:**

```dart
/// Returns true if the user completed sign-in, false if dismissed/skipped.
Future<bool> showAuthGateSheet(
  BuildContext context, {
  /// Why we're asking. Shown as the subtitle. e.g. "Sign in to place your
  /// food order" — action-specific reasons convert far better than a
  /// generic "Please log in".
  required String reason,
  /// 30s timer prompt = true (shows "Later"). Action-triggered = false
  /// (still dismissible via drag/back, but no explicit Later button, since
  /// skipping cannot complete the action they just tapped).
  bool showLaterButton = false,
});
```

**Layout, top to bottom:**

1. Drag handle.
2. App icon (`web/icons/Icon-customer-192.png` equivalent asset, or the
   existing pink gradient mark used by `BrandedLoadingScreen`).
3. Title: **"Welcome to MyAllin1"**.
4. Subtitle: the `reason` string.
5. **Theme selection row** (§6a).
6. Primary button: **Continue with Google** → `AuthService().upgradeGuestWithGoogle()`.
7. Secondary: **Continue with Mobile Number** → reuse the existing
   mobile-number flow from `lib/screens/customer_login_screen.dart`. If that
   flow is a full screen, push it and `await` the result rather than
   re-implementing it inside the sheet.
8. If `showLaterButton`: a low-emphasis text button **"Later"** →
   `Navigator.pop(context, false)`.

**Behaviour:**

- `isScrollControlled: true`, rounded top corners (radius 22), theme background.
- Pop `true` only after auth genuinely succeeds.
- On failure show an inline error inside the sheet; do **not** close it.
- Wrap in `PopScope(canPop: true)` — never trap the user.

### 6a. Theme selection inside the sheet

`lib/services/theme_service.dart` already exists: a `ChangeNotifier` with 5
selectable themes, exposed app-wide via `ChangeNotifierProvider` in
`CustomerApp`, and read as `context.watch<ThemeService>().currentTheme`.

- Render a horizontal row of circular colour swatches, one per theme.
- Selected swatch gets a ring/check.
- Tapping applies **immediately** via the existing ThemeService setter so the
  sheet itself restyles live — that instant feedback is the whole point of
  putting this here.
- Read the existing setter name from `theme_service.dart`; do not invent one.
- Persisting is already handled by ThemeService. Do not add a second
  persistence path.

---

## 7. File 4 — NEW `lib/services/auth_prompt_service.dart`

Two responsibilities.

### 7a. `requireRealAuth()` — the reusable action wrapper

```dart
/// Call at the TOP of any action that must not be performed by a guest.
/// Returns true if the caller may proceed.
///
/// Usage:
///   if (!await requireRealAuth(context, reason: 'Sign in to book a Hero')) return;
///   ...existing booking code unchanged...
Future<bool> requireRealAuth(BuildContext context, {required String reason}) async {
  if (AuthService().isRealUser) return true;
  if (!context.mounted) return false;
  return await showAuthGateSheet(context, reason: reason) ?? false;
}
```

Deliberately a plain function, not a widget wrapper: booking actions are
triggered inside `onPressed` callbacks, so a guard at the top of the handler is
both simpler and impossible to accidentally bypass by navigating in another way.

### 7b. The 30s deferred prompt

```dart
class AuthPromptService {
  static final AuthPromptService instance = ...;
  Timer? _timer;
  bool _shownThisSession = false;
  static const _dismissedKey = 'auth_prompt_dismissed_at';
  static const _reAskAfter = Duration(hours: 24);

  /// Called from DashboardScreen.initState().
  void scheduleDeferredPrompt(BuildContext context) { ... }
  void cancel() { _timer?.cancel(); }
}
```

Rules:
- Do nothing if `AuthService().isRealUser`.
- Do nothing if already shown this session.
- Do nothing if `_dismissedKey` (SharedPreferences) is within 24h — someone who
  tapped "Later" should not be asked again on every app open.
- After 30s: check `context.mounted`, then
  `showAuthGateSheet(context, reason: 'Sign in to save your orders and track your bookings', showLaterButton: true)`.
- On dismissal, write `_dismissedKey = now`.
- **Do not show it if a modal/route is already on top** — check
  `ModalRoute.of(context)?.isCurrent == true` first. Ambushing someone
  mid-booking-flow with a login sheet is worse than not asking.

---

## 8. File 5 — `lib/screens/dashboard_screen.dart`

In `initState()`:

```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  if (mounted) AuthPromptService.instance.scheduleDeferredPrompt(context);
});
```

`addPostFrameCallback` is required — `context` is not safe for
`showModalBottomSheet` during `initState`.

In `dispose()`: `AuthPromptService.instance.cancel();`

---

## 9. File 6 — apply the guard to every booking action

Add this one line at the top of each submit handler, **before** any Firestore
write or navigation:

```dart
if (!await requireRealAuth(context, reason: '<action-specific reason>')) return;
```

| File | Handler (search for) | Suggested reason |
|---|---|---|
| `lib/screens/hero_booking_screen.dart` | the `createServiceRequest(` call site (~line 501) | Sign in to book a Hero |
| `lib/screens/grocery_order_screen.dart` | `createServiceRequest(` (~line 223) | Sign in to place your grocery order |
| `lib/screens/custom_food_order_screen.dart` | `createServiceRequest(` (~line 208) | Sign in to place your food order |
| `lib/screens/custom_order_screen.dart` | `createServiceRequest(` (~line 68) | Sign in to place your order |
| `lib/screens/custom_hotel_view_screen.dart` | `createServiceRequest(` (~line 445) | Sign in to order from this hotel |
| `lib/screens/nj_tech_store_screen.dart` | `createServiceRequest(` (~line 810) | Sign in to request this service |
| `lib/screens/bike_taxi/bike_booking_screen.dart` | the Confirm Booking handler that builds `RideModel` (~line 2010) | Sign in to book your ride |
| `lib/screens/checkout_screen.dart` | the place-order handler | Sign in to complete your order |
| `lib/screens/guru_chat_screen.dart` | `_actOnCreateServiceRequest` | Sign in to place this order |

**Important:** guests must still be able to **browse** every one of these
screens. Only the final submit action is gated.

**Note on the AI agent:** `guru_chat_screen.dart`'s `_actOnCreateServiceRequest`
already checks `FirebaseAuth.instance.currentUser == null`. That check now
passes for anonymous guests, so it must be upgraded to `requireRealAuth()` or
guests will place orders under an anonymous uid with no way to contact them.

---

## 10. Acceptance criteria

1. Cold boot → exactly **one** transition: HTML splash → Home. No login screen,
   no second splash, no flash.
2. Guest can browse every service screen freely.
3. At 30s on Home, the sheet appears with a working **Later** button.
4. "Later" → not asked again for 24h.
5. Tapping any booking/submit action as a guest → sheet appears immediately
   with an action-specific reason.
6. Completing sign-in → the action the user originally tapped proceeds without
   them having to tap it again (verify per call site).
7. Theme swatch tap restyles the sheet instantly and survives an app restart.
8. Sign-in from guest **preserves the uid** (verify in Firebase console: the
   anonymous uid becomes the Google-linked uid, not a new one).
9. `flutter analyze` clean; all touched files bracket-balanced.

---

## 11. Do not do these

- Do **not** re-add a login gate in `_CustomerHomeGate`.
- Do **not** call `signOut()` before linking a Google account — it orphans the
  guest's data.
- Do **not** add a second theme-persistence mechanism.
- Do **not** show the 30s prompt while another route/modal is on top.
- Do **not** ship without the `isRealUser()` rules change in §1 — otherwise
  anonymous accounts can write to every collection.
