# Function Alignment Audit Report

- Scope: full codebase (excluding generated/vendor bundles), graph used as reference only
- Inventory source: static symbol extraction + analyzer/build diagnostics
- Generated: 2026-05-01T14:49:07.707102Z

## 1) Complete Function Inventory Status
- Total functions discovered: **3357**
- Working: **3335**
- Misaligned: **22**

### By Language
| Language | Total | Misaligned | Working |
|---|---:|---:|---:|
| dart | 3335 | 22 | 3313 |
| java | 1 | 0 | 1 |
| js | 16 | 0 | 16 |
| py | 1 | 0 | 1 |
| swift | 3 | 0 | 3 |
| ts | 1 | 0 | 1 |

## 2) Misaligned Functions (Detailed)
| Function | File | Line | Primary Issues |
|---|---|---:|---|
| `if` | `lib/services/task_service.dart` | 28 | alignment_audit:MISMATCH |
| `if` | `lib/services/task_service.dart` | 41 | alignment_audit:MISMATCH |
| `if` | `lib/services/task_service.dart` | 54 | alignment_audit:MISMATCH |
| `if` | `lib/services/task_service.dart` | 74 | alignment_audit:MISMATCH |
| `if` | `lib/services/task_service.dart` | 139 | alignment_audit:MISMATCH |
| `if` | `lib/services/task_service.dart` | 166 | alignment_audit:MISMATCH |
| `if` | `lib/services/task_service.dart` | 179 | alignment_audit:MISMATCH |
| `if` | `lib/services/task_service.dart` | 194 | alignment_audit:MISMATCH |
| `if` | `lib/services/task_service.dart` | 204 | alignment_audit:MISMATCH |
| `getPendingCompletions` | `lib/services/task_service.dart` | 239 | alignment_audit:MISMATCH |
| `getVerifiedCompletions` | `lib/services/task_service.dart` | 262 | alignment_audit:MISMATCH |
| `getUserWallet` | `lib/services/wallet_service.dart` | 18 | alignment_audit:MISMATCH |
| `if` | `lib/services/wallet_service.dart` | 21 | alignment_audit:MISMATCH |
| `if` | `lib/services/wallet_service.dart` | 27 | alignment_audit:MISMATCH |
| `if` | `lib/services/wallet_service.dart` | 46 | alignment_audit:MISMATCH |
| `if` | `lib/services/wallet_service.dart` | 63 | alignment_audit:MISMATCH |
| `if` | `lib/services/wallet_service.dart` | 115 | alignment_audit:MISMATCH |
| `if` | `lib/services/wallet_service.dart` | 132 | alignment_audit:MISMATCH |
| `checkDailyLimit` | `lib/services/wallet_service.dart` | 178 | alignment_audit:MISMATCH |
| `if` | `lib/services/wallet_service.dart` | 181 | alignment_audit:MISMATCH |
| `if` | `lib/services/wallet_service.dart` | 232 | alignment_audit:MISMATCH |
| `if` | `lib/services/wallet_service.dart` | 277 | alignment_audit:MISMATCH |

## 3) Expected vs Actual Tool Names
| Tool Name | Expected (`functions/index.ts`) | Actual (`functions/index.js`) | Actual (`functions/lib/index.js`) | Recommendation |
|---|---|---|---|---|
| `affiliatePostbackWebhook` | Yes | No | Yes | Align exports across entrypoints |
| `checkDeviceFingerprint` | Yes | No | Yes | Align exports across entrypoints |
| `manageHeroApproval` | Yes | Yes | Yes | Align exports across entrypoints |
| `registerDevice` | No | No | No | Export from index.ts only if callable is required |
| `verifyAndProcessPayment` | Yes | No | Yes | Align exports across entrypoints |

## 4) Priority Ranking of Fixes
### P0 (4 items)
- `functions/checkDeviceFingerprint.ts`: build-breaking: functions.https/logger unresolved -> Switch import to firebase-functions and type callable context.
- `lib/services/wallet_service.dart`: security parity gap vs server-enforced daily limit logic -> Enable FirebaseFunctions callable path and keep simulation only behind debug flag.
- `lib/services/task_service.dart`: anti-fraud controls diverge from backend callable behavior -> Replace local check with cloud callable invocation and fallback policy.
- `functions/tsconfig.json`: Request/Response members unresolved in onRequest handlers -> Remove `types: []` or include required type packages explicitly.
### P1 (2 items)
- `functions/index.js`: deployment/operator confusion, local invoke mismatch risk -> Regenerate or remove stale root index.js; use functions/lib/index.js from tsc output.
- `functions/index.ts`: function unreachable from deployed entrypoint -> Add `export { registerDevice } from './checkDeviceFingerprint';` if required by app flow.
### P2 (0 items)
- None

## 5) Remediation Plan
1. Stabilize build/lint toolchain in `functions/` (fix module deps, tsconfig ambient types).
2. Fix namespace mismatch in `checkDeviceFingerprint.ts` (`firebase-functions` import + callable context typing).
3. Align callable export surface (`functions/index.ts`, `functions/index.js`, `functions/lib/index.js`).
4. Wire Flutter service calls to callable functions for `verifyAndProcessPayment` and `checkDeviceFingerprint` behind rollout flag.
5. Re-run verification gates: `npm run build`, `npm run lint`, `flutter analyze`, callable smoke tests.
6. After fixes, run `python -m graphify update .` to refresh graph outputs without changing graph structure design.

## External Integrations Covered
- Firebase Auth / Firestore / Realtime DB usage in Dart services
- Firebase Cloud Functions TypeScript and compiled JS entrypoints
- Groq/OpenAI-compatible chat endpoint integration in `AIService`
- Python utility scripts (`main.py`, `fix_booking.py`) syntax check