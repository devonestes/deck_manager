defmodule DeckManager.Tags do
  @moduledoc """
  The closed vocabulary the card tagger fills in, plus validation.

  Deliberately *functional and objective* — what a card does, read off its text —
  not how strong it is. Power/quality is intentionally excluded: for draft it
  comes from real 17Lands win rates, and having a 7B guess it would be its weakest
  point. Keeping the vocabulary closed (fixed enums and lists) is what makes a
  small local model reliable here, so `validate/1` rejects anything out of range
  and the caller retries.

  Changing this vocabulary invalidates existing tags — bump/rebuild the tag cache
  (`data/tags/tags.jsonl`) when you do.
  """

  @removal ~w(none conditional unconditional sweeper)
  @removal_speed ~w(none instant sorcery)
  @card_advantage ~w(negative neutral positive strong)
  @role ~w(enabler payoff flexible standalone)
  @functions ~w(ramp card_draw counterspell recursion tutor protection disruption
                fixing lifegain discard burn bounce anthem cost_reduction pump wincon)
  @archetypes ~w(aggro control midrange tokens sacrifice counters artifacts
                 enchantments graveyard spells_matter lifegain ramp blink mill
                 go_wide combo)

  def removal, do: @removal
  def removal_speed, do: @removal_speed
  def card_advantage, do: @card_advantage
  def role, do: @role
  def functions, do: @functions
  def archetypes, do: @archetypes

  @doc """
  Validate and normalize a decoded model response.

  Unknown values in the list fields are dropped; an out-of-range enum (or a
  missing required key) is an error so the caller can retry. Returns
  `{:ok, map}` with atom keys, or `{:error, reason}`.
  """
  def validate(%{} = raw) do
    with {:ok, removal} <- enum(raw, "removal", @removal),
         {:ok, removal_speed} <- enum(raw, "removal_speed", @removal_speed),
         {:ok, card_advantage} <- enum(raw, "card_advantage", @card_advantage),
         {:ok, role} <- enum(raw, "role", @role) do
      {:ok,
       %{
         removal: removal,
         removal_speed: removal_speed,
         card_advantage: card_advantage,
         role: role,
         evasive: truthy(raw["evasive"]),
         interaction: truthy(raw["interaction"]),
         functions: subset(raw["functions"], @functions),
         archetypes: subset(raw["archetypes"], @archetypes)
       }}
    end
  end

  def validate(_), do: {:error, :not_a_map}

  @doc "Human-readable field spec injected into the tagging prompt, kept in sync with the vocab."
  def schema_doc do
    """
    - removal: one of #{inspect(@removal)}
        "sweeper" = affects MULTIPLE or ALL targets (e.g. "destroy all creatures", "deal 3 damage to each creature") — use this even when the card says "destroy", whenever it hits many things at once
        "unconditional" = removes almost ANY single target with no meaningful restriction
        "conditional" = single-target removal that is restricted (by color, mana value, tapped-ness, power/toughness, damage amount, etc.)
        "none" = does not remove permanents
    - removal_speed: one of #{inspect(@removal_speed)} — instant- vs sorcery-speed; "none" if not removal
    - card_advantage: one of #{inspect(@card_advantage)} — the NET cards/permanents it deals with or generates:
        "strong" = mass removal that hits several, OR a repeatable source of cards/bodies (each turn, etc.)
        "positive" = nets one extra card
        "neutral" = trades one-for-one — THIS INCLUDES most single-target removal (your one card for their one card is neutral, NOT negative) — or simply replaces itself
        "negative" = costs you cards with no replacement
    - evasive: true/false — does THIS card, as a creature, have evasion (flying, menace, can't be blocked, shadow, etc.)? false for non-creatures
    - interaction: true/false — does it directly interact with the opponent's cards or plays (removal, counters, discard, etc.)?
    - functions: array, any of #{inspect(@functions)} — include a function ONLY if the text clearly performs it; do not guess. Watch these easily-confused ones: ramp = produces EXTRA MANA; card_draw = draws/puts cards into your hand (NOT ramp); fixing = fixes mana COLORS; burn = deals direct damage to any target or player; disruption = attacks the opponent's hand or plans (discard, taxes, stax); recursion = returns cards from the graveyard; pump = temporary power/toughness boost; anthem = static team-wide boost
    - archetypes: array, any of #{inspect(@archetypes)} — ONLY themes the card clearly enables or pays off from its text; if it is a generically good card with no synergy hook, use an EMPTY array
    - role: one of #{inspect(@role)} — default "standalone" for generically-good or vanilla cards; use "enabler"/"payoff"/"flexible" only when the card clearly works with a named theme
    """
  end

  defp enum(raw, key, allowed) do
    value = raw[key]

    if value in allowed do
      {:ok, value}
    else
      {:error, {:bad_enum, key, value}}
    end
  end

  defp subset(list, allowed) when is_list(list) do
    list |> Enum.filter(&(&1 in allowed)) |> Enum.uniq()
  end

  defp subset(_, _), do: []

  defp truthy(true), do: true
  defp truthy(_), do: false
end
