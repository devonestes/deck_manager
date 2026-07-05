defmodule DeckManager.Archetypes.Reference do
  @moduledoc """
  The seed knowledge the discovery engine reasons against.

  Two parts, deliberately separate:

  * `detectors/0` — how to *measure* low-level mechanical themes in a pool. Each
    is a Scryfall keyword set and/or an oracle-text regex. This is the emergent
    layer: whatever mechanics are actually in the cards get counted.
  * `taxonomy_prompt/0` — a compiled list of Limited archetypes seen across recent
    sets, used only as candidate *hypotheses* and altitude guidance. The evidence
    always wins; the priors just make sure strategic altitudes (tempo, aggro) and
    common pairings are in scope so nothing is invisible for lack of vocabulary.

  Extend `detectors/0` when a new mechanic appears; extend `taxonomy_prompt/0`
  when a new archetype shows up in a set.
  """

  # {theme, scryfall_keywords, oracle_regex_or_nil}
  @detectors [
    {"fliers/evasion", ["Flying", "Menace"], ~r/can't be blocked/},
    {"flash", ["Flash"], nil},
    {"ninjutsu", ["Ninjutsu"], nil},
    {"bounce/tempo-interaction", [],
     ~r/return target .* to (its|their) owner's hand|tap target|doesn't untap|stun counter/},
    {"blink/flicker", [], ~r/exile .*return .*to the battlefield/},
    {"+1/+1 counters", ["Proliferate", "Outlast"], ~r/\+1\/\+1 counter/},
    {"tokens", [], ~r/create .* token/},
    {"sacrifice/aristocrats", [], ~r/\bsacrifice\b|\bdies\b/},
    {"graveyard", [], ~r/graveyard/},
    {"reanimator", [], ~r/return .* creature card .* from .* graveyard .* to the battlefield/},
    {"mill", ["Mill"], ~r/\bmill\b/},
    {"delirium/threshold", ["Delirium"], ~r/delirium|four or more card types/},
    {"surveil", ["Surveil"], nil},
    {"discard/madness", ["Madness"], ~r/\bdiscard\b/},
    {"artifacts", ["Affinity", "Improvise"], ~r/\bartifact\b/},
    {"artifact creatures", [], ~r/artifact creature/},
    {"treasure", [], ~r/treasure/},
    {"spells-matter", ["Prowess"], ~r/instant or sorcery|noncreature spell/},
    {"ramp", [], ~r/\{t\}: add|search your library for .* land/},
    {"landfall", ["Landfall"], ~r/landfall/},
    {"lifegain", [], ~r/gain [0-9x]+ life|gain that much life/},
    {"attack/aggro", ["Haste"], ~r/whenever .* attacks/},
    {"combat damage", [], ~r/deals combat damage/},
    {"power-matters", [], ~r/power 4 or greater|greatest power/},
    {"energy", [], ~r/\{e\}|energy counter/}
  ]

  def detectors, do: @detectors

  def taxonomy_prompt do
    """
    Known Limited archetypes (candidate hypotheses only — pick the altitude the evidence supports):

    STRATEGIC (roll specific mechanics UP to these when a cluster of them co-occurs in a pair):
    - Aggro / go-wide: cheap creatures, tokens, attack triggers, anthems, haste
    - Tempo / fliers: cheap EVASIVE threats (flying/menace) + interaction that buys tempo (bounce, tap/stun, flash, ninjutsu)
    - Midrange: efficient value creatures, card advantage
    - Control: removal + card draw + finishers
    - Ramp / big-mana: acceleration into expensive payoffs, power-matters
    - Combo / build-around: one specific engine

    MECHANICAL / SYNERGY THEMES (name the archetype after one of these when a SINGLE mechanic clearly dominates a pair):
    +1/+1 counters, tokens, sacrifice/aristocrats, graveyard/self-mill, reanimator, spellslinger,
    artifacts, enchantments, Voltron (auras/equipment), blink/flicker (ETB value), lifegain,
    discard/madness, mill, energy, landfall, proliferate, delirium/threshold, treasure,
    vehicles, power-matters/monsters, flash, ninjas.

    COLOR-PAIR PRIORS (typical defaults — treat as a first guess, override with the evidence):
    WU fliers/tempo/control · WB lifegain/aristocrats · WR go-wide aggro · WG counters/tokens ·
    UB control/mill/tempo · UR spells OR artifacts/artifact-creatures · UG ramp/flash/energy · BR sacrifice/madness ·
    BG graveyard/midrange · RG landfall/monsters
    """
  end
end
