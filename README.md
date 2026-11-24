# ZoneNotes

A World of Warcraft Forever addon for leaving yourself reminders that pop up when you walk into a place.

> "When I'm in a city with an Auction House, post the herbs." → walk into Orgrimmar, and a reminder pops up with a sound.

## Where a note can fire

- **Any city with an Auction House**: Stormwind, Ironforge, Darnassus, Orgrimmar, Thunder Bluff, Undercity, Booty Bay, Gadgetzan, Everlook (plus later-expansion cities if Forever has them)
- **Any inn or rested area**
- **A specific place**: any zone or subzone by name, such as `Orgrimmar`, `The Drag` or `Gadgetzan`. The note window has buttons to fill in where you're standing.

A note keeps popping up every time you arrive until you click **Done** on it. Notes are on all your characters unless you tick **Only on this character**.

## Usage

Type `/zn` to open the notes window, then click **New note**. Rows in green match where you're standing right now.

When you walk into a matching place, a pop-up lists every note for it. The note also prints in chat and plays a sound. Each note in the pop-up has two buttons:
- **Done**: you've done it, so the note is deleted.
- **Next time**: keep the note and remind you on your next visit.

**Close** dismisses the whole pop-up (same as Next time for everything). You can drag the pop-up to move it.

To stop it nagging when you cross a zone border back and forth, the same note won't pop again for 2 minutes. It also stays quiet after a `/reload`.

## Commands

| Command | What it does |
|---|---|
| `/zn` | Open or close the notes window |
| `/zn city <text>` | Quick note for any Auction House city |
| `/zn inn <text>` | Quick note for any inn or rested area |
| `/zn here <text>` | Quick note for the zone you're in |
| `/zn list` | List your notes in chat |
| `/zn test` | Show the notes for where you're standing |
| `/zn sound` | Turn the sound on or off |

`/zonenotes` works too.

## Install

Copy the `ZoneNotes` folder into `World of Warcraft\_forever_\Interface\AddOns\`, then fully restart the game.
