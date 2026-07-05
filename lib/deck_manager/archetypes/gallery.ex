defmodule DeckManager.Archetypes.Gallery do
  @moduledoc """
  Renders a pool's archetype assignment as a standalone HTML gallery of card
  images for visual review.

  It's a local file, not a shareable artifact, on purpose: the page references
  Scryfall's image CDN directly (`<img src>`), which needs network access the
  sandboxed artifact host forbids. Images are lazy-loaded so a 280-card set
  doesn't fetch everything at once.
  """

  alias DeckManager.Archetypes.Assignment

  # Card-frame colors for the archetype color pips.
  @pip %{
    "W" => "#fffbd5",
    "U" => "#aae0fa",
    "B" => "#cbc2bf",
    "R" => "#f9aa8f",
    "G" => "#9bd3ae"
  }

  @doc "Full HTML document for `list`'s assignment."
  def html(list, cards, archetypes) do
    assignments = Assignment.assign(cards, archetypes)
    supply = Assignment.by_archetype(assignments, archetypes)
    {lands, nonland} = Enum.split_with(Assignment.flex_cards(assignments), &land?(&1.card))

    sections =
      supply
      |> Enum.with_index()
      |> Enum.map(fn {{arch, members}, i} -> archetype_section(arch, members, i) end)

    body =
      Enum.join(sections, "\n") <>
        flex_section("flex", "Flex / role-players", nonland) <>
        flex_section("fixing", "Fixing / lands", lands)

    document(
      "#{esc(String.upcase(list))} — archetype gallery",
      "#{length(cards)} cards · #{length(archetypes)} archetypes",
      nav(supply, length(nonland), length(lands)),
      body
    )
  end

  @doc """
  HTML page of add suggestions: one section per archetype, showing the owned
  candidate cards. `sections` is `[{archetype_map, [member]}]` in the same member
  shape `Assignment.by_archetype/2` produces.
  """
  def suggestions_html(list, sections) do
    body =
      sections
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {{arch, members}, i} -> archetype_section(arch, members, i) end)

    nav =
      sections
      |> Enum.with_index()
      |> Enum.map_join("", fn {{arch, members}, i} ->
        ~s(<a href="#a#{i}">#{pips(arch["colors"])}<span>#{esc(arch["archetype"])}</span><b>#{length(members)}</b></a>)
      end)

    document(
      "#{esc(String.upcase(list))} — add suggestions",
      "owned cards that fit under-supplied archetypes",
      nav,
      body
    )
  end

  defp document(title, subtitle, nav, body) do
    """
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>#{title}</title>
    <style>#{css()}</style>
    </head>
    <body>
    <header class="top">
      <h1>#{title} <span class="sub">#{subtitle}</span></h1>
      <nav class="jump">#{nav}</nav>
    </header>
    <main>
    #{body}
    </main>
    </body>
    </html>
    """
  end

  defp nav(supply, flex_n, land_n) do
    arch_links =
      supply
      |> Enum.with_index()
      |> Enum.map_join("", fn {{arch, members}, i} ->
        ~s(<a href="#a#{i}">#{pips(arch["colors"])}<span>#{esc(arch["archetype"])}</span><b>#{length(members)}</b></a>)
      end)

    arch_links <>
      ~s(<a href="#flex"><span>Flex</span><b>#{flex_n}</b></a>) <>
      ~s(<a href="#fixing"><span>Lands</span><b>#{land_n}</b></a>)
  end

  defp archetype_section(arch, members, i) do
    """
    <section id="a#{i}" class="arch">
      <div class="head">
        <div class="pips">#{pips(arch["colors"])}</div>
        <h2>#{esc(arch["colors"])} · #{esc(arch["archetype"])}</h2>
        <span class="tier tier-#{esc(arch["tier"])}">#{esc(arch["tier"])}</span>
        <span class="count">#{length(members)} cards</span>
      </div>
      <div class="grid">
        #{Enum.map_join(members, "\n", &member_card/1)}
      </div>
    </section>
    """
  end

  defp flex_section(_id, _title, []), do: ""

  defp flex_section(id, title, entries) do
    cards = Enum.sort_by(entries, & &1.card.name)

    """
    <section id="#{id}" class="arch">
      <div class="head"><h2>#{esc(title)}</h2><span class="count">#{length(cards)} cards</span></div>
      <div class="grid">
        #{Enum.map_join(cards, "\n", fn %{card: c} -> card_fig(c, false, "") end)}
      </div>
    </section>
    """
  end

  defp member_card(m) do
    mech = Enum.join(m.matched, " · ")
    card_fig(m.card, m.role == :signpost, mech)
  end

  defp card_fig(card, signpost?, mech) do
    """
    <figure class="card#{if signpost?, do: " signpost"}">
      <img loading="lazy" src="#{esc(image_url(card))}" alt="#{esc(card.name)}">
      <figcaption>
        <span class="nm">#{esc(card.name)}</span>
        #{if mech != "", do: ~s(<span class="mech">#{esc(mech)}</span>), else: ""}
      </figcaption>
    </figure>
    """
  end

  # Real image if we captured it, else Scryfall's named-image endpoint, which
  # redirects to the current printing's image (works for cube cards whose cached
  # data predates image capture).
  defp image_url(card) do
    card.image ||
      "https://api.scryfall.com/cards/named?exact=#{URI.encode(card.name)}&format=image&version=normal"
  end

  defp pips(colors) do
    colors
    |> String.upcase()
    |> String.graphemes()
    |> Enum.filter(&Map.has_key?(@pip, &1))
    |> Enum.map_join("", fn c -> ~s(<i class="pip" style="background:#{@pip[c]}"></i>) end)
  end

  defp land?(card), do: String.contains?(card.type_line || "", "Land")

  defp esc(text) do
    text
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp css do
    """
    :root { color-scheme: dark; }
    * { box-sizing: border-box; }
    body {
      margin: 0; background: #0e1116; color: #e6e9ef;
      font: 14px/1.4 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    }
    .top {
      position: sticky; top: 0; z-index: 10; background: #0e1116ee;
      backdrop-filter: blur(8px); border-bottom: 1px solid #232a35; padding: 14px 20px;
    }
    .top h1 { margin: 0 0 10px; font-size: 20px; letter-spacing: .3px; }
    .top .sub { color: #8b93a1; font-size: 13px; font-weight: 400; margin-left: 8px; }
    .jump { display: flex; flex-wrap: wrap; gap: 6px; }
    .jump a {
      display: inline-flex; align-items: center; gap: 6px; text-decoration: none;
      color: #cdd3dc; background: #171d26; border: 1px solid #232a35; border-radius: 20px;
      padding: 4px 10px; font-size: 12px; transition: background .15s, border-color .15s;
    }
    .jump a:hover { background: #1e2632; border-color: #3a4556; }
    .jump a b { color: #8b93a1; font-weight: 600; }
    main { padding: 8px 20px 60px; max-width: 1600px; margin: 0 auto; }
    .arch { margin: 28px 0; scroll-margin-top: 96px; }
    .head { display: flex; align-items: center; gap: 10px; margin: 0 0 14px;
            border-bottom: 1px solid #232a35; padding-bottom: 8px; }
    .head h2 { margin: 0; font-size: 17px; }
    .pips { display: inline-flex; gap: 3px; }
    .pip { width: 15px; height: 15px; border-radius: 50%; display: inline-block;
           box-shadow: inset 0 0 0 1px #0006; }
    .tier { font-size: 11px; text-transform: uppercase; letter-spacing: .5px;
            padding: 2px 8px; border-radius: 10px; font-weight: 600; }
    .tier-primary { background: #1f3a2a; color: #7ee0a6; }
    .tier-support { background: #33301c; color: #ded08a; }
    .tier-fringe  { background: #2a2230; color: #c8a6dc; }
    .count { color: #8b93a1; font-size: 13px; margin-left: auto; }
    .grid { display: grid; gap: 12px;
            grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); }
    .card { margin: 0; position: relative; transition: transform .12s; }
    .card:hover { transform: translateY(-3px) scale(1.02); z-index: 5; }
    .card img { width: 100%; display: block; border-radius: 9px; background: #1a2029;
                aspect-ratio: 488/680; box-shadow: 0 2px 8px #0007; }
    .card.signpost img { box-shadow: 0 0 0 3px #f4c95d, 0 2px 10px #0009; }
    .card.signpost::after {
      content: "★"; position: absolute; top: 6px; right: 6px; color: #1a1206;
      background: #f4c95d; width: 22px; height: 22px; border-radius: 50%;
      display: grid; place-items: center; font-size: 13px; box-shadow: 0 1px 4px #0008;
    }
    figcaption { margin-top: 5px; }
    .nm { display: block; font-size: 12px; font-weight: 600; color: #e6e9ef;
          white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .mech { display: block; font-size: 10.5px; color: #7d8697; margin-top: 1px; }
    """
  end
end
