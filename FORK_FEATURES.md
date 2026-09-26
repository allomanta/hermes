# Hermes fork features

Added features on top of upstream that need to be maintained through any merges with upstream:

## Features
- Telegram style full page interactive swipe (with setting toggle) [55173656a, 96928db1d, 395de588a, decf4ee07, af3f8af41, af4e45a6d, 60bda3ea3, bf06067d6]
- Faster/smoother reply swipe interaction that interacts better with the page swipe. Also interacts more with trackpads/mice [f0b8ec437, d99affcf6, decf4ee07, 92d17e7b5, 9e4976f55, 4b57d5f2c, af4e45a6d]
- Use Alt+j/k/arrows to jump between chats, escape generally acts more like a back button (closes chats, images, pickers, edits etc) [3fb8e1e76, 55173656a, 9c2dd20e3, cf1910a39, ffd9eda27]
- Hide nested spaces from navigation rail [349c0db97, 42f34548c]
- Tapping on a message shows a popup instead of selecting it [789fa6efb, 50aa402ef, 304d2bc04, 281cf98b9, e3bab1225, 7f3bb0eca]
- Choose whether to open stickers or emojis by default (always shows emojis when typing) [696ede3b3, 2aaafdad9]
- Sticker picker stays open when typing on desktop and search grabs focus after opening [c5b472823, 812dabb4c, 9c2dd20e3]
- Add toggle to switch a chat between a group and direct chat [c2fb42020, 43723c09c]
- Some backfill options to copy the entire state locally for a faster scrolling/searching etc [d52bc0438, 02ace7168]
- j/k shortcuts for image scrolling [33c315829]
- Direct share integration for android [1b0b9854c, 98a65e87d, 24b253b30]
- Markdown tweaks [4caf7c224, 2eb0c4658, d6c5c6196]
- Sticker pack picker at the top of the sticker picker to quickly scroll to the right pack [68041b72a, 8f46b38e9, 186828702]
- Force mark a chat as read to clear stale unread counts [9c356f9bc, 425bf17b6, 82ec9503e]
- Unread chats filter in the navigation rail [306cfb829]
- Drag to reorder spaces in the navigation rail [5373d33b6]
- Open space actions from navigation rail icons [d96f91ce4]
- Sort space chats like the all chats list [e74b1a1dd]

## UI tweaks
- Nav rail resizes [8b642d768, c57b7f39d, 82352a97e, adb6b0dde, 927c18d4b]
- Added settings toggle to nav rail [42f34548c]
- Removed profile from search bar [428d066e5]
- Add back unread messages count from back button in chats [cac50a5c4]
- Remove gradient from chats [6c10736c2]
- Always show timestamps, not relative age (grouped for sequental messages) and dates [fdc1293aa, cf1910a39]
- Show sending text at the end of a group of sending messages [b8e5dc5a3]
- Darken sending message bubbles [8a47c3211]
- Attachment button is moved to the right of the input [9e5d0a91a, 8769006bf]
- Login layout spacing tweaks, was off on some devices for me [2bc689cd5]
- Animated chat filter toggle and sliding space selection indicator [8cb8dcaa1, 5080efdde]
- Compact chat input and emoji/sticker picker [059b6cc57, 393757b39]

## Optimizations
- Different media caching [cfd6ce308]
- Sticker memory caching [b1ff170b8, f5d2f9951, 30d71b447]
- Load stickers per row [8f46b38e9, e0edab660]
- Load stickers at low resolution when in sticker picker [8602e0c9b]

## Bug fixes

— Routes refresh their child when a page key is reused [bf06067d6]
- Search simplification and fixes, used to stop searching if it didn't immediately find matches for me [428d066e5, bb21fc274, fa012027e, 043189cb4]
- Search results jump better to chats, added the option for images etc as well, jumps back to search on back [f502ee2f1, 91f85acc7, fbea87461]
- Correct end-of-timeline detection and jump-to-bottom [3b1d369e0, 3c7ebffe5, b1fd9a3cb, fc5fb315b]
- Notification behavior: [335a8760a, bf2c95d51, 3e05215bb]
    - Clear notifications when a chat is opened/read [335a8760a]
    - Sync updates clear notifications for rooms whose normal unread state is clear, supporting reads on other devices [335a8760a]
    - Don't get stuck on read receipt failure [bf2c95d51]
    - Notifications on macos (weren't working for me before) [0a00dacd4, a6d962f9b, 3e05215bb]
- Clear pending Android shares after use [cb80b234b]
- Restart stalled desktop sync after sleep or network loss [ec3867fab, 74398aa56, 2687eec6e]
- Prevent back swipes from the chat list to a blank page [82cd2cbc2, 957ac4394]
- Sanitize malformed UTF-16 in rail labels and avatars [8cb8dcaa1]
- Position chat context menus at the tap or click and prevent overflow [5f53eab66]
- Hide left spaces and remove stale cached spaces [cc7b0bca1, 868925a36]

## Miscelanous
- Name/logo changes because I thought it looked/sounded cool [c5bdac807, 937c1e13d, 88d9c9d29, 0a4b1e85b, 079418639]
- Run the firebase notification integration by default [b4e009461, 416b7af71, d1d8d1e70]
- Regression tests for these features [bf06067d6, fc5fb315b, 335a8760a, 43723c09c, 30d71b447, e0edab660, 8602e0c9b]
