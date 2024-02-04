defmodule DeckManager do
  @decks [
    "vampires",
    "slug",
    "morphs",
    "korvold",
    "monarch",
    "dinos",
    "wanderer",
    "mishra",
    "shrines",
    "ur_dragon",
    "x_spells",
    "merfolk",
    "galadriel",
    "aesi",
    "eldrazi",
    "slivers",
    "meria",
    "henzie",
    "jetmir",
    "clues",
    "mirko"
  ]

  def run() do
    build_decks()
  end

  def run(deck) do
    update_deck(deck)
  end

  defp build_decks() do
    collection = read_csv("decks/collection.csv")

    Enum.reduce(@decks, collection, fn deck, updated_collection ->
      file = read_txt("decks/#{deck}.txt")

      case build(updated_collection, file) do
        {:error, missing_cards, new_collection} ->
          IO.puts("Could not build #{deck} - missing:")

          Enum.each(missing_cards, fn card ->
            IO.puts("    #{card}")
          end)

          IO.puts("")
          new_collection

        {deck_built, new_collection} ->
          proxies = Enum.filter(deck_built, fn card -> card["Proxy"] end)
          IO.puts("Built #{deck} with #{length(proxies)} proxies")

          Enum.each(proxies, fn proxy ->
            IO.puts("    #{proxy["Name"]}")
          end)

          IO.puts("")
          write_deck(deck_built, "built_decks/#{deck}.txt")
          new_collection
      end
    end)
  end

  defp update_deck(deck) do
    decks = Enum.reverse(@decks) -- [deck]
    path = "built_decks/#{deck}.txt"

    {:ok, built_deck} = File.read(path)
    built_deck = built_deck |> String.trim() |> String.split("\n")

    {proxies, real} = Enum.split_with(built_deck, fn line -> String.ends_with?(line, "(PROXY)") end)
    proxies = Enum.map(proxies, fn line -> String.replace(line, " (PROXY)", "") end)

    {replaced, replacements} =
      Enum.reduce(proxies, [], fn card, acc ->
        deck =
          Enum.find(decks, fn deck ->
            {:ok, other} = File.read("built_decks/#{deck}.txt")
            other = other |> String.trim() |> String.split("\n")

            non_proxies =
              other
              |> Enum.reject(fn line -> String.ends_with?(line, "(PROXY)") end)
              |> Enum.map(fn line ->
                [card, _] = String.split(line, " (")
                card
              end)

            if Enum.member?(non_proxies, card) do
              {deck, card}
            else
              nil
            end
          end)

        [{deck, card} | acc]
      end)
      |> Enum.group_by(fn {deck, _} -> deck end)
      |> Enum.reduce({[], ""}, fn {deck, cards}, {replaced, replacements} ->
        real_cards = put_proxies(deck, cards)

        replacements = replacements <> "\n#{deck}\n"

        replacements =
          Enum.reduce(cards, replacements, fn {_, card}, inner ->
            inner <> "  " <> card <> "\n"
          end)
        {[real_cards | replaced], replacements}
    end)

    file =
      replaced
      |> List.flatten()
      |> Kernel.++(real)
      |> Enum.join("\n")

    File.write!(path, file)

    IO.puts(replacements)
  end

  defp put_proxies(deck, cards) do
    path = "built_decks/#{deck}.txt"

    {:ok, built_deck} = File.read(path)
    cards = Enum.map(cards, fn {_, card} -> card end)

    {proxies, real} =
      built_deck
      |> String.trim()
      |> String.split("\n")
      |> Enum.map(fn line ->
        [card, _] = String.split(line, " (")
        if Enum.member?(cards, card) do
          {line, true, card <> " (PROXY)"}
        else
          {line, false, line}
        end
      end)
      |> Enum.split_with(fn {_, replaced, _} -> replaced end)

    replaced = Enum.map(proxies, fn {line, _, _} -> line end)
    proxies = Enum.map(proxies, fn {_, _, line} -> line end)
    real = Enum.map(real, fn {_, _, line} -> line end)
    deck = Enum.sort(proxies) ++ Enum.sort(real)
    file = Enum.join(deck, "\n")
    File.write!(path, file)
    replaced
  end

  defp read_csv(path) do
    path
    |> File.stream!()
    |> CSV.decode(headers: true)
    |> Enum.map(fn {:ok, line} ->
      line
      |> Map.drop([
        "Alter",
        "Condition",
        "Foil",
        "Language",
        "Last Modified",
        "Purchase Price",
        "Tags",
        "Tradelist Count"
      ])
      |> Map.update!("Count", fn count ->
        {num, _} = Integer.parse(count)
        num
      end)
      |> Map.update!("Proxy", fn
        "True" -> true
        "False" -> false
      end)
    end)
    |> Enum.reduce(%{}, fn card, acc ->
      Map.update(acc, card["Name"], [card], fn cards ->
        [card | cards]
      end)
    end)
    |> Enum.reduce(%{}, fn {card_name, cards}, acc ->
      all_cards =
        Enum.flat_map(cards, fn card ->
          Enum.map(0..(card["Count"] - 1), fn _ ->
            Map.drop(card, ["Count"])
          end)
        end)

      Map.put(acc, card_name, all_cards)
    end)
  end

  defp read_txt(path) do
    {:ok, file} = File.read(path)

    file
    |> String.trim_trailing()
    |> String.split("\n")
    |> Enum.map(fn card ->
      regex = ~r/(\d*) (.*) \((.*)\) (\d*)/
      [_, count, name, _set, _collector_number] = Regex.run(regex, card)
      {count, _} = Integer.parse(count)
      %{"Count" => count, "Name" => name}
    end)
    |> Enum.reduce([], fn card, acc ->
      cards = Enum.map(0..(card["Count"] - 1), fn _ -> card["Name"] end)
      [cards | acc]
    end)
    |> List.flatten()
  end

  defp build(collection, deck) do
    result =
      Enum.reduce(deck, {[], [], collection}, fn card_name, {built, missing, inner_collection} ->
        case find_card(card_name, inner_collection, false) do
          {nil, _} ->
            case find_card(card_name, inner_collection, true) do
              {nil, updated_collection} ->
                {built, [card_name | missing], updated_collection}

              {card, updated_collection} ->
                {[card | built], missing, updated_collection}
            end

          {card, updated_collection} ->
            {[card | built], missing, updated_collection}
        end
      end)

    case result do
      {built, [], collection} -> {List.flatten(built), collection}
      {_, missing, collection} -> {:error, missing, collection}
    end
  end

  defp find_card(card_name, collection, proxy) do
    case collection[card_name] do
      nil ->
        {nil, collection}

      card_list ->
        case Enum.find(card_list, &(&1["Proxy"] == proxy)) do
          nil ->
            {nil, collection}

          card ->
            updated_collection =
              Map.update!(collection, card_name, fn cards -> List.delete(cards, card) end)

            {card, updated_collection}
        end
    end
  end

  defp write_deck(deck, path) do
    {proxies, real} = Enum.split_with(deck, fn card -> card["Proxy"] end)
    deck = real ++ proxies

    formatted =
      Enum.reduce(deck, "", fn card, acc ->
        case card["Proxy"] do
          true -> "#{card["Name"]} (PROXY)\n" <> acc
          false -> "#{card["Name"]}\n" <> acc
        end
      end)

    File.write!(path, formatted)
  end
end
