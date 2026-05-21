# PinkSync — User Guide

A step-by-step guide to using PinkSync on iPad/iPhone during Frozen Flamingos games. For setup and developer info, see [README.md](README.md).

---

## Table of Contents

1. [First Launch & Sign In](#1-first-launch--sign-in)
2. [The Tabs](#2-the-tabs)
3. [Managing the Roster](#3-managing-the-roster)
4. [Scheduling a Bout](#4-scheduling-a-bout)
5. [Creating a Game](#5-creating-a-game)
6. [Setting the Lineup](#6-setting-the-lineup)
7. [Going Live](#7-going-live)
8. [Live Stat Tracking](#8-live-stat-tracking)
9. [Goals, Penalties & Power Plays](#9-goals-penalties--power-plays)
10. [Ending Periods, OT, and Shootouts](#10-ending-periods-ot-and-shootouts)
11. [Reviewing & Editing a Game](#11-reviewing--editing-a-game)
12. [Saving to the Website](#12-saving-to-the-website)
13. [MVP Voting](#13-mvp-voting)
14. [Fixing Mistakes](#14-fixing-mistakes)
15. [Photos](#15-photos)
16. [Roles & Permissions](#16-roles--permissions)
17. [Offline Use](#17-offline-use)

---

## 1. First Launch & Sign In

- Open PinkSync. The launch screen shows the team logo while data loads.
- Tap **Sign in with Apple** on the login screen.
- New users land in the `player` role by default. An admin can promote you (see [Roles & Permissions](#16-roles--permissions)).
- On the first launch the app seeds the full Frozen Flamingos roster (27 players, including 4 goalies) and 7 opponent teams. Edit any of it later from the Roster tab.
- Sign out from the **Profile** tab.

---

## 2. The Tabs

| Tab | What it does |
|-----|--------------|
| **Games** | Upcoming bouts, in-progress games, create new games, go live |
| **Roster** | All players with photos — add, edit, remove, change positions |
| **History** | Completed games, filter by opponent (logo chips), tap for full summary |
| **Stats** | Season totals for skaters and goalies, sortable columns |
| **Admin** | User management — only visible if you have the admin role |
| **Profile** | Account info and sign out |

---

## 3. Managing the Roster

> Requires the `roster_manager` or `admin` role to push changes to the server.

- Open the **Roster** tab.
- **Add a player** — tap the `+` button. Set name, jersey number, position (Forward / Defense / Goalie), and optionally pick a photo from your library.
- **Also plays Goalie** toggle — for skaters who can also play in net (dual-role players). They appear in both skater and goalie pickers.
- **Substitute Player** toggle — marks the player as a sub who doesn't get a permanent jersey number. Subs wear a different number each game; set their tonight number in the **Lineup** picker.
- **Edit a player** — tap a row, then **Edit**.
- **Remove a player** — swipe left on a row.
- **Pull to refresh** — pulls the latest roster (and player photos) from the server.

The active/enrolled flag on a player is managed via roster sync from the server, not via a toggle in the app form.

---

## 4. Scheduling a Bout

> Requires the `schedule_manager` or `admin` role.

- From the **Games** tab, tap the `+` menu and choose **Schedule Bout**.
- Pick opponent, date, time, and location.
- Saved bouts appear in the **Upcoming** section and on the team website.
- Tap a scheduled bout to convert it into a game (see next section). Completed games disappear from Upcoming automatically.

---

## 5. Creating a Game

You can start a game two ways:

**From a scheduled bout:** tap the bout in **Upcoming** → opponent, date, and location come pre-filled.

**Ad hoc:** tap **New Game** in the Games tab.

Fill in:

- **Opponent** — pick from saved teams or type a new one. New opponents can be saved with a logo from your photo library, and will appear in the picker for future games.
- **Date & location**
- **Starting goalie** — required. Pick from any roster player with the Goalie position (including dual-role players).

Tap **Save** to create the game in **Setup** state.

---

## 6. Setting the Lineup

Open the game. If no lineup is set yet, tap **Set Lineup**. If a lineup exists, scroll to the Skaters section and tap **Edit Lineup**.

- Tap a player tile to add them to the lineup; tap again to remove.
- Tap the **#** badge on a tile to set a **per-game jersey number** (overrides the roster number for this game only — useful when a player switches numbers).
- Tap **Add Sub** to create a one-off substitute player with a name and tonight-only number.
- Goalies are managed separately via the **Starting Goalie** picker on the Game Detail screen.

You do not have to do this before going live — the **Go Live** check-in screen will pre-select your existing lineup and let you adjust on the spot.

---

## 7. Going Live

From the Game Detail view, tap **Go Live**.

1. **Check-in screen** — toggle each player who is actually here. Pre-selected from the lineup if you set one.
2. Tap **Start Tracking** to enter the live tracking view.

If a lineup and starting goalie are already in place, **Go Live** opens a confirmation sheet listing the roster with a single **Start Tracking** button (and an **Edit Lineup** shortcut if something is wrong).

The live screen has:

- **Scoreboard** — our score, opponent score, current period, game clock
- **Set Clock** — pick a period length (12 / 15 / 20 / 25 minutes); after that, the same control becomes the **start / pause** for the clock
- **End** — small button on the scoreboard that ends the game (with a confirmation alert)
- **Penalty timers** — live countdowns for each active penalty, both ours and theirs (handles concurrent penalties, e.g. 5-on-3)
- **On Ice section** — players currently on the ice, shown first for quick tapping. **Set Players** lets you toggle who is on the ice.
- **Bench section** — expandable list of checked-in players not currently on the ice
- **Event feed** — chronological list of plays
- **Action buttons** — split into **Us** (Shot, Goal, Hit, Block, Faceoff, Penalty) and **Them** (Shot, Goal, Penalty)
- **Quick repeat** — after recording a shot, hit, or block, a single-tap shortcut appears to repeat the same action for the same player

---

## 8. Live Stat Tracking

The basic flow: **start the clock → tap an action → pick the player(s)**.

- **Shot** — tap **Shot** (under "Us"), pick shooter. Auto-timestamped with the period and clock time.
- **Hit / Block** — same pattern.
- **Faceoff** — tap **Faceoff**, pick the taker, then mark **Won** or **Lost**. For faceoffs the on-ice center is pre-selected; tap to pick a different player.
- **Goal** — see next section.
- **Penalty** — see next section.
- **Opponent stats** — under the "Them" column, **Shot** records a shot against the goalie, **Goal** records a goal against (with optional PP flag and clock time), **Penalty** records an opposing-player penalty by jersey number that runs a power-play clock for our side.

All events are recorded with:

- Period (1 / 2 / 3 / OT / SO)
- Clock time (optional but supported on every event type)
- PP/SH flags (auto-computed from active penalties)

The **Undo** button on the event feed reverses the most recent action. Tapping an event in the feed (or using the **Edit Events** button on Game Detail after the game) opens it for editing or deletion.

### Lines

Assign players to lines with game positions (C, LW, RW, LD, RD). PinkSync supports **rolling lines** — unassigned players stay on the ice during line changes rather than being benched. The line management area lets you swap a whole forward line or defense pairing on at once.

---

## 9. Goals, Penalties & Power Plays

### Recording a goal

1. Tap **Goal**.
2. Pick the scorer.
3. Optionally add 1st assist, 2nd assist.
4. Optionally set the exact clock time.
5. Confirm.

The app automatically:

- Flags it as **PPG / SHG** based on active penalty state at the moment of the goal
- Flags assists as **PPA / SHA** the same way
- Awards **+/-** to all on-ice skaters (even strength and shorthanded goals only — power play goals do not affect +/- per NHL rules)
- Clears the opposing team's **shortest minor penalty** when you score on the power play
- Marks the **Game Winning Goal** retroactively once the game ends, based on the full event history

### Recording a penalty

1. Tap **Penalty**.
2. Pick the penalized player.
3. Pick penalty type and duration (2:00 minor, 4:00 double minor, 5:00 major, etc.).
4. Optionally set the clock time.

The penalty timer starts running with the game clock. Concurrent penalties stack — the on-ice strength indicator updates to reflect 5-on-4, 5-on-3, 4-on-4, etc.

---

## 10. Ending Periods, OT, and Shootouts

A single period-transition button at the bottom of the live screen advances the game. Its label changes based on where you are:

- **End 1st Period** → **End 2nd Period** → **End 3rd Period** — between regulation periods, the clock resets to the configured period length and any leftover penalty time carries over.
- **Going to Overtime** — appears after the 3rd period if you need OT. Sets the clock to 5:00 and switches the period label to OT.
- **Going to Shootout** — appears after OT. Switches to the Shootout view.

### Shootout

- The Shootout view records each round separately, alternating **Our Shot** and **Their Shot**.
- For our shots: pick the shooter, then tap **Goal** or **Miss**.
- For their shots: tap **Goal** or **Save** (save credits the active goalie).
- Each shootout goal counts toward `goalsFor` / `goalsAgainst` on the scoresheet (note: this differs from official NHL stats, which only count the deciding goal).
- Shootout rounds are stored individually for the goalie's record.

### Ending the game

Tap the small **End** button on the scoreboard, then confirm in the **End Game?** alert. The app automatically:

- Sets the result (W / L / OTL / SOW / SOL) based on which period you ended in and the score
- Closes all open shifts and persists TOI for every checked-in player
- Awards the **Game Winning Goal** retroactively (regulation/OT wins only)
- Marks the game **Complete**

---

## 11. Reviewing & Editing a Game

From the game's detail view, tap **Game Summary** to see:

- Per-period scoring grid
- Shots by period
- Goal log with scorer, assists, time
- Penalty log
- Full skater stat table (G, A, P, +/-, PPG, SHG, GWG, PIM, Shots, Hits, Blocks, FO W/L, TOI)
- Goalie stat table (SA, GA, GAA, SV%, result)

Tap any **skater row** to drill into their **per-shift breakdown** — each individual shift with start/end clock times, duration, and per-period totals (average shift length included).

### Editing plays after the fact

- **Tap any event in the live feed** during the game to open the event editor. Change the player, assists, time, period, or related fields.
- After the game, from Game Detail, tap **Edit Events** to open the same editor for the full event log.
- **Manual stat edit** — from Game Detail, tap **Edit Stats** for direct edits to skater/goalie totals (use sparingly; the event log is the source of truth for derived stats).

---

## 12. Saving to the Website

From the completed game's detail view, tap **Save & Send**.

- Submits the game (events, shifts, stats, score) to the backend.
- The team website updates automatically.
- The game is marked **Synced**.

### Re-sending after edits

Make changes, tap **Save & Send** again. The server upserts by `gameId`, so re-sending replaces the previous version of the game cleanly.

### Reset to Bout

> Admin only, and only for games linked to a scheduled bout.

From the game's detail view, **Reset to Bout** wipes all stats, events, and shifts, removes the game from the server if it was synced, and returns the schedule entry to the **Upcoming** list. Use this if a game was created in error or needs to be restarted from scratch.

---

## 13. MVP Voting

> Admin only. Available on **synced** games (the button only appears after Save & Send).

After a game is sent to the website:

1. Open the game → **MVP Voting**.
2. Tap **Open Voting** to let fans vote on the website.
3. While voting is open, the screen shows:
   - Total ballots cast
   - Live per-player tallies (e.g. `Sela 'Tequila' Dieden — 5 Votes`)
   - Auto-refresh every **2 seconds**
4. Tap **Close Voting** to lock the result.
5. The closed view shows the final winner and refreshes every 30 seconds.
6. **Reopen Voting** is available if you closed too early or need a recount.

---

## 14. Fixing Mistakes

| Mistake | Fix |
|---------|-----|
| Wrong player tapped on a stat | Tap the event in the feed → change the player |
| Wrong assist | Same — event editor |
| Penalty entered with wrong time | Event editor → change clock time |
| Game clock drifted from rink clock | Clock control → **Edit Time** |
| Lineup is wrong mid-game | Pull up the player picker → toggle in/out |
| Whole game is junk | (Admin only, schedule-linked games) **Reset to Bout** |
| Game already sent and has errors | Edit anywhere, then **Save & Send** again |

The event feed is the source of truth — if a derived stat (G total, +/-, GWG) looks wrong, fix the underlying event and the totals recalculate.

---

## 15. Photos

- Player photos sync from the server during roster sync (pull-to-refresh on the Roster tab).
- The server tries `jerseyDisplay`, then jersey `number`, then `default.jpg` to resolve a photo.
- Photos uploaded from the app are stored per-player and override number-based photos.
- Cache busting is automatic — re-uploaded photos appear without restarting the app.

> Uploading photos requires the `photographer` or `admin` role.

---

## 16. Roles & Permissions

| Role | Can do |
|------|--------|
| `player` | View games, stats, roster, history |
| `roster_manager` | Edit and push roster changes |
| `photographer` | Upload player photos |
| `schedule_manager` | Add/remove scheduled bouts |
| `admin` | Everything above, plus: send games, delete games, manage users, MVP voting, manual stat editing, Reset to Bout |

To manage roles:

- Admins open **Profile → Admin → User Management**, pick a user, change their role.
- Some stat views (notably **+/-**) are admin-only on the app side; the server stores the data but the public website does not display it.

---

## 17. Offline Use

PinkSync works fully offline:

- All recording (clock, events, shifts, lineup, photos) happens locally.
- The app shows an **offline indicator** when there is no network.
- A failed **Save & Send** is queued automatically and retries:
  - Every 60 seconds while online
  - The moment the device reconnects
  - When the app comes back to the foreground
- The pending count and last sync error are visible so you know what is waiting.

You never have to wait for connectivity to keep tracking the game — start tapping and let the sync layer catch up later.
