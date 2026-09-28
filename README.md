# PinkSync

An iOS/iPad app for collecting hockey stats during live games, built for the Frozen Flamingos hockey team. Stats are recorded in real-time and synced to the team website via a backend API.

## Requirements

- Xcode 16+
- iOS 18+ / iPadOS 18+
- Swift 6
- A running backend server (see [Backend Setup](#backend-setup))

## Getting Started

### 1. Clone the repo

```bash
git clone https://github.com/lpelosi/PinkSync.git
cd PinkSync
```

### 2. Configure secrets

The app requires an API key and server URL to communicate with the backend. These are stored in a file that is **not committed to the repo**.

```bash
cp Secrets.example.swift PinkSync/Utilities/Secrets.swift
```

Open `PinkSync/Utilities/Secrets.swift` and fill in your values:

```swift
enum Secrets {
    static let apiKey = "your-api-key-here"
    static let baseURL = "https://your-domain.com"
}
```

The `apiKey` must match the `PINKSYNC_API_KEY` environment variable on your server. The `baseURL` is the root URL of your website (no trailing slash).

### 3. Open and build

```bash
open PinkSync.xcodeproj
```

Select your target device or simulator and build (Cmd+B). No third-party dependencies are required — the app uses only SwiftUI and SwiftData.

## Project Structure

```
PinkSync/
├── Models/                  # SwiftData models
│   ├── Game.swift           # Game with score, result, sync status, scheduleId
│   ├── Player.swift         # Player with computed season aggregates
│   ├── GamePlayerStats.swift # Per-game skater stats (shots, goals, assists, +/-, PPG, SHG, PPA, SHA, GWG, TOI, etc.)
│   ├── GameGoalieStats.swift # Per-game goalie stats (SA, GA, result)
│   ├── GameEvent.swift      # Per-action event model (period, clock time, PP/SH flags)
│   ├── PlayerShift.swift    # Individual shift records (period, duration, start/end clock times)
│   ├── ShootoutRound.swift  # Individual shootout round tracking
│   ├── GameResult.swift     # W/L/OTL/SOW/SOL enum
│   ├── Position.swift       # Player position enum (C, LW, RW, LD, RD, Goalie)
│   ├── Team.swift           # Team model (Frozen Flamingos)
│   ├── OpponentTeam.swift   # Persisted opponent teams with logos
│   └── AuthUser.swift       # User model for JWT auth
├── Views/
│   ├── MainTabView.swift    # Tab navigation (Games, Roster, History, Stats)
│   ├── Games/               # Game creation, stat entry, summaries
│   │   ├── GamesListView.swift     # Games list + schedule integration
│   │   ├── GameFormView.swift      # New game with opponent picker + goalie selection
│   │   ├── GameDetailView.swift    # Stat entry hub + Save & Send
│   │   ├── PlayerStatsView.swift   # Big +/- buttons for skater stats
│   │   ├── GoalieStatsView.swift   # Goalie stat entry + result picker
│   │   ├── ShootoutView.swift      # Round-by-round shootout tracker
│   │   ├── GameSummaryView.swift   # Full game summary with per-period breakdown
│   │   ├── GameStatsEditorView.swift # Manual stat editing
│   │   ├── GameEventEditorView.swift # Edit an individual play (player/assists/time/type)
│   │   ├── MvpVoteView.swift       # Admin MVP voting (open/close/live tallies)
│   │   └── ScheduleFormView.swift  # Schedule bout creation
│   │   └── LiveGame/               # Real-time stat tracking
│   │       ├── LiveGameView.swift          # Live game UI with scoreboard + event feed
│   │       ├── LiveGameViewModel.swift     # Game state, clock, penalties, event recording
│   │       ├── LineupCheckInView.swift     # Pre-game player check-in
│   │       ├── PenaltyEntryView.swift      # Penalty type + time entry
│   │       └── LivePlayerPickerView.swift  # Player selection during live game
│   ├── Roster/              # Player list, detail, add/edit
│   ├── History/             # Past matchups with team filter
│   ├── Stats/               # Season stat tables
│   ├── Auth/                # Login + profile views
│   ├── Admin/               # User management (role-gated)
│   └── Components/          # Reusable UI (StatButton, PlayerRow, ClockTimeField, CachedPlayerPhoto)
├── Theme/
│   └── AppTheme.swift       # Pink color scheme, fonts, button styles
├── Utilities/
│   ├── APIClient.swift      # HTTP client for backend communication
│   ├── AuthManager.swift    # JWT auth + role-based access control
│   ├── SyncManager.swift    # Background retry of failed sends + network reachability
│   ├── PhotoCache.swift     # Two-tier (memory + disk) player photo cache
│   ├── RosterSeeder.swift   # Seeds roster + opponent teams on first launch
│   ├── KeychainHelper.swift # Secure token storage
│   └── Secrets.swift        # API key + base URL (gitignored)
├── Assets.xcassets/         # App icon, team logo, opponent logos (7 teams)
└── PinkSyncApp.swift        # App entry point with SwiftData container
```

`Secrets.example.swift` lives at the repo root (committed) and is copied into `PinkSync/Utilities/Secrets.swift` during setup.

## App Features

### Game Workflow
1. **Create a game** — pick an opponent (from saved teams or type a new one), set the date, location, and starting goalie. Games can also be created directly from scheduled bouts.
2. **Go Live** — check in players, then record stats in real-time with the live game mode
3. **Live stat tracking** — tap players to record shots, goals (with assists), hits, blocks, penalties. All events are timestamped with the game clock and tagged with the current period. On-ice players appear first for quick selection, with an expandable bench section for all enrolled players.
4. **Game clock + penalty clock** — configurable period length, running clock with start/stop/edit, automatic penalty countdown timers with support for concurrent penalties (5-on-3)
5. **Auto PP/SH detection** — goals scored during a power play or shorthanded situation are automatically flagged. Power play goals clear the opposing team's shortest minor penalty (NHL rules).
6. **Per-period tracking** — "End Period" buttons advance through 1st → 2nd → 3rd → OT → SO. All stats are recorded per-period with optional clock time for goals and penalties. Every period change can be reversed with a **Go back** button (clock, penalty timers and period restored, plays untouched), and the clock sheet has a period picker for setting 1st / 2nd / 3rd / OT directly.
7. **Edit plays** — tap any event in the live feed to edit it (change player, assists, time, type). Undo support for all actions, period changes, goalie changes, lineup changes and shootout attempts. Goalie can be changed mid-game (relief goalie), and players can be added to or removed from the lineup after the game has started.
7a. **Leave and resume, reopen** — the live session (period, clock, penalty timers, lineup, on-ice, shifts, shootout, feed) is written to disk after every change. The live screen can be closed and resumed, survives a crash, and an ended game can be reopened for corrections and ended again. Shootout attempts can be re-assigned to another shooter, flipped between goal and miss/save, or removed; score, round numbers and whose turn it is are re-derived. Both sides' shootout buttons are always live, since the opponent sometimes shoots first.
8. **Goalie stats** — shots against, goals against, result, shootout rounds
9. **Line management** — assign players to lines with game positions (C, LW, RW, LD, RD). Supports rolling lines where unassigned players stay on ice during line changes. Faceoffs default to the on-ice center for quick recording, with other players available below.
10. **Lineup management** — set the game lineup before going live. Only enrolled players appear in the skaters list. Players can be added or removed via the lineup picker; the "Go Live" check-in pre-selects the existing lineup.
11. **Review** — game summary with per-period scoring grid, shots by period, goal/penalty detail logs, and full skater/goalie stat tables. Only enrolled players are shown (not the full roster). Tap any skater to see a per-shift breakdown with individual shift durations and per-period totals.
12. **Save & Send** — submits the game to the backend API, which updates the website automatically
13. **Edit & re-send** — fix errors after sending; the API upserts by gameId
14. **Reset to Bout** — clears all stats and events for a game and returns it to the schedule as an upcoming bout (admin only, games linked to a schedule entry)
15. **MVP Voting management** — for synced games, admins can open, close, or reopen MVP voting from the app. The MVP Voting view shows the current status, total ballots cast, live per-player tallies (e.g., `Sela 'Tequila' Dieden — 5 Votes`), and the final winner once voting closes. Tallies auto-refresh every 2 seconds while voting is open (every 30 seconds when closed).

### Stat Tracking (NHL-aligned)
- **Skaters**: GP, G, A, P, +/-, PPG, PPA, SHG, SHA, GWG, PIM, Shots, Hits, Blocks, FO W/L, TOI
- **Goalies**: GP, W, L, OTL, SOW, SOL, SA, GA, GAA, SV%
- **+/- (Plus/Minus)** — auto-tracked on even-strength and short-handed goals per NHL rules (not power play goals). Visible only to admins in the app; data stored server-side but not displayed on the website.
- **TOI (Time On Ice)** — per-shift tracking synced to the game clock. Individual shifts are recorded with start/end clock times and duration. Total TOI and average shift length are computed per game.
- **Per-shift tracking** — each player's shifts are stored as individual records with period, duration, and clock times. Shift data is sent to the server for future analytics.
- **GWG** (Game Winning Goal) is auto-computed from event history
- **PPA/SHA** (Power Play Assists / Short-Handed Assists) are auto-tracked during goal recording

### Schedule Integration
- Bouts are scheduled on the website and synced to the app
- Tapping a scheduled bout creates a game pre-filled with opponent, date, and location
- Games are linked to their schedule entry via `scheduleId` — completed games are automatically filtered out of the "Upcoming" section
- Bouts carry a Home/Away flag (`isHome`); away bouts show as "@ Opponent"
- Schedule management is role-gated (schedule_manager or admin)

### Seasons
- Seasons come from `GET /api/seasons` (a labelled date range each, one flagged current, optionally with a `playoffsStart` day). Nothing is stamped onto games — the app classifies a game by its date the same way the server does, so a game posted with no season field lands in the right season on both sides.
- The Games, Roster and Stats tabs each have a season picker, defaulting to the current season, with an "All Seasons" option.
- Stats are scoped to regular season by default (matching the site's leader cards), with Playoffs and All Games toggles. A player's detail page has the same season picker.
- Roster membership per season is the server's `seasons` array on each player. The player form has a toggle per season; a new player joins the current season. A player with no membership set belongs to every season, as on the server.
- Roster edits go through a read-modify-write of `/api/roster/raw`, so one player's save never disturbs anyone else's season membership or stored photo path.
- **Local fixes are never overwritten.** A game edited on this device after sending (post-game edits, manual stat edits, score/result or goalie changes, lineup changes, reopening, live scoring) is marked as having local edits. Games-tab refresh leaves it alone until it is sent again, and the games list shows an orange icon on it instead of the green check.
- Sync always pulls every season (`?season=all`) for games, roster and scheduled bouts, so archived games and past players stay on the device; the pickers do the narrowing.
- Game dates are sent with the device's UTC offset (e.g. `2026-08-14T21:30:00-04:00`), so an evening game stays on the calendar day it was played when the server classifies it by season and playoffs. Games sent before this update keep their UTC timestamp until they are next re-sent.
- **Franchise Records** (Stats tab) shows the all-time record book from `GET /api/records`.
- **Admin → Seasons & Playoffs** starts a new season, flags the playoffs (one tap: "Start Playoffs Today"), edits dates, or makes a season current — all through `PUT /api/seasons`.

### Live Score
- While a game is live, the app pushes the scoreboard (score, shots, period, clock) to `PUT /api/live` at most every 5 seconds and on every play. The website shows it as a banner. Ending the game takes it down; the server also expires it after four hours.
- **On-ice for goals.** Goal entry, goal-against entry, the live feed editor and Edit Events all share an On Ice picker (`OnIcePicker`). It is pre-filled with the recorded or current skaters, keeps the scorer and assists locked on, and moves +/- when changed. Goals against are editable after the game (time, power play, on ice), and Edit Events lists who was on for each goal.
- Goalie decisions follow hockey's goalie-of-record rule: on a win the goalie in net for the winning goal, on a loss the goalie who allowed the deciding goal against, in a shootout the goalie who faced it. Other goalies who played get no decision. Goalie changes are stored as `goalieChange` events, and shots against carry the goalie's id.

### Tests
- `PinkSyncTests` (unit tests, run with ⌘U or `xcodebuild test -scheme PinkSync -destination 'platform=iOS Simulator,name=iPhone 17'`) cover season classification, stat scoping, shootout recomputation, period go-back, live session resume/reopen, and goalie of record. They use an in-memory SwiftData container and never touch the network.

### Player Photos
- Photos are synced from the server during roster sync (pull-to-refresh on the Roster tab)
- The server resolves photos by checking `jerseyDisplay` first, then `number`, against `png`/`jpg`/`jpeg` extensions, with `default.jpg` as a final fallback
- Photos uploaded via the app are stored by playerId and take priority over number-based photos
- The server appends a `?v=<mtime>` cache-busting query string so re-uploaded photos invalidate automatically on every client
- **`PhotoCache`** — a two-tier (in-memory `NSCache` + on-disk) actor-based cache. Photos are keyed by SHA-256 of their full URL so cache busting is automatic. In-flight requests for the same URL are coalesced into a single network call.
- **`CachedPlayerPhoto`** — drop-in SwiftUI view used by `PlayerRow`, `PlayerDetailView`, and `PlayerFormView` to display cached photos with a `person.circle.fill` fallback

### Tabs
- **Games** — upcoming bouts, active games, create new games, live stat tracking
- **Roster** — full team roster with player photos, add/edit/remove players, position management (C, LW, RW, LD, RD, Goalie)
- **History** — completed games with team filter (logos in filter chips), tap for game summary
- **Stats** — per-season aggregate tables for skaters and goalies with sortable columns (including jersey number), a regular season / playoffs / all games toggle, a **Pick specific games** filter within that season, and a link to Franchise Records. Players who also play goal appear in both tables. +/- column is visible only to admins.

### Opponent Teams
- 7 teams are pre-seeded with logos (Orlando Kraken, Warriors, Wolves, Dangleberry Puckhounds, Whiskey Tangos, Otterhawks, District 5) plus Frozen Flamingos
- Custom teams can be added during game creation with an optional photo from your library
- Saved teams persist and appear in the picker for future games
- Team logos are automatically uploaded to the website when a game is synced via Save & Send

### Authentication & Roles
- Sign in with Apple authentication
- JWT-based auth with role-gated access (player, roster_manager, photographer, schedule_manager, admin)
- Admin panel for user management

### Data Persistence
All data is stored locally using SwiftData. The app works fully offline — syncing to the website is triggered manually via "Save & Send."

### Background Sync & Offline Resilience
- `SyncManager` watches network reachability with `NWPathMonitor` and surfaces an online/offline indicator
- Games whose `Save & Send` fails are marked `pendingSync` and retried automatically:
  - Every 60 seconds while online
  - As soon as the device comes back online after losing connectivity
  - When the app returns to the foreground (`scenePhase` change to `.active`)
- The pending-send count is exposed for UI indicators; the last sync error is stored per game for display

### Server-side Backups
The backend automatically backs up `games.json`, `schedule.json`, and `roster.json` to `data/backups/` before every write, keeping the 20 most recent copies per file.

## Backend Setup

The app communicates with an Express.js API server. The server code lives in the website repository.

### API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/game-stats` | Submit or update game stats (admin) |
| `DELETE`| `/api/game/:gameId` | Delete a game (admin) |
| `GET` | `/api/games` | Raw game data; `?season=<id>\|all` (default: current season), `?type=regular\|playoff\|all` (default: all) |
| `GET` | `/api/stats` | Aggregated stats (read key); same `?season=`, `?type=` defaults to `regular` |
| `GET` | `/api/seasons` | Season list, oldest first, with `isCurrent` resolved and any `playoffsStart` |
| `PUT` | `/api/seasons` | Replace the season list — Admin tab: new season, start playoffs, fix dates (admin) |
| `PUT` | `/api/live` | Push the live scoreboard while scoring (admin); `DELETE /api/live?gameId=` takes it down |
| `GET` | `/api/records` | All-time franchise records: single season, single game, career, playoffs |
| `GET` | `/api/roster` | Roster with resolved photo paths; `?season=<id>\|all` (default: current season) |
| `GET` | `/api/roster/raw` | Roster exactly as stored, no photo resolution or season filter (roster_manager/admin) — the app reads this before every roster write |
| `PUT` | `/api/roster` | Replace full roster; each player may carry a `seasons` array of season ids (roster_manager/admin) |
| `POST` | `/api/player-photo` | Upload a player photo (photographer/admin) |
| `POST` | `/api/team-logo` | Upload an opponent team logo (admin) |
| `GET` | `/api/team-logos` | Map of uploaded team logos (read key) |
| `GET` | `/api/schedule` | Scheduled bouts; same `?season=` / `?type=` handling as `/api/games` |
| `POST` | `/api/schedule` | Add a schedule entry, optional `isHome` boolean (schedule_manager/admin) |
| `DELETE`| `/api/schedule/:id` | Remove a schedule entry (schedule_manager/admin) |
| `GET` | `/api/games/:gameId/mvp-vote` | Admin MVP vote summary with individual ballots (admin) |
| `GET` | `/api/games/:gameId/mvp-vote-status` | Public MVP vote summary (read key) |
| `POST` | `/api/games/:gameId/mvp-vote-open` | Open or reopen MVP voting (admin) |
| `POST` | `/api/games/:gameId/mvp-vote-close` | Close active MVP voting (admin) |

### Server Configuration

The server requires the following environment variables:

```bash
PINKSYNC_API_KEY=<write-key>      # Used by the iOS app for POST requests
PINKSYNC_READ_KEY=<read-key>      # Used by the website frontend for GET requests
JWT_SECRET=<jwt-secret>           # Used for JWT authentication
APPLE_TEAM_ID=<team-id>           # Apple Developer Team ID for Sign in with Apple
APPLE_SERVICE_ID=<service-id>     # Apple Service ID for web auth
```

Generate keys with:
```bash
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

### Running with PM2

```bash
PINKSYNC_API_KEY=your_write_key PINKSYNC_READ_KEY=your_read_key pm2 start server.js --name pinksync-api
```

### Apache Reverse Proxy

If using Apache as a reverse proxy (the server binds to `127.0.0.1:3001`):

```apache
<Location /api>
    ProxyPass http://127.0.0.1:3001/api
    ProxyPassReverse http://127.0.0.1:3001/api
</Location>
```

Requires `mod_proxy` and `mod_proxy_http` enabled.

## Security

- **JWT authentication** with Sign in with Apple for user identity
- **Role-based access control** — player, roster_manager, photographer, schedule_manager, admin
- **API key authentication** on all `/api` routes with timing-safe comparison
- **Separate read/write keys** — the public frontend only has the read key; write access requires the iOS app's key
- **Rate limiting** — 100 reads / 10 writes per 15-minute window per IP
- **Localhost binding** — Express only listens on `127.0.0.1`, all external traffic must go through the reverse proxy (HTTPS)
- **CORS restricted** to the production domain
- **Secrets.swift is gitignored** — API keys never enter version control
- **Keychain storage** for auth tokens on device

## Pre-seeded Roster

The app seeds 27 Frozen Flamingos players on first launch, including 4 goalies (3 of which are dual-role skater/goalies). The roster can be edited in-app after launch.

## Managing Games

- Games can be deleted via swipe-to-delete with a confirmation dialog
- Synced games are also deleted from the server when removed from the app (admin role required)
- Games linked to a scheduled bout can be reset via "Reset to Bout" — this clears all stats, events, and shifts, removes the game from the server if synced, and returns the schedule entry to the upcoming bouts list
