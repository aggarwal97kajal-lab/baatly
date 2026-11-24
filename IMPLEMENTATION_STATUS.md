# BAATLY — Implementation Status

_Last updated: 2026-11-24_

## Milestone 1 — Project setup, design system, branding (IN PROGRESS)

| Area | Status | Notes |
|---|---|---|
| Brand: logo (concept 01, "Do Bubble B"), Mitti palette | ✅ Approved | Assets in `assets/brand`, launcher icons in `android_overrides/` |
| Design tokens (light + dark) | ✅ Done | `lib/theme/` |
| Onboarding screens (splash → permissions) | ✅ UI done | OTP is **demo only** — no SMS |
| Home shell + 5 tabs | ✅ UI done | Community tab is a placeholder |
| Chat list (search, filters, pin/mute/archive) | ✅ Works locally | In-memory only |
| Chat screen (send, ticks, typing, reply, react, delete) | ✅ Works locally | Delivery/read/reply are **simulated** |
| Status view + text status | ✅ Works locally | |
| Calls history + call screen | 🟡 Visual only | No audio/video |
| Wallpapers (6) + theme switcher | ✅ Done | |
| CI: APK build + GitHub Release | ✅ Set up | `.github/workflows/build-apk.yml` |
| Tests | 🟡 Basic | 1 widget test, 1 state test |
| State management | 🟡 `ChangeNotifier` | Move to Riverpod + GoRouter in Milestone 2 when real data arrives |
| iOS build | ❌ Not started | Needs Mac + Apple Developer account ($99/yr) |

### Not production-ready
This is a **demo build**. Nothing is sent over the network. There is **no end-to-end encryption yet** — the app
does not claim it is active; screens mention it as coming in a later milestone.

## Next — Milestone 2: Authentication, profiles, device sessions
Needs from the founder:
- Firebase project (free Spark plan is enough to start) → `google-services.json`
- Decision on backend hosting (NestJS + PostgreSQL + Redis); cheapest start ≈ ₹0–1,500/month
- Commit the `android/` folder at that point (Firebase needs native config)

Milestones 3–10: see master prompt.
