defmodule DeckManager do
  @decks [
    {"jetmir","4T4sW6V7JUSmN7OpnQ_hrQ", "a89a5213-f8c6-4d19-a5d1-bed98927932a"},
    {"vampires", "jOUImhiaykKSYanHfKmkLA", "28309948-82fd-41f6-ab59-c18e3689e77d"},
    {"morphs", "RX85WnSoI0KVaeQhOJ8wQA", "cbc7f5e6-9ec9-4a65-9308-4a529df379be"},
    {"henzie","l4YgSzpNmkG-UpBAuusAhg",  "1d47b6aa-b250-48e0-abd6-29b83286d34d"},
    {"slug", "3F4O9kcJ1Ea6YK0wPlUSSw", "eb09e94c-031d-411f-8301-0592285445cf"},
    {"monarch", "aHQmX2i_i0-hUQpdq0ta5w", "d5af5f3f-60ef-442e-a378-ac21792a1471"},
    {"aesi", "x3NtuV2jeEKPVA8YJVwkjA", "10f01741-98b9-4741-a9ad-7d31419ec516"},
    {"wanderer", "IoR8Jb5aB0ulmNOtWs5RZg", "e59cf956-680f-436a-b200-068f5962eaf1"},
    {"mishra", "ynyDvRw8G0Kmrajlp_UegA", "a735961f-9d0e-4fa7-8ca8-7035e88b06d6"},
    {"aristocats", "TYqGCS46qEaJMRKsasgcCQ", "be34ece7-5d32-44c3-b0e4-fa452b151cbc"},
    {"shrines", "YontiLZZZEmugFVEqOhXKA", "828cf477-a6f5-450d-b14b-7b74f1dde4cb"},
    {"ur_dragon", "KSVzZ4Os-UKKFXud4-5Vnw", "acc8bcd4-3eea-4ada-9a4e-a70b43623366"},
    {"dinos", "3Ekcem0mLk6xskQ8U5FJBg", "b80cc791-fcd2-4abc-af12-e7d8b18240f0"},
    {"eldrazi", "sB9e88BQ5UqFwb6tBUS2_w", "ae56d72e-baeb-4dee-9719-befc8c4d2256"},
    {"slivers", "G69IYzuFrkKvwQMumlgJog", "0c02b3ee-7672-4446-8178-b1fe4005a0ae"},
    {"meria", "Bu_ZwfjumUuFD1KuH2_FqQ", "40faed00-3b8a-4fbc-a711-aa8f753f1ab0"},
    {"bant_tokens", "1CtjbDS54kOSqeGlg2t22Q", "ff27a0e1-a95e-4d84-951e-a491ab20f1e4"},
    {"korvold", "z3o8vEq1lEm0sk7cGP9_9g", "74060e7a-59a6-4e84-877f-9ff761c4237b"},
    {"x_spells", "i1LRiXwbGEy1FC6weByOdQ", "f9c228f7-a0fa-4043-ab01-6505e1218c64"},
    {"merfolk", "ekHtx3vytky4yfEHOIpi2A", "0e516b67-5914-40fe-8bc3-31aaf4d63b73"},
    #{"clues", "KKyqOseMpUqZDN1HrhXDKg", "15839e34-90bf-404d-a30b-3f2d0ad024e8"},
    #{"mw_control", "j8XE7zIQ70O5vRXmD5Ua3g", "bcad72f6-57ea-474d-aef7-a19a9f74931f"},
    #{"mirko", "yYJUeFoCNEaoTg8kBQgt6w", "cfcdd050-f39b-4302-8689-5b244bb2ddfd"},
    #{"doric", "r-Uw7LJz-EC5xeTvSLxcqg", "abd873c1-6927-422e-aef8-269d4d6e92d4"},
    #{"chatterfang", "qEQ49yCVEUqgPw9CG6w3cw", "e6c047ef-21c6-45d6-91a9-a7217d324de0"},
    #{"nazgul", "qp4inpYaK0Sm0gpwS0XXqQ", "80b455f0-e71b-4cb2-8186-1d594c8504ea"},
    #{"thalrog", "pXSEOh3nJUun86gLXS-DmQ", "710dd6ff-eebe-40c8-b4ef-ab416d2b616c"},
    #{"knights", "5F_piVq7KUKAwdAP2tw9Rw", "f4990f31-316c-4447-991d-a6aa77fabb7e"},
    #{"galadriel_cedh", "WT-etujvYUWLAa_ux-wUgA", "c20fbf07-be33-482f-996f-3a8d9800ff9b"},
  ]

  def run() do
    build_decks()
  end

  def download() do
    Enum.each(@decks, fn {deck, id, export_id} ->
      deck_list =
        id
        |> list_url(export_id)
        |> Req.get!()
        |> Map.get(:body)
        |> String.split("SIDEBOARD:")
        |> case do
          [deck_list] -> deck_list
          [deck_list, _] -> deck_list
        end
        |> String.trim_trailing()

      count =
        deck_list
        |> String.split("\n")
        |> Enum.reduce(0, fn card, acc ->
          regex = ~r/(\d*) (.*) \((.*)\) (\d*)/
          [_, count, _, _set, _collector_number] = Regex.run(regex, card)
          {count, _} = Integer.parse(count)
          count + acc
        end)

      if count == 100 do
        File.write!("decks/#{deck}.txt", deck_list)
      else
        IO.puts("Could not download #{deck} - Invalid number of cards: #{count}")
      end

      :timer.sleep(1000)
    end)
  end

  def run(deck) do
    update_deck(deck)
  end

  defp build_decks() do
    collection = read_csv("decks/collection.csv")

    Enum.reduce(@decks, collection, fn {deck, _, _}, updated_collection ->
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
    deck_names = Enum.map(@decks, fn {name, _, _} -> name end)
    decks = Enum.reverse(deck_names) -- [deck]
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
                case String.split(line, " (") do
                  [card, _] -> card
                  [card] -> card
                end
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
        card =
          case String.split(line, " (") do
            [card, _] -> card
            [card] -> card
          end

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

  defp list_url(deck_id, export_id) do
    "https://api2.moxfield.com/v2/decks/all/#{deck_id}/export?format=full&exportId=#{export_id}"
  end
end
