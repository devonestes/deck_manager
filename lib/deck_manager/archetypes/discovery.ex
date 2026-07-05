defmodule DeckManager.Archetypes.Discovery do
  @moduledoc """
  Discovers a pool's archetypes from the cards alone.

  Two stages, matching the "deterministic evidence + strong-model synthesis"
  split: `evidence_text/1` measures every theme's presence per color (cheap,
  reliable), and `discover/2` hands that evidence plus the seed taxonomy to a
  model that names each pair's archetype at the right altitude.

  Two signals do the heavy lifting per color pair:

    * **balance** — `min(count_a, count_b)`: an archetype needs BOTH colors to
      contribute, which is what stops one color's mechanic (e.g. U's flash) from
      being credited to every pair that contains it.
    * **distinctiveness** — the share of a theme's whole-pool presence that falls
      in this pair: a low-count but highly distinctive theme (ninjutsu, delirium)
      is a strong archetype signal.
  """

  alias DeckManager.Anthropic
  alias DeckManager.Archetypes.Reference
  alias DeckManager.Ollama
  alias DeckManager.Scryfall

  @pairs [
    ~w(W U),
    ~w(W B),
    ~w(W R),
    ~w(W G),
    ~w(U B),
    ~w(U R),
    ~w(U G),
    ~w(B R),
    ~w(B G),
    ~w(R G)
  ]

  @triples [
    ~w(W U B),
    ~w(W U R),
    ~w(W U G),
    ~w(W B R),
    ~w(W B G),
    ~w(W R G),
    ~w(U B R),
    ~w(U B G),
    ~w(U R G),
    ~w(B R G)
  ]

  @doc "For each theme, the list of cards that match its detector."
  def theme_matches(cards) do
    Map.new(all_detectors(cards), fn {name, kws, re} ->
      {name, Enum.filter(cards, &detect(&1, kws, re))}
    end)
  end

  # Fixed semantic detectors PLUS every keyword actually present in this pool, so
  # set-specific mechanics (repartee, converge, and any future keyword) become
  # themes without being hard-coded in advance. This is what lets discovery find
  # mechanics it was never told about.
  defp all_detectors(cards) do
    Reference.detectors() ++ emergent_keyword_detectors(cards) ++ typal_detectors(cards)
  end

  # Creature types that are both populous AND cared-about become themes (e.g.
  # "type:villain"). This is what surfaces typal/tribal archetypes; without it,
  # a Villains deck reads only as its underlying mechanic (sacrifice, etc.).
  defp typal_detectors(cards) do
    cards
    |> qualifying_types()
    |> Enum.map(fn {st, _creatures, _payoffs} ->
      {"type:" <> String.downcase(st), [], type_regex(st)}
    end)
  end

  @doc false
  # [{subtype, creature_count, payoff_count}] for creature types with enough
  # members and enough cards that reference the type.
  def qualifying_types(cards) do
    freq =
      cards
      |> Enum.filter(&String.contains?(&1.type_line || "", "Creature"))
      |> Enum.flat_map(&creature_subtypes(&1.type_line))
      |> Enum.frequencies()

    freq
    |> Enum.filter(fn {_st, n} -> n >= 5 end)
    |> Enum.map(fn {st, n} -> {st, n, payoff_count(cards, st)} end)
    |> Enum.filter(fn {_st, _n, payoffs} -> payoffs >= 3 end)
    |> Enum.sort_by(fn {_st, n, payoffs} -> n + payoffs end, :desc)
  end

  defp creature_subtypes(type_line) do
    (type_line || "")
    |> String.split(" // ")
    |> Enum.flat_map(fn face ->
      case String.split(face, "—", parts: 2) do
        [_, subs] -> subs |> String.trim() |> String.split()
        _ -> []
      end
    end)
  end

  # Cards whose RULES TEXT references the type — payoffs/lords, not mere members.
  defp payoff_count(cards, st) do
    re = type_regex(st)
    Enum.count(cards, fn c -> Regex.match?(re, String.downcase(c.oracle_text || "")) end)
  end

  defp type_regex(st) do
    Regex.compile!("\\b" <> Regex.escape(String.downcase(st)) <> "s?\\b")
  end

  # Glue words; a phrase made only of these is structural boilerplate, not a theme.
  @glue ~w(a an the of to and or this that these those you your yours control
           target each any all at is are be been with for from into in on it its
           their they them as if then when whenever may up onto do does have has
           had than other another where who whose gets get put onto no not can t
           s x may)

  @doc false
  # Recurring oracle-text phrases (2-4 words) that appear on several cards and
  # concentrate in 1-2 colors — the signal for set-specific build-around themes
  # ("attack alone", "draw your second card") that are neither keywords nor types.
  # Boilerplate is filtered by color spread: glue phrases spread across all colors.
  def mined_phrases(cards) do
    cap = round(length(cards) * 0.25)
    docs = Enum.map(cards, fn c -> {c, tokenize(c.oracle_text)} end)

    # Distinctive single words, ranked by TF-IDF against all of MTG. Words compete
    # only with other words here, so a rare hook like "alone" isn't buried under
    # rare multi-word template fragments.
    words =
      docs
      |> ngram_freq(1..1)
      |> Enum.filter(fn {w, n} ->
        n >= 4 and n <= cap and String.length(w) >= 5 and w not in @glue
      end)
      |> attach_colors(docs)
      |> rank_by_tfidf()
      |> Enum.take(12)

    # Multi-word phrases, ranked by frequency (TF-IDF over-rewards rare long
    # fragments, so plain recurrence is the better signal for 2-3 word hooks).
    phrases =
      docs
      |> ngram_freq(2..3)
      |> Enum.filter(fn {ph, n} ->
        n >= 4 and n <= cap and not Enum.all?(String.split(ph), &(&1 in @glue))
      end)
      |> attach_colors(docs)
      |> Enum.sort_by(fn {_ph, n, _c} -> n end, :desc)
      |> Enum.take(15)

    words ++ phrases
  end

  # Rank candidates by TF-IDF against the full MTG oracle corpus: a phrase frequent
  # in THIS set but rare across all cards is a set-defining hook; generic boilerplate
  # ("each turn", "flying when") is globally common and sinks. This lets a distinctive
  # low-count hook like "alone" outrank frequent-but-generic fragments.
  defp rank_by_tfidf(candidates) do
    corpus = Enum.map(Scryfall.oracle_cards(), fn c -> String.downcase(c.oracle_text || "") end)
    n_global = length(corpus) + 1

    candidates
    |> Enum.map(fn {ph, n, colors} ->
      df = Enum.count(corpus, &String.contains?(&1, ph)) + 1
      {ph, n, colors, n * :math.log(n_global / df)}
    end)
    |> Enum.sort_by(fn {_ph, _n, _colors, score} -> score end, :desc)
    |> Enum.map(fn {ph, n, colors, _score} -> {ph, n, colors} end)
  end

  defp tokenize(text) do
    (text || "")
    |> String.replace(~r/\([^)]*\)/, " ")
    |> String.downcase()
    |> String.replace(~r/[^a-z ]/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  # Distinct n-gram -> card count (counts each n-gram once per card).
  defp ngram_freq(docs, range) do
    docs
    |> Enum.flat_map(fn {_c, text} ->
      ws = String.split(text)

      for(n <- range, chunk <- Enum.chunk_every(ws, n, 1, :discard), do: Enum.join(chunk, " "))
      |> Enum.uniq()
    end)
    |> Enum.frequencies()
  end

  defp attach_colors(freqs, docs) do
    freqs
    |> Enum.map(fn {ph, n} -> {ph, n, phrase_colors(docs, ph)} end)
    |> Enum.filter(fn {_ph, _n, colors} -> length(colors) in 1..2 end)
  end

  defp phrase_section(cards) do
    case mined_phrases(cards) do
      [] ->
        "RECURRING PHRASES: none notable."

      list ->
        "RECURRING RULES-TEXT PHRASES (phrase — #cards — colors) — candidate set-specific build-around themes that are NOT keywords or types. A phrase concentrated in a color/pair is likely that archetype's hook; name the archetype after the CONDITION (e.g. \"draw your second card\", \"attacks alone\", \"creature cards in your graveyard\"):\n" <>
          Enum.map_join(list, "\n", fn {ph, n, colors} ->
            c = Enum.map_join(colors, ",", fn {col, k} -> "#{col}:#{k}" end)
            "  \"#{ph}\" — #{n} cards — #{c}"
          end)
    end
  end

  defp phrase_colors(docs, phrase) do
    padded = " " <> phrase <> " "
    matched = for {c, text} <- docs, String.contains?(" " <> text <> " ", padded), do: c

    ~w(W U B R G)
    |> Enum.map(fn col ->
      {col, Enum.count(matched, fn c -> col in (c.color_identity || []) end)}
    end)
    |> Enum.filter(fn {_col, n} -> n >= 2 end)
  end

  defp emergent_keyword_detectors(cards) do
    known =
      Reference.detectors()
      |> Enum.flat_map(fn {_name, kws, _re} -> kws end)
      |> MapSet.new()

    cards
    |> Enum.flat_map(fn c -> c.keywords || [] end)
    |> Enum.frequencies()
    |> Enum.reject(fn {kw, count} -> count < 4 or MapSet.member?(known, kw) end)
    |> Enum.map(fn {kw, _} -> {String.downcase(kw), [kw], nil} end)
  end

  @doc """
  Per color pair, the defining themes, each as `{theme, count_a, count_b,
  distinctiveness}`.

  A theme is a candidate only if BOTH colors contribute (`min(count_a, count_b) >=
  2`), which stops one color's mechanic from being credited to every pair it
  touches. Candidates are ranked by *distinctiveness* — the fraction of the
  theme's cards playable in exactly this pair (`color_identity ⊆ {a,b}`) — so
  ubiquitous themes like ramp fall away and defining ones like delirium rise.
  """
  def pair_evidence(cards) do
    tm = theme_matches(cards)

    Enum.map(@pairs, fn [a, b] ->
      themes =
        tm
        |> Enum.map(fn {name, matches} -> theme_signal(name, matches, a, b) end)
        |> Enum.filter(fn {_, ca, cb, _, _, in_pair} -> min(ca, cb) >= 2 and in_pair >= 3 end)
        |> Enum.sort_by(&score/1, :desc)
        |> Enum.take(6)
        |> Enum.map(fn {name, ca, cb, dist, gold, _} -> {name, ca, cb, dist, gold} end)

      {"#{a}#{b}", a, b, themes}
    end)
  end

  # Per-theme signal for a pair: both colors' counts, the count actually playable
  # in-pair (colored, `color_identity ⊆ {a,b}`), the count of true gold cards
  # (color identity exactly this pair), and distinctiveness (in_pair / whole-pool
  # count). Colorless cards are left out of the numerator so they don't inflate
  # every pair equally. `in_pair >= 3` is the support floor that kills tiny
  # spurious themes.
  defp theme_signal(name, matches, a, b) do
    ci = fn card -> card.color_identity || [] end
    ca = Enum.count(matches, &(a in ci.(&1)))
    cb = Enum.count(matches, &(b in ci.(&1)))

    in_pair =
      Enum.count(matches, fn c ->
        id = ci.(c)
        id != [] and Enum.all?(id, &(&1 in [a, b]))
      end)

    gold = Enum.count(matches, fn c -> Enum.sort(ci.(c)) == Enum.sort([a, b]) end)
    total = length(matches)
    dist = if total > 0, do: Float.round(in_pair / total, 2), else: 0.0
    {name, ca, cb, dist, gold, in_pair}
  end

  # Gold cards (signposts) often set a pair's direction, so each AMPLIFIES a
  # theme's distinctiveness — multiplicatively, so gold can only reinforce a theme
  # already concentrated in the pair, never resurrect a ubiquitous filler theme
  # (e.g. ramp) that merely happens to have many gold cards.
  defp score({_name, _ca, _cb, dist, gold, _in_pair}), do: dist * (1 + 0.1 * gold)
  defp score({_name, _ca, _cb, dist, gold}), do: dist * (1 + 0.1 * gold)

  @doc "Human/model-readable evidence bundle for the whole pool."
  def evidence_text(cards) do
    Enum.join(
      [
        "PER-PAIR THEME EVIDENCE — each theme shows the two colors' card counts and distinctiveness:\n" <>
          pair_section(cards),
        three_color_section(cards),
        typal_section(cards),
        phrase_section(cards),
        keyword_summary(cards),
        multicolor_section(cards)
      ],
      "\n\n"
    )
  end

  defp pair_section(cards) do
    Enum.map_join(pair_evidence(cards), "\n", fn {pair, a, b, themes} ->
      lines =
        Enum.map_join(themes, "; ", fn {name, ca, cb, d, gold} ->
          "#{name} (#{a}:#{ca}/#{b}:#{cb}, distinct=#{d}, gold=#{gold})"
        end)

      "#{pair}: #{lines}"
    end)
  end

  # Every keyword present in the set. New keywords (not in our fixed vocabulary)
  # are shown with a definition pulled from a card's reminder text, so the model
  # can understand a mechanic it doesn't know — e.g. that "converge" rewards
  # spending many colors, which implies a 5-color archetype even though the cards
  # themselves aren't multicolored.
  defp keyword_summary(cards) do
    freq =
      cards
      |> Enum.flat_map(fn c -> c.keywords || [] end)
      |> Enum.frequencies()
      |> Enum.filter(fn {_kw, n} -> n >= 3 end)
      |> Enum.sort_by(&elem(&1, 1), :desc)

    known = known_keywords()
    {new_kws, familiar} = Enum.split_with(freq, fn {kw, _} -> not MapSet.member?(known, kw) end)

    new_block =
      case new_kws do
        [] ->
          "  (none)"

        list ->
          Enum.map_join(list, "\n", fn {kw, n} ->
            "  #{kw} (#{n} cards): #{keyword_gloss(cards, kw)}"
          end)
      end

    "SET KEYWORDS.\n" <>
      "NEW/unfamiliar keywords — likely archetype-defining; definition from a sample card:\n" <>
      new_block <>
      "\nOther keywords present: " <>
      Enum.map_join(familiar, ", ", fn {kw, n} -> "#{kw}(#{n})" end)
  end

  defp known_keywords do
    Reference.detectors() |> Enum.flat_map(fn {_n, kws, _re} -> kws end) |> MapSet.new()
  end

  # Creature-type archetypes (Villains, Heroes, ...): type, member count, payoff
  # count, and the colors the type concentrates in — so a typal archetype is named
  # after the type, not just the mechanic underneath it.
  defp typal_section(cards) do
    case qualifying_types(cards) do
      [] ->
        "TYPAL THEMES: no creature type has both a critical mass of creatures and payoffs."

      list ->
        "TYPAL / TRIBAL THEMES (type: members / payoff cards / main colors) — a type with payoffs IS an archetype; name it after the type:\n" <>
          Enum.map_join(list, "\n", fn {st, creatures, payoffs} ->
            "  #{st}: #{creatures} creatures, #{payoffs} payoffs, colors #{type_colors(cards, st)}"
          end)
    end
  end

  defp type_colors(cards, st) do
    re = type_regex(st)

    matches =
      Enum.filter(cards, fn c ->
        Regex.match?(re, String.downcase((c.oracle_text || "") <> " " <> (c.type_line || "")))
      end)

    ~w(W U B R G)
    |> Enum.map(fn col ->
      {col, Enum.count(matches, fn c -> col in (c.color_identity || []) end)}
    end)
    |> Enum.filter(fn {_col, n} -> n >= 2 end)
    |> Enum.sort_by(&elem(&1, 1), :desc)
    |> Enum.map_join("", fn {col, _} -> col end)
  end

  # For each color triple, the count of dedicated three-color cards (signposts)
  # and the top themes among cards castable in it. A triple with several
  # three-color cards is a real wedge/shard "family" — the primary archetype unit
  # in sets like New Capenna or Alara, which the pair analysis can only flatten.
  defp three_color_section(cards) do
    dets = all_detectors(cards)

    groups =
      @triples
      |> Enum.map(fn combo ->
        set = MapSet.new(combo)

        group_cards =
          Enum.filter(cards, fn c ->
            ci = c.color_identity || []
            ci != [] and MapSet.subset?(MapSet.new(ci), set)
          end)

        signposts = Enum.count(group_cards, fn c -> length(c.color_identity || []) == 3 end)
        {Enum.join(combo), group_cards, signposts}
      end)
      |> Enum.filter(fn {_combo, _cards, signposts} -> signposts >= 3 end)
      |> Enum.sort_by(fn {_combo, _cards, signposts} -> signposts end, :desc)

    case groups do
      [] ->
        "THREE-COLOR GROUPS: no color triple has 3+ dedicated three-color cards — this set is not wedge/shard-based."

      list ->
        "THREE-COLOR GROUP EVIDENCE (triples with 3+ dedicated three-color cards — candidate wedge/shard 'family' archetypes; top themes among cards castable in the triple):\n" <>
          Enum.map_join(list, "\n", fn {combo, group_cards, signposts} ->
            "#{combo}: #{signposts} three-color cards | #{top_themes(group_cards, dets)}"
          end)
    end
  end

  defp top_themes(group_cards, dets) do
    dets
    |> Enum.map(fn {name, kws, re} -> {name, Enum.count(group_cards, &detect(&1, kws, re))} end)
    |> Enum.filter(fn {_name, count} -> count >= 3 end)
    |> Enum.sort_by(&elem(&1, 1), :desc)
    |> Enum.take(5)
    |> Enum.map_join(", ", fn {name, count} -> "#{name}(#{count})" end)
  end

  # A short definition of a keyword: its reminder text (first parenthetical) if
  # present, else a snippet of a card's rules text.
  defp keyword_gloss(cards, kw) do
    card =
      Enum.find(cards, fn c ->
        kw in (c.keywords || []) and String.contains?(c.oracle_text || "", "(")
      end) ||
        Enum.find(cards, fn c -> kw in (c.keywords || []) end)

    text = (card && card.oracle_text) || ""

    case Regex.run(~r/\(([^)]{12,220})\)/, text) do
      [_, reminder] -> reminder
      _ -> text |> String.replace("\n", " ") |> String.slice(0, 140)
    end
  end

  # Themes whose cards span 3+ colors — the signal for wedge/shard/5-color
  # "domain" archetypes that the two-color pair analysis structurally cannot see.
  defp multicolor_section(cards) do
    signals =
      all_detectors(cards)
      |> Enum.map(fn {name, kws, re} ->
        matches = Enum.filter(cards, &detect(&1, kws, re))
        multi = Enum.count(matches, fn c -> length(c.color_identity || []) >= 3 end)
        {name, multi, length(matches)}
      end)
      |> Enum.filter(fn {_name, multi, _total} -> multi >= 3 end)
      |> Enum.sort_by(fn {_name, multi, _total} -> multi end, :desc)
      |> Enum.take(8)

    case signals do
      [] ->
        "MULTICOLOR SIGNALS: no theme is concentrated in 3+ color cards."

      list ->
        "MULTICOLOR SIGNALS (themes whose cards span 3+ colors — candidate wedge/shard/5-color 'domain' archetypes):\n" <>
          Enum.map_join(list, "; ", fn {name, multi, total} ->
            "#{name} (#{multi} of #{total} cards are 3+ color)"
          end)
    end
  end

  @doc """
  Assign each pair its defining theme(s) by **competitive** distinctiveness: a
  theme belongs to the pair where it is most distinctive, so a theme high in two
  pairs (e.g. discard in both UR and BR) is credited to the one that owns it (BR),
  freeing the other (UR) for its next-best theme. This global step is what the
  per-pair synthesizer kept getting wrong.

  Returns `[{pair, [{theme, distinctiveness}], :owned | :fallback}]` in pair order.
  """
  def assign(cards) do
    pe = pair_evidence(cards)

    ranked =
      for({pair, _a, _b, themes} <- pe, t <- themes, do: {elem(t, 0), pair, score(t)})
      |> Enum.sort_by(&elem(&1, 2), :desc)

    # Greedy global matching: walking highest score first, give each theme to its
    # best still-open pair and each pair its best still-open theme.
    {primaries, _, _} =
      Enum.reduce(ranked, {%{}, MapSet.new(), MapSet.new()}, fn {name, pair, sc},
                                                                {acc, pairs, themes} ->
        if MapSet.member?(pairs, pair) or MapSet.member?(themes, name) do
          {acc, pairs, themes}
        else
          {Map.put(acc, pair, {name, Float.round(sc, 2)}), MapSet.put(pairs, pair),
           MapSet.put(themes, name)}
        end
      end)

    Enum.map(pe, fn {pair, _a, _b, themes} ->
      {pair, Map.get(primaries, pair) || fallback(themes), themes}
    end)
  end

  # A pair whose themes were all claimed elsewhere takes its own top theme anyway.
  defp fallback([]), do: nil

  defp fallback(themes) do
    top = Enum.max_by(themes, &score/1)
    {elem(top, 0), Float.round(score(top), 2)}
  end

  @doc """
  Run LLM synthesis (naming + altitude) over the evidence. This is the once-per-pool
  step, so it defaults to a frontier model; pass `backend: :ollama` for the local
  14B. Returns `{:ok, %{"pairs" => [...]}} | {:error, reason}`.
  """
  def discover(cards, opts \\ []) do
    prompt = synthesis_prompt(evidence_text(cards))

    result =
      case Keyword.get(opts, :backend, :anthropic) do
        :anthropic ->
          # Adaptive thinking counts against max_tokens; a tribal set's evidence is
          # large, so give generous room or the JSON answer gets truncated (which
          # silently reads as "only one archetype").
          opts =
            opts |> Keyword.put(:format, output_schema()) |> Keyword.put_new(:max_tokens, 32_000)

          Anthropic.generate(prompt, opts)

        :ollama ->
          Ollama.generate(prompt, Keyword.merge([model: "qwen2.5:14b", num_ctx: 8192], opts))
      end

    with {:ok, text} <- result, {:ok, parsed} <- Jason.decode(text) do
      {:ok, parsed}
    end
  end

  # Constrains the frontier model's output to exactly the shape we consume.
  defp output_schema do
    %{
      type: "object",
      additionalProperties: false,
      required: ["archetypes"],
      properties: %{
        archetypes: %{
          type: "array",
          items: %{
            type: "object",
            additionalProperties: false,
            required: ["colors", "archetype", "altitude", "key_mechanics", "tier"],
            properties: %{
              colors: %{type: "string"},
              archetype: %{type: "string"},
              altitude: %{type: "string", enum: ["strategic", "mechanical"]},
              key_mechanics: %{type: "array", items: %{type: "string"}},
              tier: %{type: "string", enum: ["primary", "support", "fringe"]}
            }
          }
        }
      }
    }
  end

  defp detect(card, kws, re) do
    # Search rules text AND the type line, so typal detectors match both a card's
    # own creature type and cards that reference it ("Villains you control ...").
    text = String.downcase((card.oracle_text || "") <> " " <> (card.type_line || ""))

    Enum.any?(kws, &(&1 in (card.keywords || []))) or
      (re != nil and Regex.match?(re, text))
  end

  defp synthesis_prompt(evidence) do
    """
    You are analyzing a Magic: the Gathering draft environment to discover its archetypes.

    #{Reference.taxonomy_prompt()}

    EVIDENCE from the actual card pool:
    #{evidence}

    How to read the evidence:
    - distinctiveness = share of a theme's cards playable in exactly that color pair (1.0 = only there); gold = signpost cards of exactly that pair.
    - SET KEYWORDS are the mechanics actually in this set. Some may be NEW keywords you don't recognize — if one is concentrated in a color or color pair, it is very likely that archetype's defining theme; infer its role from where it clusters.
    - MULTICOLOR SIGNALS flag themes whose cards span 3+ colors — these indicate wedge/shard or 5-color "domain" archetypes the two-color analysis cannot capture.

    Identify the archetypes this environment supports:
    - FIRST check the THREE-COLOR GROUP EVIDENCE. If several triples have many dedicated three-color cards, this is a WEDGE/SHARD "family" set (like New Capenna or Alara): the ~5 three-color families ARE the primary archetypes — report them with colors like "WUB", tier "primary". In that case the two-color pairs are sub-parts of the families; report only the pairs that stand as their own archetype, as "support"/"fringe". Do NOT flatten a three-color family into a two-color pair.
    - Otherwise (a two-color set), give an archetype for each of the ten color pairs, using the TIER to express strength: "primary" / "support" / "fringe". A college set has a few primary pairs and several weaker ones — express that with tiers, don't drop the weak pairs.
    - Either way, add any MONO-color and MULTICOLOR (5-color "domain") archetypes the evidence supports. A strong 5-color archetype is a first-class result.
    - Check TYPAL THEMES: a creature type with payoffs is a typal archetype — NAME IT AFTER THE TYPE (e.g. "BR Villains", "GW Heroes"), in the colors the type concentrates in, not merely after the enabler mechanic (a Villains deck is "Villains", not "sacrifice"). Fold the enabling mechanic into key_mechanics.
    - Check RECURRING RULES-TEXT PHRASES: these capture build-around archetypes that are neither keywords nor types. When a phrase concentrates in a color pair, name that pair's archetype after the CONDITION it describes (e.g. "UB draw-your-second-card", "GB creatures-in-graveyard"), not a generic mechanic. These often ARE the real archetype where the pair otherwise looks generic.
    - Prefer a strategic name (tempo, aggro, control) when a cluster of mechanics co-occurs; use a specific mechanic name — INCLUDING a new set keyword — when one clearly dominates.

    Output JSON: {"archetypes":[{"colors":"WB" or "WUBRG" or "mono-R" etc.,"archetype":"...","altitude":"strategic|mechanical","key_mechanics":["..."],"tier":"primary|support|fringe"}, ...]}
    """
  end
end
