// ================================================================
// hero_skill_catalog.dart — SKILL heroes (electrician, plumber,
// laptop/PC, TV, fridge & AC) as first-class hero categories.
// ================================================================
// NEW (Aug 29 2026 — Nizam: "hero and vehicle category iruku, but
// skillers electrician, punjar, lap&pc, TV, fridge&ac ithu yellathukum
// heros join pannunum... admin same approval, register pannuna heros ku
// customer app la search pannumbothu nearby 5 kms la iruka heros
// availability kaatanum, request kudukumbothu customer request entha
// hero accept pandraro avarukku followup aganum").
//
// THE DESIGN CONSTRAINT Nizam set: "backend logic maarama" — do not
// change the dispatch backend. This file is what makes that possible.
//
// WHY NO NEW PIPELINE
// A skilled worker's job is, mechanically, the SAME transaction the app
// already runs for NJ Tech electronics work: customer describes a
// problem at an address, nearby heroes get pinged, first to accept owns
// it, customer follows that one hero to completion. That is
// `requestType: 'electronics_service'`, live since the NJ Tech launch
// and already wired end to end — admin_new_orders, admin_service_
// requests, my_orders, hero_home_screen's ping card, and the shared
// hero_booking_status_screen bottom sheet all handle it today.
//
// The Mobile Hub proved the pattern first: mobile_service_sheet.dart
// files an 'electronics_service' request carrying `category: 'mobile'`
// and got the whole lifecycle for free, with no new requestType. A
// plumber booking is the same move with `category: 'plumber'`.
//
// So a skill hero needs exactly three things that did not exist:
//   1. A category to pick in the onboarding form  -> [kHeroSkills]
//   2. A way for dispatch to send an electrician job to electricians
//      and not to every hero in the city               -> [kHeroSkillsField]
//   3. Distance, because a plumber 14km away is not a plumber
//                    -> kSkillDispatchRadiusKm, enforced in
//                       service_request_service._broadcastToEligibleHeroes
//
// WHAT IS DELIBERATELY REUSED, NOT REBUILT
//   * Approval: skill heroes write the identical heroes/{uid} doc with
//     approvalStatus:'pending'. hero_approvals_screen.dart needs no new
//     queue — Nizam asked for "admin same approval" and this is it.
//   * Permissions: hero_service_access.dart already gates work per hero.
//     A skill hero is simply a hero whose serviceAccess denies every
//     bucket, including the generic electronics_service one — their
//     own trade jobs bypass that bucket entirely via a dedicated skill
//     match in dispatch. See [skillHeroServiceAccess]. No new
//     permission system.
//   * Presence: the existing online_heroes/{uid} node carries lat/lng
//     and city already. It gains one more mirrored field, [kHeroSkillsField],
//     alongside the serviceAccess mirror that is already there.
//
// THE vehicleType QUESTION
// Every hero doc has `vehicleType`, and ride dispatch matches a booking's
// category against it. Skill heroes get [kSkillWorkerVehicleType], a
// value no ride category can ever equal, so the ride matcher can never
// select them — belt. [skillHeroServiceAccess] also denies ride/parcel
// explicitly — braces. Two independent mechanisms, because a plumber
// receiving a bike-taxi ping is the exact "kulappam" this is meant to
// prevent.
// ================================================================

import 'package:colorful_iconify_flutter/icons/fluent_emoji_flat.dart';
import 'package:flutter/material.dart';

import 'hero_service_access.dart';

/// Firestore/RTDB field holding a hero's skill keys, e.g. `['plumber']`.
///
/// A LIST, not a single string, even though the onboarding form only
/// lets a hero pick one today. Real tradespeople are routinely two
/// things at once — the electrician who also services ACs is the norm in
/// Erode, not the exception — and widening a scalar field to a list on a
/// live collection later is a migration; starting as a list is free.
/// Dispatch already reads it as a membership test, so admin granting a
/// hero a second skill needs no code change at all.
const String kHeroSkillsField = 'skills';

/// `heroes/{uid}.vehicleType` for a hero who drives nothing.
///
/// Not left null and not defaulted to 'bike'. Both would be actively
/// harmful: ride_search_screen matches on this field, and a null or
/// 'bike' plumber is a plumber who gets bike-taxi pings. This value
/// matches no entry in ride_catalog.dart, by construction.
const String kSkillWorkerVehicleType = 'skill_worker';

/// `service_requests.details.category` value that routes a customer
/// booking to skill heroes. The request itself stays
/// `requestType: 'electronics_service'` — see this file's header.
const String kSkillRequestCategoryKey = 'category';

/// How far a skill job is broadcast, in kilometres (Nizam: "nearby 5
/// kms la iruka heros availability kaatanum").
///
/// Applies to SKILL requests ONLY. Rides, food, grocery, parcel and
/// custom orders keep their existing city-wide fan-out untouched —
/// narrowing those on a live fleet would silently cut hero supply for
/// flows that are working today, which is not a change anybody asked
/// for. See _broadcastToEligibleHeroes: the radius is applied only when
/// a caller passes both a skill and a customer location.
const double kSkillDispatchRadiusKm = 5;

/// One bookable trade.
@immutable
class HeroSkill {
  const HeroSkill({
    required this.key,
    required this.title,
    required this.tamilTitle,
    required this.subtitle,
    required this.icon,
    required this.svgIcon,
    required this.color,
  });

  /// Canonical key. Written to `heroes/{uid}.skills` and to a request's
  /// `details.category`; the two must match exactly or dispatch finds
  /// nobody, so both sides read it from here.
  final String key;

  final String title;

  /// Shown under the English title in the customer grid and the hero
  /// onboarding picker. Most heroes onboarding for these trades read
  /// Tamil far more comfortably than English, and this form is the one
  /// place a wrong tap costs them a rejected application.
  final String tamilTitle;

  final String subtitle;

  /// Kept as a fallback only — nothing renders this anymore. See
  /// [svgIcon].
  final IconData icon;

  /// Full-color FluentEmojiFlat SVG markup (from
  /// package:colorful_iconify_flutter, already bundled and used
  /// throughout the customer dashboard — see dashboard_screen.dart),
  /// rendered via SvgPicture.string wherever a trade's icon shows.
  ///
  /// NEW (Aug 29 2026 — Nizam, on seeing the rendered cards: "icons
  /// category ku mismatch aagi irukku"). The monochrome Material glyphs
  /// this used to carry (electrical_services, plumbing,
  /// laptop_chromebook, tv, ac_unit) render at a small size as
  /// near-identical grey rounded-rectangle silhouettes — exactly the
  /// "which one is the fridge and which is the laptop" confusion a hero
  /// glancing at this picker on a small phone screen hits. A full-color
  /// illustrated icon per trade is unambiguous at a glance without
  /// needing the caption at all, which is the actual goal here ("hero
  /// paathathum identify pandramari" — identifiable the instant a hero
  /// looks at it).
  final String svgIcon;

  final Color color;
}

/// The bookable trades, in the order they appear in both the hero
/// onboarding picker and the customer services grid.
final List<HeroSkill> kHeroSkills = <HeroSkill>[
  HeroSkill(
    key: 'electrician',
    title: 'Electrician',
    tamilTitle: 'மின் பணியாளர்',
    subtitle: 'Wiring, switches, fans, repairs',
    icon: Icons.electrical_services_rounded,
    svgIcon: FluentEmojiFlat.electric_plug,
    color: const Color(0xFFF5A623),
  ),
  HeroSkill(
    key: 'plumber',
    title: 'Plumber',
    tamilTitle: 'பிளம்பர்',
    subtitle: 'Taps, pipes, leaks, fittings',
    icon: Icons.plumbing_rounded,
    svgIcon: FluentEmojiFlat.wrench,
    color: const Color(0xFF2D9CDB),
  ),
  HeroSkill(
    key: 'laptop_pc',
    title: 'Laptop & PC',
    tamilTitle: 'லேப்டாப் & பிசி',
    subtitle: 'Service, software, upgrades',
    icon: Icons.laptop_chromebook_rounded,
    svgIcon: FluentEmojiFlat.laptop,
    color: const Color(0xFF9B51E0),
  ),
  HeroSkill(
    key: 'tv_service',
    title: 'TV Service',
    tamilTitle: 'டிவி சர்வீஸ்',
    subtitle: 'Panel, display, installation',
    icon: Icons.tv_rounded,
    svgIcon: FluentEmojiFlat.television,
    color: const Color(0xFF27AE60),
  ),
  HeroSkill(
    key: 'fridge_ac',
    title: 'Fridge & AC',
    tamilTitle: 'ஃப்ரிட்ஜ் & ஏசி',
    subtitle: 'Cooling, gas filling, service',
    icon: Icons.ac_unit_rounded,
    svgIcon: FluentEmojiFlat.snowflake,
    color: const Color(0xFF56CCF2),
  ),
];

/// All skill keys, for membership tests.
final Set<String> kHeroSkillKeys =
    kHeroSkills.map((s) => s.key).toSet();

/// The skill for [key], or null when [key] is not a trade.
///
/// Returns null rather than a fallback on purpose: callers use a null
/// here to mean "this is not a skill request, dispatch normally", and a
/// silent fallback to the first trade would send every unrecognised
/// request to electricians.
HeroSkill? heroSkillFor(String? key) {
  if (key == null) return null;
  final normalized = key.trim().toLowerCase();
  for (final skill in kHeroSkills) {
    if (skill.key == normalized) return skill;
  }
  return null;
}

/// Display label for [key], falling back to the raw key so an admin
/// screen showing a skill added by a future build still renders
/// something truthful instead of blank.
String heroSkillLabel(String? key) =>
    heroSkillFor(key)?.title ?? (key ?? '').trim();

/// True when [heroData] — a `heroes/{uid}` doc map or an
/// `online_heroes/{uid}` presence map, both of which carry
/// [kHeroSkillsField] — lists [skillKey].
///
/// Both shapes are accepted for the same reason [isServiceAllowed]
/// accepts both: dispatch has the presence map in hand and must not
/// spend a Firestore read per hero per booking.
///
/// DEFAULTS TO FALSE, the opposite of [isServiceAllowed], and the
/// asymmetry is deliberate. serviceAccess answers "should this hero be
/// BLOCKED from work they'd otherwise get", so absence must mean allowed
/// or deploying it would strip the live fleet. This answers "is this
/// hero QUALIFIED for a trade", where absence means unqualified —
/// pinging a plumbing job to every hero who has no skills recorded is
/// precisely the indiscriminate fan-out this replaces.
bool heroHasSkill(Object? heroData, String skillKey) {
  if (heroData is! Map) return false;
  final raw = heroData[kHeroSkillsField];
  if (raw is! List) return false;
  final target = skillKey.trim().toLowerCase();
  for (final entry in raw) {
    if (entry is String && entry.trim().toLowerCase() == target) return true;
  }
  return false;
}

/// Skill keys recorded on [heroData], for display.
List<String> heroSkillsOf(Object? heroData) {
  if (heroData is! Map) return const [];
  final raw = heroData[kHeroSkillsField];
  if (raw is! List) return const [];
  return raw
      .whereType<String>()
      .map((s) => s.trim().toLowerCase())
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
}

/// The `serviceAccess` map written for a newly registered skill hero.
///
/// EVERY bucket, including electronics_service, is an explicit `false`.
///
/// That is load-bearing. hero_service_access's [isServiceAllowed] treats
/// a MISSING key as allowed — correct for existing heroes, but it means
/// a skill hero with no map at all would receive food, grocery,
/// custom-order and hero-booking pings from the day they were approved.
/// Writing the denials at registration time is what keeps an
/// electrician's phone showing only electrical work, without one line
/// of dispatch logic changing.
///
/// electronics_service being FALSE here (not true — corrected after a
/// re-audit found the bug this comment used to gloss over) needs its
/// own explanation, because `electronics_service` is not exclusive to
/// skill bookings: Mobile Hub repairs and "sell your phone" enquiries
/// (mobile_service_sheet.dart, sell_your_phone_sheet.dart) create the
/// SAME requestType with no trade attached. This bucket therefore means
/// "wants generic NJ Tech/Mobile Hub work", which a plumber does not.
/// The bucket being false does NOT block a skill hero's own trade jobs —
/// _broadcastToEligibleHeroes checks [heroHasSkill] first for any
/// request that carries a requiredSkill, and that check is authoritative
/// on its own; this bucket is only ever consulted for a request with NO
/// trade attached. Admin can still flip it on for a specific hero from
/// hero_service_access_sheet if that hero genuinely also wants generic
/// electronics jobs — this is a starting position, not a lock.
///
/// Also called for 'emergency_manpower' heroes (Aug 29 2026) — a
/// second, unrelated caller with the same requirement: "deny every
/// ordinary job bucket". Emergency responders aren't a trade and have
/// no skills array, but they need the identical all-off starting
/// position, and this map already is that. See
/// hero_register_screen.dart's isEmergencyOnly for why.
Map<String, bool> skillHeroServiceAccess() => <String, bool>{
      HeroServiceKeys.ride: false,
      HeroServiceKeys.parcel: false,
      HeroServiceKeys.heroBooking: false,
      HeroServiceKeys.foodOrder: false,
      HeroServiceKeys.groceryOrder: false,
      HeroServiceKeys.customOrder: false,
      HeroServiceKeys.electronicsService: false,
    };
