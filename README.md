# dillaHybridBar

A compact, independent action bar for **World of Warcraft Forever**, designed for hybrid **controller + mouse/keyboard** play.

The addon uses its own secure action buttons and does not modify Blizzard's gamepad UI, controller bindings, or standard action-bar slots.

**Version:** 0.3.8  
**WoW interface:** 16001  
**Dependencies:** None

## Features

- Place spells, items, and macros directly on the bar via drag and drop.
- Configure **1–60 active slots**, columns, rows, button spacing, scale, and background opacity.
- Mouse-clickable secure buttons, including in combat.
- Spell cooldown indicators using Forever-compatible duration objects.
- Item counts displayed in the bottom-right corner (carried bags only, excluding bank).
- Position and settings saved per character; reducing active slots preserves hidden assignments.
- Minimal locked appearance, with a separate `MOVE` handle while unlocked.
- Draggable minimap launcher with direct access to addon options.
- No external libraries or ConsolePort requirement.

## Installation

Copy the addon folder to:

```text
World of Warcraft/_forever_/Interface/AddOns/dillaHybridBar/
```

Ensure `Core.lua` and `dillaHybridBar.toc` are directly inside that folder. Restart the game or use `/reload` after updating.

## Usage

Drag a spell, item, or macro onto an empty button. **Left-click** to use it. **Shift + right-click** a button to clear it (outside combat).

When unlocked, drag the small `MOVE` handle to reposition the bar. The handle is hidden when locked.

Open settings with `/dhb`, through **Options → AddOns → dillaHybridBar**, or by left-clicking the minimap button.

### Minimap launcher

| Action | Result |
| --- | --- |
| Left-click | Open dillaHybridBar options |
| Right-click | Lock / unlock the bar |
| Shift + left-click | Show / hide the bar |
| Left-drag | Move the launcher around the minimap |

### Slash commands

| Command | Description |
| --- | --- |
| `/dhb` or `/dhb config` | Open options |
| `/dhb help` | Show help |
| `/dhb slots 8` | Set active slot count (1–60) |
| `/dhb lock` | Lock the bar |
| `/dhb unlock` | Unlock the bar and show its move handle |
| `/dhb scale 0.8` | Set bar scale (0.5–2.0) |
| `/dhb reset` | Reset layout and position, retaining assignments |
| `/dhb show` | Show the bar |
| `/dhb hide` | Hide the bar |

## Configuration

The options page provides total slots, rows and columns, scale, button spacing, background opacity, lock state, minimap launcher visibility, and layout reset.

Saved settings use **`dillaHybridBarDB`** as character-specific SavedVariables. Existing bindings and settings from earlier versions are retained.

## Limitations

- Changing assignments and protected layout/visibility operations is restricted during combat.
- Item cooldown visualization may be limited when the client supplies protected secret values.
- This addon targets WoW Forever; compatibility with other game clients is not guaranteed.

## Changelog

### 0.3.8
- Display item stack counts on item buttons and update them when inventory changes.

### 0.3.7
- Use secret-safe duration objects for spell cooldown visualization.

### 0.3.6
- Rework bar position persistence to store WoW anchors and avoid duplicate automatic position storage.

### 0.3.5
- Fix startup ordering so saved button layout is applied after secure buttons are created.

### 0.3.4
- Initial position persistence changes.

### 0.3.3
- Minimap right-click toggles lock; Shift + left-click toggles bar visibility.

### 0.3.2
- Remove permanent title strip; show an independent move handle while unlocked.

### 0.3.1
- Adjust minimap launcher position and options-page navigation.

### 0.3.0
- Configurable active slots up to 60 and draggable minimap button.

### 0.2.0
- Options page and configurable grid/layout.

### 0.1.1
- Correct spell ID handling and secure mouse-click registration.

### 0.1.0
- Initial independent secure action bar.

## Development note

Version 0.3.8 was tested by the project owner in WoW Forever. The GitHub publication itself does not imply a new in-game regression test.