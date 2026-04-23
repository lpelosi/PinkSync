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
│   ├── Game.swift           # Game with score, result, sync status
│   ├── Player.swift         # Player with computed season aggregates
│   ├── GamePlayerStats.swift # Per-game skater stats (shots, goals, assists, etc.)
│   ├── GameGoalieStats.swift # Per-game goalie stats (SA, GA, result)
│   ├── ShootoutRound.swift  # Individual shootout round tracking
│   ├── GameResult.swift     # W/L/OTL/SOW/SOL enum
│   ├── Position.swift       # Player position enum
│   ├── Team.swift           # Team model (Frozen Flamingos)
│   └── OpponentTeam.swift   # Persisted opponent teams with logos
├── Views/
│   ├── MainTabView.swift    # Tab navigation (Games, Roster, History, Stats)
│   ├── Games/               # Game creation, stat entry, summaries
│   │   ├── GamesListView.swift
│   │   ├── GameFormView.swift      # New game with opponent picker + goalie selection
│   │   ├── GameDetailView.swift    # Stat entry hub + Save & Send
│   │   ├── PlayerStatsView.swift   # Big +/- buttons for skater stats
│   │   ├── GoalieStatsView.swift   # Goalie stat entry + result picker
│   │   ├── ShootoutView.swift      # Round-by-round shootout tracker
│   │   └── GameSummaryView.swift   # Full game summary
│   ├── Roster/              # Player list, detail, add/edit
│   ├── History/             # Past matchups with team filter
│   ├── Stats/               # Season stat tables
│   └── Components/          # Reusable UI (StatButton, PlayerRow)
├── Theme/
│   └── AppTheme.swift       # Pink color scheme, fonts, button styles
├── Utilities/
│   ├── APIClient.swift      # HTTP client for backend communication
│   ├── RosterSeeder.swift   # Seeds roster + opponent teams on first launch
│   ├── Secrets.swift        # API key + base URL (gitignored)
│   └── Secrets.example.swift # Template for Secrets.swift (committed)
├── Assets.xcassets/         # App icon, team logo, opponent logos
└── PinkSyncApp.swift        # App entry point with SwiftData container
```

## App Features

### Game Workflow
1. **Create a game** — pick an opponent (from saved teams or type a new one), set the date, location, and starting goalie
2. **Record stats** — tap a player, use large +/- buttons to increment shots, goals, assists, hits, blocks, PIMs
3. **Goalie stats** — record shots against, goals against, set result, track shootout rounds
4. **Review** — view the game summary with all player and goalie stats
5. **Save & Send** — submits the game to the backend API, which updates the website automatically
6. **Edit & re-send** — fix errors after sending; the API upserts by date + opponent

### Tabs
- **Games** — active games list, create new games, enter stats
- **Roster** — full team roster, add/edit/remove players
- **History** — completed games with team filter (logos in filter chips), tap for game summary
- **Stats** — season aggregate tables for skaters and goalies

### Opponent Teams
- 6 teams are pre-seeded with logos (Orlando Kraken, Warriors, Dangleberry Puckhounds, Whiskey Tangos, Otterhawks, Frozen Flamingos)
- Custom teams can be added during game creation with an optional photo from your library
- Saved teams persist and appear in the picker for future games
- Team logos are automatically uploaded to the website when a game is synced via Save & Send

### Data Persistence
All data is stored locally using SwiftData. The app works fully offline — syncing to the website is triggered manually via "Save & Send."

## Backend Setup

The app communicates with an Express.js API server. The server code lives in the website repository.

### API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/game-stats` | Submit or update game stats (write key required) |
| `POST` | `/api/team-logo` | Upload an opponent team logo (write key required) |
| `GET` | `/api/team-logos` | Map of uploaded team logos (read key accepted) |
| `GET` | `/api/stats` | Aggregated season stats (read key accepted) |
| `GET` | `/api/games` | All raw game data (read key accepted) |

### Server Configuration

The server requires two environment variables:

```bash
PINKSYNC_API_KEY=<write-key>    # Used by the iOS app for POST requests
PINKSYNC_READ_KEY=<read-key>    # Used by the website frontend for GET requests
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

- **API key authentication** on all `/api` routes with timing-safe comparison
- **Separate read/write keys** — the public frontend only has the read key; write access requires the iOS app's key
- **Rate limiting** — 100 reads / 10 writes per 15-minute window per IP
- **Localhost binding** — Express only listens on `127.0.0.1`, all external traffic must go through the reverse proxy (HTTPS)
- **CORS restricted** to the production domain
- **Secrets.swift is gitignored** — API keys never enter version control

## Pre-seeded Roster

The app seeds 27 Frozen Flamingos players on first launch, including 4 goalies (3 of which are dual-role skater/goalies). The roster can be edited in-app after launch.

## Deleting Games

- Games that have **not been synced** to the website can be deleted via swipe-to-delete with a confirmation dialog
- Games that have been **synced** (Save & Send completed) cannot be deleted from the app — this preserves the website's data integrity
