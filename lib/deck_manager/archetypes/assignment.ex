defmodule DeckManager.Archetypes.Assignment do
  @moduledoc """
  Places every card in a pool into the archetypes it belongs to.

  `Discovery` answers "what archetypes does this pool support?"; this module
  answers the per-card follow-up "where does each card go, and as what?" — the
  view that feeds cube supply/balance analysis and a draft pick order.

  A card can have several homes: a mono-black removal spell is playable in every
  black archetype, while a gold signpost belongs to exactly one. We distinguish
  three roles so the two aren't conflated:

    * `:signpost` — a multicolor card whose identity is *exactly* an archetype's
      colors: it was printed to point at that archetype.
    * `:synergy` — color-legal and actively matches one of the archetype's
      defining mechanics (a payoff or enabler).
    * `:role_player` — color-legal but with no specific synergy: a card that
      merely *can* be played there (removal, fixing, a vanilla beater).

  Matching a card to a mechanic reuses `Discovery.theme_matches/1` — the same
  detectors (semantic + emergent keyword + typal) that produced the archetypes —
  so assignment stays consistent with discovery. The frontier model's free-text
  `key_mechanics` are mapped back onto those detectors by shared content word,
  falling back to an oracle-text phrase search for build-around hooks (e.g.
  "attacks alone") that are neither keywords nor types.
  """

  alias DeckManager.Archetypes.Discovery

  @colors ~w(W U B R G)

  # Evergreen combat keywords describe how a creature fights, not what deck it
  # enables. They mean opposite things depending on the archetype: for a TYPAL
  # archetype (Dragons, Angels) a flier is incidental — the type is the theme, so
  # evergreen keywords must NOT confer membership or the deck swallows every
  # flier. For an evasion/tempo archetype, evasive creatures ARE the deck, so
  # there the same keyword is the core theme. We resolve this by whether the
  # archetype is anchored on a creature type (`typal?`): demote evergreen only
  # then.
  @evergreen ~w(flying fliers flier evasion menace trample deathtouch lifelink
                vigilance haste reach ward defender indestructible hexproof strike)

  @doc """
  Assign every card to its archetype homes.

  `archetypes` is the list `Discovery.discover/2` returns (maps with string keys
  `"colors"`, `"archetype"`, `"key_mechanics"`, `"tier"`). Returns one entry per
  card: `%{card: %Card{}, homes: [home]}` where each `home` is
  `%{colors, archetype, tier, role, score, matched}` sorted best-fit first.
  `matched` lists which of the archetype's mechanics the card satisfies.
  """
  def assign(cards, archetypes) do
    theme_map = Discovery.theme_matches(cards)
    parsed = Enum.map(archetypes, &parse_archetype(&1, cards, theme_map))
    artifact_home? = Enum.any?(parsed, & &1.artifact_themed?)

    Enum.map(cards, fn card ->
      homes =
        parsed
        |> Enum.map(&fit(card, &1))
        |> Enum.reject(&is_nil/1)
        |> concentrate_colorless_artifacts(card, artifact_home?)
        |> Enum.sort_by(& &1.score, :desc)

      %{card: card, homes: homes}
    end)
  end

  # A colorless artifact has no color to place it, so color-legality alone would
  # scatter it into every archetype it incidentally touches (Wurmcoil into every
  # deck that likes a creature dying). In a cube these cards are the artifact
  # deck's payload, so when an artifact archetype exists they home there and
  # nowhere else.
  defp concentrate_colorless_artifacts(homes, card, true) do
    if colorless_artifact?(card) do
      Enum.filter(homes, & &1.artifact_themed?)
    else
      homes
    end
  end

  defp concentrate_colorless_artifacts(homes, _card, false), do: homes

  defp colorless_artifact?(card) do
    (card.color_identity || []) == [] and String.contains?(card.type_line || "", "Artifact")
  end

  @doc """
  Roll the per-card assignment up into a per-archetype supply view.

  Returns `[{archetype_map, [%{card:, role:, matched:, score:}]}]` in the input
  archetype order, listing only the cards that actively belong (signpost or
  synergy — not incidental role-players), signposts first.
  """
  def by_archetype(assignments, archetypes) do
    Enum.map(archetypes, fn arch ->
      name = arch["archetype"]

      members =
        for %{card: card, homes: homes} <- assignments,
            home <- homes,
            home.archetype == name and home.role in [:signpost, :synergy] do
          %{card: card, role: home.role, matched: home.matched, score: home.score}
        end
        |> Enum.sort_by(& &1.score, :desc)

      {arch, members}
    end)
  end

  @doc """
  Cards with no synergy or signpost home anywhere — the flexible "role-player"
  pool. Returns `[%{card:, legal_colors: [colors_str]}]`: the card and the
  archetypes it is merely color-legal for. In a cube these still have homes (any
  deck of their colors), they just don't pull toward one archetype.
  """
  def flex_cards(assignments) do
    for %{card: card, homes: homes} <- assignments,
        not Enum.any?(homes, &(&1.role in [:signpost, :synergy])) do
      %{card: card, legal_colors: Enum.map(homes, & &1.colors)}
    end
  end

  # Pre-resolve an archetype to its color set and the set of card names each of
  # its mechanics matches, so per-card fitting is a cheap membership test.
  defp parse_archetype(arch, cards, theme_map) do
    mechanics = arch["key_mechanics"] || []

    mechanic_hits =
      Map.new(mechanics, fn m ->
        names = m |> cards_for_mechanic(cards, theme_map) |> MapSet.new(& &1.name)
        {m, names}
      end)

    typal? = Enum.any?(mechanics, &typal_mechanic?(&1, theme_map))

    %{
      colors: arch["colors"],
      name: arch["archetype"],
      tier: arch["tier"],
      colorset: parse_colors(arch["colors"]),
      # Evergreen keywords confer membership only for an archetype that is *about*
      # evasion/tempo — there evasive creatures ARE the deck. A typal archetype
      # (Dragons) or a synergy archetype that merely lists fliers among its
      # mechanics (UR spells) must not scoop every flier.
      evergreen_ok?: tempo_named?(arch["archetype"]) and not typal?,
      artifact_themed?: Enum.any?(mechanics, &artifact_mechanic?(&1, theme_map)),
      mechanic_hits: mechanic_hits
    }
  end

  # An archetype is artifact-themed when a key mechanic resolves to the artifacts
  # (or artifact-creatures) theme — the home for the pool's colorless artifacts.
  defp artifact_mechanic?(mechanic, theme_map) do
    case best_theme(theme_map, mechanic) do
      {name, _cards} -> String.contains?(name, "artifact")
      nil -> false
    end
  end

  # An archetype is typal when one of its key mechanics resolves to a creature
  # type (a "type:..." detector) — e.g. Dragons, Angels, Merfolk.
  defp typal_mechanic?(mechanic, theme_map) do
    case best_theme(theme_map, mechanic) do
      {name, _cards} -> String.starts_with?(name, "type:")
      nil -> false
    end
  end

  @tempo_words ~w(tempo evasi flier flying skies ninja)

  defp tempo_named?(name) do
    n = String.downcase(name || "")
    Enum.any?(@tempo_words, &String.contains?(n, &1))
  end

  defp fit(card, arch) do
    ci = card.color_identity || []

    if color_legal?(ci, arch.colorset) do
      matched = for {m, names} <- arch.mechanic_hits, MapSet.member?(names, card.name), do: m
      core = if arch.evergreen_ok?, do: matched, else: Enum.reject(matched, &evergreen?/1)

      role =
        cond do
          # Lands are fixing — playable in the pair but never its signpost or its
          # synergy engine, so they don't belong in an archetype's supply.
          land?(card) -> :role_player
          signpost?(ci, arch.colorset) -> :signpost
          core != [] -> :synergy
          true -> :role_player
        end

      %{
        colors: arch.colors,
        archetype: arch.name,
        tier: arch.tier,
        role: role,
        matched: matched,
        artifact_themed?: arch.artifact_themed?,
        score: score(role, length(core))
      }
    end
  end

  # A card is playable in an archetype when its color identity fits within the
  # archetype's colors (colorless fits everywhere).
  defp color_legal?(ci, colorset), do: Enum.all?(ci, &MapSet.member?(colorset, &1))

  # A signpost is a gold card printed to point at a specific two- or three-color
  # archetype: its identity is exactly those colors. The idea doesn't apply to
  # 4-5 color "domain"/typal archetypes, where a card sharing all five colors is
  # not a signpost for anything — those earn membership by type/mechanic instead.
  defp signpost?(ci, colorset) do
    MapSet.size(colorset) in 2..3 and MapSet.new(ci) == colorset
  end

  defp land?(card), do: String.contains?(card.type_line || "", "Land")

  # Signposts outrank multi-mechanic payoffs, which outrank single-mechanic ones;
  # role-players score 0 so they never displace real members in the supply view.
  defp score(:signpost, hits), do: 100 + hits
  defp score(:synergy, hits), do: hits * 10
  defp score(:role_player, _), do: 0

  # Cards a mechanic matches: first via the detector/keyword/typal that shares a
  # content word with the mechanic name, else a raw oracle-text phrase search for
  # build-around hooks that aren't detectors.
  defp cards_for_mechanic(mechanic, cards, theme_map) do
    case best_theme(theme_map, mechanic) do
      {_name, matched} -> matched
      nil -> phrase_matches(cards, mechanic)
    end
  end

  defp best_theme(theme_map, mechanic) do
    mtoks = mechanic |> content_tokens() |> MapSet.new()

    if MapSet.size(mtoks) == 0 do
      nil
    else
      Enum.find(theme_map, fn {name, _cards} ->
        ntoks = name |> String.replace_prefix("type:", "") |> content_tokens() |> MapSet.new()
        token_overlap?(mtoks, ntoks)
      end)
    end
  end

  # Two token sets overlap if any pair shares a stem (one is a prefix of the
  # other, min length 4) — so "villains"/"villain" and "counters"/"counter" match
  # without a real stemmer.
  defp token_overlap?(a, b) do
    Enum.any?(a, fn x -> Enum.any?(b, &stem_eq?(x, &1)) end)
  end

  defp stem_eq?(x, y) do
    x == y or (String.length(x) >= 4 and String.length(y) >= 4 and prefix_either?(x, y))
  end

  defp prefix_either?(x, y), do: String.starts_with?(x, y) or String.starts_with?(y, x)

  defp evergreen?(mechanic) do
    mechanic |> content_tokens() |> Enum.any?(&(&1 in @evergreen))
  end

  defp phrase_matches(cards, mechanic) do
    m = normalize(mechanic)

    if String.length(m) < 4 do
      []
    else
      Enum.filter(cards, fn c -> String.contains?(normalize(c.oracle_text), m) end)
    end
  end

  # Words too common across theme/mechanic names to carry meaning: matching on
  # them causes false overlaps ("creature dies" wrongly resolving to "artifact
  # creatures" because both contain "creature").
  @stopwords ~w(your that with this from creature creatures card cards spell
                spells permanent permanents player players target control each
                other another whenever noncreature)

  # Content words of a mechanic/theme name: normalized, short/common words
  # dropped, so "sacrifice/aristocrats" -> ["sacrifice", "aristocrats"].
  defp content_tokens(text) do
    text
    |> normalize()
    |> String.split()
    |> Enum.filter(fn w -> String.length(w) >= 4 and w not in @stopwords end)
  end

  defp normalize(text) do
    (text || "")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9 ]/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  # "WB" -> #{W,B}, "mono-R" -> #{R}, "WUBRG"/"5c"/"domain" -> all five.
  defp parse_colors(colors_str) do
    letters =
      colors_str
      |> String.upcase()
      |> String.graphemes()
      |> Enum.filter(&(&1 in @colors))
      |> Enum.uniq()

    case letters do
      [] -> MapSet.new(@colors)
      _ -> MapSet.new(letters)
    end
  end
end
