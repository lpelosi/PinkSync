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
│   ├── GamePlayerStats.swift # Per-game skater stats (shots, goals, assists, PPG, SHG, PPA, SHA, GWG, etc.)
│   ├── GameGoalieStats.swift # Per-game goalie stats (SA, GA, result)
│   ├── GameEvent.swift      # Per-action event model (period, clock time, PP/SH flags)
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
│   └── Components/          # Reusable UI (StatButton, PlayerRow, ClockTimeField)
├── Theme/
│   └── AppTheme.swift       # Pink color scheme, fonts, button styles
├── Utilities/
│   ├── APIClient.swift      # HTTP client for backend communication
│   ├── AuthManager.swift    # JWT auth + role-based access control
│   ├── RosterSeeder.swift   # Seeds roster + opponent teams on first launch
│   ├── KeychainHelper.swift # Secure token storage
│   ├── Secrets.swift        # API key + base URL (gitignored)
│   └── Secrets.example.swift # Template for Secrets.swift (committed)
├── Assets.xcassets/         # App icon, team logo, opponent logos (7 teams)
└── PinkSyncApp.swift        # App entry point with SwiftData container
```

## App Features

### Game Workflow
1. **Create a game** — pick an opponent (from saved teams or type a new one), set the date, location, and starting goalie. Games can also be created directly from scheduled bouts.
2. **Go Live** — check in players, then record stats in real-time with the live game mode
3. **Live stat tracking** — tap players to record shots, goals (with assists), hits, blocks, penalties. All events are timestamped with the game clock and tagged with the current period.
4. **Game clock + penalty clock** — configurable period length, running clock with start/stop/edit, automatic penalty countdown timers with support for concurrent penalties (5-on-3)
5. **Auto PP/SH detection** — goals scored during a power play or shorthanded situation are automatically flagged. Power play goals clear the opposing team's shortest minor penalty (NHL rules).
6. **Per-period tracking** — "End Period" buttons advance through 1st → 2nd → 3rd → OT → SO. All stats are recorded per-period with optional clock time for goals and penalties.
7. **Edit plays** — tap any event in the live feed to edit it (change player, assists, time, type). Undo support for all actions.
8. **Goalie stats** — shots against, goals against, result, shootout rounds
9. **Review** — game summary with per-period scoring grid, shots by period, goal/penalty detail logs, and full skater/goalie stat tables
10. **Save & Send** — submits the game to the backend API, which updates the website automatically
11. **Edit & re-send** — fix errors after sending; the API upserts by gameId

### Stat Tracking (NHL-aligned)
- **Skaters**: GP, G, A, P, PPG, PPA, SHG, SHA, GWG, PIM, Shots, Hits, Blocks, FO W/L
- **Goalies**: GP, W, L, OTL, SOW, SOL, SA, GA, GAA, SV%
- **GWG** (Game Winning Goal) is auto-computed from event history
- **PPA/SHA** (Power Play Assists / Short-Handed Assists) are auto-tracked during goal recording

### Schedule Integration
- Bouts are scheduled on the website and synced to the app
- Tapping a scheduled bout creates a game pre-filled with opponent, date, and location
- Games are linked to their schedule entry via `scheduleId` — completed games are automatically filtered out of the "Upcoming" section
- Schedule management is role-gated (schedule_manager or admin)

### Tabs
- **Games** — upcoming bouts, active games, create new games, live stat tracking
- **Roster** — full team roster, add/edit/remove players, position management (C, LW, RW, LD, RD, Goalie)
- **History** — completed games with team filter (logos in filter chips), tap for game summary
- **Stats** — season aggregate tables for skaters and goalies

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

### Server-side Backups
The backend automatically backs up `games.json`, `schedule.json`, and `roster.json` to `data/backups/` before every write, keeping the 20 most recent copies per file.

## Backend Setup

The app communicates with an Express.js API server. The server code lives in the website repository.

### API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/game-stats` | Submit or update game stats (admin) |
| `DELETE`| `/api/game/:gameId` | Delete a game (admin) |
| `GET` | `/api/games` | All raw game data (authenticated) |
| `GET` | `/api/stats` | Aggregated season stats (read key) |
| `GET` | `/api/roster` | Server roster with active status (read key) |
| `POST` | `/api/team-logo` | Upload an opponent team logo (admin) |
| `GET` | `/api/team-logos` | Map of uploaded team logos (read key) |
| `GET` | `/api/schedule` | Scheduled bouts (read key) |
| `POST` | `/api/schedule` | Add a schedule entry (schedule_manager/admin) |
| `DELETE`| `/api/schedule/:id` | Remove a schedule entry (schedule_manager/admin) |

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

## Deleting Games

- Games can be deleted via swipe-to-delete with a confirmation dialog
- Synced games are also deleted from the server when removed from the app (admin role required)
