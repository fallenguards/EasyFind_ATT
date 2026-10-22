# EasyFind: ALL THE THINGS Extension

ALL THE THINGS' things in EasyFind's search bar. Type a mount, pet, toy, title or recipe and the row says whether your account has it and where it comes from. A click asks EasyFind's GPS for directions to the source.

Requires ALL THE THINGS and EasyFind.

## Dependencies

- EasyFind, with its extension API (EasyFind.API version 1).
- ALL THE THINGS, which this addon reads at runtime: its lists of things, its account-wide collection state and where each thing comes from. Nothing of ALL THE THINGS' is copied into this addon.

## How it reads ALL THE THINGS

The addon waits for ALL THE THINGS to say it is ready, then looks for the search functions it needs. If one is missing in the installed version, the search turns itself off with one line in chat and nothing else changes. ALL THE THINGS' settings and saved data are never written.
