# Balance

> **Status: stub — not yet implemented**

## Description

Logical weighing puzzle: deduce which balls differ in weight using the minimum number of balance-scale comparisons.

## Files to create

- `board.lua` — game logic, puzzle generator, serialize/load
- `board_widget.lua` — grid rendering and tap gestures
- `screen.lua` — full-screen layout (buttons + board)
- `main.lua` — PluginBase entry point

## Notes

Placement/deduction game — adapt InputContainer pattern from game-common.
