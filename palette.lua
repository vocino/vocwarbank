local _, ns = ...

-- Palette (FAMILY.md "Palette"; the voc-addons skill, principle 2),
-- defined once and loaded first. Every color the window paints is a
-- name from this table; nothing writes an RGB triple at a call site.
-- The chrome tokens (gold, text, muted, red, green) are the family's.
-- The data tokens (verdict, quality) are VocWarbank's own and stay the
-- same in every look: they are data, not chrome (FAMILY.md principle 6).
ns.COLORS = {
  gold = { 1, 0.82, 0 },         -- titles, emphasis, the selection and queue marks
  text = { 1, 1, 1 },            -- body
  muted = { 0.5, 0.5, 0.5 },     -- hints, secondary text, the unknown-quality plate
  red = { 0.9, 0.3, 0.25 },      -- restriction lines and warnings only
  green = { 0.25, 0.9, 0.35 },   -- valid state only

  -- Verdict dots, one per verdict (ranking.lua verdictOrder).
  verdict = {
    keep = { 0.1, 0.9, 0.1 }, sell = { 1, 0.85, 0 },
    disenchant = { 0.2, 0.6, 1 }, vendor = { 0.7, 0.7, 0.7 },
    destroy = { 0.7, 0.1, 0.1 }, use = { 0.75, 0.5, 1 },
  },

  -- Item quality plates, Blizzard's own ladder (ITEM_QUALITY_COLORS is
  -- preferred when the client has it; this is the stock fallback).
  quality = {
    [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 },
    [3] = { 0, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 },
    [6] = { 0.9, 0.8, 0.5 }, [7] = { 0, 0.8, 1 },
  },
}

-- r, g, b (and alpha when given) for a token, so a SetColorTexture or
-- SetTextColor call reads as the token's name.
function ns.rgb(token, alpha)
  return token[1], token[2], token[3], alpha
end
