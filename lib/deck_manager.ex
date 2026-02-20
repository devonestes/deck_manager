defmodule DeckManager do
  @decks [
    # {"thrasios_yoshimaru", "Bdwllw3tYka3tSfVrO6K5w", "d8b70926-1071-4c85-ac12-3b23ee79399b"},
    {"vampires", "jOUImhiaykKSYanHfKmkLA", "28309948-82fd-41f6-ab59-c18e3689e77d"},
    {"morphs", "RX85WnSoI0KVaeQhOJ8wQA", "cbc7f5e6-9ec9-4a65-9308-4a529df379be"},
    {"henzie", "l4YgSzpNmkG-UpBAuusAhg", "1d47b6aa-b250-48e0-abd6-29b83286d34d"},
    # {"jetmir", "4T4sW6V7JUSmN7OpnQ_hrQ", "a89a5213-f8c6-4d19-a5d1-bed98927932a"},
    {"5c_eldrazi", "05p1hDvFX0C63tM3pfe2LA", "fc411984-9974-44fe-9959-5108a32fb532"},
    {"aesi", "x3NtuV2jeEKPVA8YJVwkjA", "10f01741-98b9-4741-a9ad-7d31419ec516"},
    {"mishra", "ynyDvRw8G0Kmrajlp_UegA", "a735961f-9d0e-4fa7-8ca8-7035e88b06d6"},
    # {"monarch", "aHQmX2i_i0-hUQpdq0ta5w", "d5af5f3f-60ef-442e-a378-ac21792a1471"},
    {"shrines", "YontiLZZZEmugFVEqOhXKA", "828cf477-a6f5-450d-b14b-7b74f1dde4cb"},
    {"gitrog_ride", "wo9B3RfmDk-HnA_ywmH9NQ", "23d12b36-bb8b-4e6f-9f9a-07b9eafcb5d0"},
    {"hare_apparant", "juBb7nCb4UuPDDrc0PHp3Q", "6e7d9747-56d6-40c6-a0e1-27bb6822bae0"},
    # {"bant_tokens", "1CtjbDS54kOSqeGlg2t22Q", "ff27a0e1-a95e-4d84-951e-a491ab20f1e4"},
    {"wanderer", "IoR8Jb5aB0ulmNOtWs5RZg", "e59cf956-680f-436a-b200-068f5962eaf1"},
    {"ur_dragon", "KSVzZ4Os-UKKFXud4-5Vnw", "acc8bcd4-3eea-4ada-9a4e-a70b43623366"},
    {"moogles", "8o8fBI0BcUWZrUH0Ixr_Vg", "e122a676-348f-4b85-b253-2b2036184d31"},
    {"terra", "HOYxYwvKpUS9DEKGKbSo1Q/", "469a46e4-84bd-4c72-a802-e10b52347ab8"},
    # {"cloud", "lDXJ9pEYKE6nDBQM0PFftw", "f2e054fc-60fe-43a4-b4a5-d99ae5cabce4"},
    {"slivers", "G69IYzuFrkKvwQMumlgJog", "0c02b3ee-7672-4446-8178-b1fe4005a0ae"},
    # {"storm_keruga", "GyHvudWmvkOgn3jMS4haqQ", "8e84f597-a92e-46ea-bfff-302db88991b1"},
    {"doric", "r-Uw7LJz-EC5xeTvSLxcqg", "abd873c1-6927-422e-aef8-269d4d6e92d4"},
    # {"wolverine", "rrjD_aYBqk-KQ5dxPkOQJg", "a430ce29-b4ec-44b6-a7e7-e959b02abcba"},
    # {"optimus_prime", "pLyCNHUPG02p0v5oY7HJLQ", "1f758cc9-15db-47c5-b78d-2b8f62e83a72"},
    # {"slug", "3F4O9kcJ1Ea6YK0wPlUSSw", "eb09e94c-031d-411f-8301-0592285445cf"},
    # {"felix_five_boots", "eJaeGUes4kC8XAqlKlyfEA", "bb40196d-9440-4d5e-9448-582e2d704f18"},
    # {"meria", "Bu_ZwfjumUuFD1KuH2_FqQ", "40faed00-3b8a-4fbc-a711-aa8f753f1ab0"},
    # {"aristocats", "TYqGCS46qEaJMRKsasgcCQ", "be34ece7-5d32-44c3-b0e4-fa452b151cbc"},
    {"dinos", "3Ekcem0mLk6xskQ8U5FJBg", "b80cc791-fcd2-4abc-af12-e7d8b18240f0"},
    {"kudo_hydras", "IC5cJBoBUUaQm9lrskUF6A", "51a8d379-9bc2-4f10-b584-68695873c4f8"},
    # {"rusko", "M1VrL9dGFUiGiBL8eVTLqA", "d6aee0a6-2152-41c9-937f-6e06d6e16a45"},
    # {"izzet_spells", "HDyCBqmROkW0McecXAyHlQ", "87941965-d7b5-4e8b-996c-438ad40c6933"},
    # {"wolverine_3_drops", "JjsS9GSxWEq4JUP2Wpgk1A", "aaa89c83-9ecf-4bbc-b339-5ae439d46bad"},
    # {"eldrazi", "sB9e88BQ5UqFwb6tBUS2_w", "ae56d72e-baeb-4dee-9719-befc8c4d2256"},
    # {"mono_blue_aggro", "v9iSDv4nO0im3LQ2sgpm0g", "3c6ed9e8-51d7-449e-be16-dbed52c101d8"},
    # {"korvold", "z3o8vEq1lEm0sk7cGP9_9g", "74060e7a-59a6-4e84-877f-9ff761c4237b"},
    # {"x_spells", "i1LRiXwbGEy1FC6weByOdQ", "f9c228f7-a0fa-4043-ab01-6505e1218c64"},
    # {"merfolk", "ekHtx3vytky4yfEHOIpi2A", "0e516b67-5914-40fe-8bc3-31aaf4d63b73"},
    {"omo", "YYF3-rUpU02AHaNF9AnSbg", "cda4a737-1336-40a2-9e26-880d4984462b"},
    {"kotis", "9FkAIHVAsUG4ebZGjsIlIw", "93ebcd39-823e-4c7f-8e29-f485e371fb8e"},
    {"bre", "tvofERlUL0C89KgfU02wYw", "72e60645-b2d1-45c8-aed8-c8dc011e53ce"},
    {"toph_lands", "qdK3zk6PLUOsQFggu0J4XQ", "a7e487ba-ae40-4b70-af6a-ed39d8072241"},
    # {"doran", "ApmbqKuzXkyR9r0VeX9r4Q", "7af6f4a7-ba2f-4a88-adfc-2e45be4d8626"},
    # {"vincent_voltron", "36wJSLbar0qFUjR3SAsazw", "c7ee1c30-2e40-4663-8fa5-8d4e2a0bc4cc"},
    # {"sephiroth_sac", "aZNHRA_KiU6R56T9Z7XdAA", "ea90e3a1-d286-47d0-aff9-85b8d2730a12"},
    # {"tifa_stompy", "iQf8273Hukyf0NFCZA32pQ", "0adff594-63d2-4ad0-8bef-273f008405d0"},
    # {"xolatoyac", "g1PTPNYs0UmFKpPxsOLBQA", "b44449d2-02f4-4aba-ab18-deeaba6a9cdc"},
    # {"sab-sunen", "Ezeldah8H0udTJCVxfYsBA", "994fe8fe-71aa-48d5-9485-150b080396b9"},
    # {"choco", "2Fio87RaIkaTIg2N6ovUpA", "93ded386-7c0c-45e0-9a96-52c1a7176e83"},
    # {"teysa", "3zN74rEwT02LSzkGVjj_Bw", "089a878e-6eb2-4f38-8862-1d7523d0e1b3"},
    # {"jodah", "xs7gc_AUpEqPpXR5SwvH2Q", "05df83ec-eccb-417d-ad64-5165fd25b8d8"},
    # {"tidus", "oOhw8ETkzkSM72XRneYQTQ", "1dcb8231-55a7-4938-8d01-f11393242404"},
    # {"esper_burn", "8he34yiaaUSbSmKWkCJfXQ", "fa798629-f6ed-473d-a9cd-c48d7710240c"},
    # {"terra_enchantments", "rMmtyYRjzk6vrYkX6aKJNQ", "51fa765c-598a-48db-af07-2fd3ab76c261"},
    # {"yuna_reanimator", "U4w32V60s0S5u4bM6MaPeg", "9553c3e5-6f04-4d14-b8b8-a70bfef0c479"},
    # {"vivi", "Ri_UlLsvF0anCYEfeJjcVg", "db41a2f1-6a7f-448f-b7ae-de22a750d6cd"},
    # {"deadpool", "yRYOXCFLp0GXzOpeFMDdnA", "8536484d-edf0-4d03-bb2e-e15f1eda5802"},
    # {"calamity", "ORpkt_O3G0eqHh0I6LY17g", "f20cd746-585f-478d-905f-b9c14b2b3ba6"},
    # {"minsc", "45dW6KPB7kmtB10-uxlDPg", "e395d3ca-ba82-43eb-8baf-ca0bd566bcd6"},
    # {"necrobloom", "Nkrcetw3M0y826ix5mFcVQ", "b6ae8023-4996-4f72-af4f-5c93a8a98c25"},
    # {"valgavoth", "TjO8egzemkKP9ieqcIlKvw", "b8d5fa18-4867-442f-9cd2-b6c8cf87d09a"},
    # {"bumbleflower", "0WTqKDgp80mXRHYnoL_vLw", "1d88fd10-377c-465a-b36c-3d6d325e9cc4"},
    # {"sauron", "WQxkKSEhtkKzPDsSs0O2xA", "b46ef84e-5532-4695-9f26-e2580315268e"},
    # {"breya", "H3-4JrWoi0mUdU-0WOJeSw", "1fcc95f9-4256-4557-9265-487153a331bd"},
    # {"bello", "-QsvG9tl8EaN277EkwtBTw", "1557dceb-cb08-4c08-921a-893a0c0ac8e1"},
    # {"goyfs", "zlM5lMPXqEu88EgNmF-h8A", "a6e9261f-3165-4a08-bcab-1bf86cf3280e"},
    # {"clues", "KKyqOseMpUqZDN1HrhXDKg", "15839e34-90bf-404d-a30b-3f2d0ad024e8"},
    # {"mw_control", "j8XE7zIQ70O5vRXmD5Ua3g", "bcad72f6-57ea-474d-aef7-a19a9f74931f"},
    # {"mirko", "yYJUeFoCNEaoTg8kBQgt6w", "cfcdd050-f39b-4302-8689-5b244bb2ddfd"},
    # {"chatterfang", "qEQ49yCVEUqgPw9CG6w3cw", "e6c047ef-21c6-45d6-91a9-a7217d324de0"},
    # {"nazgul", "qp4inpYaK0Sm0gpwS0XXqQ", "80b455f0-e71b-4cb2-8186-1d594c8504ea"},
    # {"thalrog", "pXSEOh3nJUun86gLXS-DmQ", "710dd6ff-eebe-40c8-b4ef-ab416d2b616c"},
    # {"knights", "5F_piVq7KUKAwdAP2tw9Rw", "f4990f31-316c-4447-991d-a6aa77fabb7e"},
    # {"storm", "5QhHPYUuA0WaXwbL1L9JXg", "f90e064f-a71a-48ef-856f-0eab72cd5e8e"},
    # {"galadriel_cedh", "WT-etujvYUWLAa_ux-wUgA", "c20fbf07-be33-482f-996f-3a8d9800ff9b"},
    # {"dimir_standard", "-htf3CURw0qUOSaKDyHfkw", "9ae96343-774f-42aa-83a2-47da2aa26b4e"},
    # {"esper_pixie", "YMpYPatCsEqzxN__9hKB0w", "02694376-98d0-4225-9697-73e864a27c6e"},
    {"dandan", "vN9isPEhfUuM3UUh7JCHJg", "800bbb43-8c98-4126-80d3-8a2ae9991d7c"},
    # {"peasant_cube", "xaM0NeOpV02u1g3LaG7nXQ", "ee59e00e-f986-468a-b751-44b878eaa5b1"},
    # {"pauper_cube", "xTLumPuQs0e-4oWb2izZyw", "a615477e-c305-484a-b10b-eca8200aa213"},
    # {"final_fantasy_remastered", "LKCKJ78Ao0ibohPEq2QRlQ", "2535f467-fd2d-4157-a395-b19fd6520c46"},
    # {"duskmourn_remastered", "In_QeFJrrk-6lenOjdG73w", "49cc2a21-50bd-4e09-9baa-d8740fb39c99"},
    {"temur_cube", "9aAuKWFZv0iOIzb_dHaQRQ", "e084d46c-ccdf-4bd9-a461-12711b6cb375"}
    # {"cube", "mU2WbFAfmk6iB0MJxIt-fg", "c602d42e-df1b-4565-9d9f-0b763aac6e6d"}
  ]

  def run() do
    build_decks()
  end

  def show_remaining() do
    build_decks() |> write_unused()
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

      if count == 100 or count > 150 or count <= 80 do
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

  def diff(first, second) do
    first_list = read_txt("decks/#{first}.txt")
    second_list = read_txt("decks/#{second}.txt")

    IO.puts("""
    Cards in #{first} not in #{second}:
      #{format_diff(first_list -- second_list)}

    Cards in both #{first} and #{second}:
      #{format_diff(Enum.filter(first_list, &(&1 in second_list)))}
    """)
  end

  defp format_diff(list) do
    list |> Enum.reverse() |> Enum.join("\n  ")
  end

  defp build_decks() do
    collection = read_csv("decks/collection.csv")

    Enum.reduce(@decks, collection, fn {deck, _, _}, updated_collection ->
      file = read_txt("decks/#{deck}.txt")

      collection =
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

      collection
    end)
  end

  defp update_deck(deck) do
    deck_names = Enum.map(@decks, fn {name, _, _} -> name end)
    decks = Enum.reverse(deck_names) -- [deck]
    path = "built_decks/#{deck}.txt"

    {:ok, built_deck} = File.read(path)
    built_deck = built_deck |> String.trim() |> String.split("\n")

    {proxies, real} =
      Enum.split_with(built_deck, fn line -> String.ends_with?(line, "(PROXY)") end)

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
      name = name |> String.replace(" / ", " // ") |> normalize_name()
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

  defp write_unused(collection) do
    scryfall_data =
      scryfall_bulk_data_api()
      |> Req.get!()
      |> Map.get(:body)
      |> Map.get("download_uri")
      |> Req.get!()
      |> Map.get(:body)
      |> Enum.map(fn entry ->
        Map.take(entry, ["name", "rarity", "edhrec_rank", "type_line"])
      end)

    sorted =
      collection
      |> Enum.reduce([], fn {card, remaining}, acc ->
        non_proxy_count = Enum.count(remaining, fn inner -> inner["Proxy"] == false end)

        if non_proxy_count > 0 do
          enriched = Enum.find(scryfall_data, fn data -> data["name"] == card end)
          [{enriched, non_proxy_count} | acc]
        else
          acc
        end
      end)
      |> Enum.sort_by(fn {card_data, _} -> card_data["edhrec_rank"] end, :desc)

    formatted_everything =
      Enum.reduce(sorted, "", fn {card_data, non_proxy_count}, acc ->
        "#{non_proxy_count},#{card_data["name"]},#{card_data["type_line"]},#{card_data["rarity"]}\n#{acc}"
      end)

    File.write!("decks/collection_remaining.txt", formatted_everything)

    for type <- [
          "land",
          "creature",
          "instant",
          "sorcery",
          "enchantment",
          "artifact",
          "planeswalker",
          "battle"
        ] do
      formatted =
        sorted
        |> Enum.filter(fn {card_data, _} -> String.downcase(card_data["type_line"]) =~ type end)
        |> Enum.reduce("", fn {card_data, non_proxy_count}, acc ->
          "#{non_proxy_count},#{card_data["name"]},#{card_data["type_line"]},#{card_data["rarity"]}\n#{acc}"
        end)

      File.write!("decks/collection_remaining_#{type}.txt", formatted)
    end

    for rarity <- ["mythic", "rare", "uncommon", "common"] do
      formatted =
        sorted
        |> Enum.filter(fn {card_data, _} -> card_data["rarity"] == rarity end)
        |> Enum.reduce("", fn {card_data, non_proxy_count}, acc ->
          "#{non_proxy_count},#{card_data["name"]},#{card_data["type_line"]},#{card_data["rarity"]}\n#{acc}"
        end)

      File.write!("decks/collection_remaining_#{rarity}.txt", formatted)
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
    proxies = Enum.reverse(proxies)
    real = Enum.reverse(real)
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

  defp scryfall_bulk_data_api() do
    "https://api.scryfall.com/bulk-data/oracle_cards"
  end

  defp normalize_name("Henneth Annûn"), do: "Reflecting Pool"
  defp normalize_name("The Party Tree"), do: "The Great Henge"
  defp normalize_name("Bucklebury Ferry"), do: "Oboro, Palace in the Clouds"
  defp normalize_name("Rick, Steadfast Leader"), do: "Greymond, Avacyn's Stalwart"
  defp normalize_name("The Dead Marshes"), do: "Urborg, Tomb of Yawgmoth"
  defp normalize_name("Firion, Swordmaster"), do: "Sram, Senior Edificer"
  defp normalize_name("Morgul-Knife"), do: "Shadowspear"
  defp normalize_name("Squall Leonhart"), do: "Danitha Capashen, Paragon"
  defp normalize_name("Storm's Will"), do: "Jeska's Will"
  defp normalize_name("Adamantium Bonding Tank"), do: "The Ozolith"
  defp normalize_name("Astral Titan"), do: "Primeval Titan"
  defp normalize_name("Endwalker"), do: "Brainstorm"
  defp normalize_name("Terra Branford"), do: "Urza, Lord High Artificer"
  defp normalize_name("Wild Rose Rebellion"), do: "Counterspell"
  defp normalize_name("The Strahl"), do: "Smuggler's Copter"
  defp normalize_name("Vayne Carudas Solidor"), do: "Fynn, the Fangbearer"

  defp normalize_name("Doric, Nature's Warden // Doric, Owlbear Avenger"),
    do: "Casal, Lurkwood Pathfinder // Casal, Pathbreaker Owlbear"

  defp normalize_name("Dr. John Seward"), do: "Torens, Fist of the Angels"
  defp normalize_name("Newfound Adventure"), do: "Farseek"
  defp normalize_name(name), do: name
end
