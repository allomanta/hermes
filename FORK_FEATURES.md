# Hermes fork features

Added features on top of upstream that need to be maintained through any merges with upstream:

## Features
- Telegram style full page interactive swipe (with setting toggle)
- Faster/smoother reply swipe interaction that interacts better with the page swipe. Also interacts more with trackpads/mice
- Use Alt+j/k/arrows to jump between chats, escape generally acts more like a back button (closes chats, images, pickers, edits etc)
- Up arrow opens the last sent message for editing
- Hide nested spaces from navigation rail
- Tapping on a message shows a popup instead of selecting it
- Choose whether to open stickers or emojis by default (always shows emojis when typing)
- Sticker picker stays open when typing on desktop and search grabs focus after opening
- Add toggle to switch a chat between a group and direct chat
- Some backfill options to copy the entire state locally for a faster scrolling/searching etc
- j/k shortcuts for image scrolling
- Direct share integration for android
- Markdown tweaks
- Sticker pack picker at the top of the sticker picker to quickly scroll to the right pack

## UI tweaks
- Nav rail resizes
- Added settings toggle to nav rail
- Removed profile from search bar
- Removed daily status 
- Add back unread messages count from back button in chats
- Remove gradient from chats
- Always show timestamps, not relative age (grouped for sequental messages) and dates
- Show sending text at the end of a group of sending messages
- Darken sending message bubbles
- Attachment button is moved to the right of the input
- Removed a bunch of empty space in sticker picker
- Login layout spacing tweaks, was off on some devices for me

## Optimizations
- Different media caching
- Sticker memory caching
- Load stickers per row
- Load stickers at low resolution when in sticker picker

## Bug fixes

— Routes refresh their child when a page key is reused
- Search simplification and fixes, used to stop searching if it didn't immediately find matches for me
- Search results jump better to chats, added the option for images etc as well, jumps back to search on back
- Correct end-of-timeline detection and jump-to-bottom
- Notification behavior:
    - Clear notifications when a chat is opened/read
    - Sync updates clear notifications for rooms whose normal unread state is clear, supporting reads on other devices
    - Don't get stuck on read receipt failure
    - Notifications on macos (weren't working for me before)

## Miscelanous
- Name/logo changes because I thought it looked/sounded cool
- Run the firebase notification integration by default
- Regression tests for these features
