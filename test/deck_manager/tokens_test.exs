defmodule DeckManager.TokensTest do
  use ExUnit.Case, async: true

  alias DeckManager.Tokens

  describe "identifiers/1" do
    test "reads the set and collector number Scryfall indexes on" do
      {[card], []} = Tokens.identifiers("1 Kotis, the Fangkeeper (TDM) 202\n")

      assert card == %{name: "Kotis, the Fangkeeper", set: "tdm", number: "202"}
    end

    test "keeps collector numbers that aren't plain integers" do
      {cards, []} =
        Tokens.identifiers("""
        1 Arcane Denial (ALL) 22a
        1 Aqueous Form (PLST) THS-39
        """)

      assert Enum.map(cards, & &1.number) == ["22a", "THS-39"]
    end

    test "counts above one still describe a single printing" do
      {[card], []} = Tokens.identifiers("7 Forest (TDM) 285")

      assert card.name == "Forest"
    end

    test "normalizes the split-card separator the exports use" do
      {[card], []} = Tokens.identifiers("1 Fire / Ice (MH2) 290")

      assert card.name == "Fire // Ice"
    end

    test "returns unparseable lines instead of dropping them" do
      {[card], unparsed} = Tokens.identifiers("1 Swan Song (THS) 51\nnot a decklist line\n")

      assert card.name == "Swan Song"
      assert unparsed == ["not a decklist line"]
    end
  end

  describe "render/1" do
    test "describes a creature token with its stats and color" do
      assert Tokens.render([{squirrel(), ["Chatterfang, Squirrel General", "Deranged Hermit"]}]) ==
               """
               Squirrel (1/1 green Creature — Squirrel)
                   Chatterfang, Squirrel General
                   Deranged Hermit
               """
    end

    test "sorts sources so an unchanged deck renders identically" do
      assert Tokens.render([{squirrel(), ["Deranged Hermit", "Chatterfang, Squirrel General"]}]) ==
               Tokens.render([{squirrel(), ["Chatterfang, Squirrel General", "Deranged Hermit"]}])
    end

    test "leaves the color off a non-creature token" do
      treasure = %{
        "name" => "Treasure",
        "type_line" => "Token Artifact — Treasure",
        "colors" => []
      }

      assert Tokens.render([{treasure, ["Old Gnawbone"]}]) ==
               "Treasure (Artifact — Treasure)\n    Old Gnawbone\n"
    end

    test "calls a colorless creature token colorless" do
      eldrazi = %{
        "name" => "Eldrazi Spawn",
        "type_line" => "Token Creature — Eldrazi Spawn",
        "power" => "0",
        "toughness" => "1",
        "colors" => []
      }

      assert Tokens.render([{eldrazi, ["Basking Broodscale"]}]) =~
               "Eldrazi Spawn (0/1 colorless Creature — Eldrazi Spawn)"
    end

    test "describes both sides of a double-faced token" do
      token = %{
        "name" => "Human // Wolf",
        "layout" => "double_faced_token",
        "type_line" => "Token Creature — Human // Token Creature — Wolf",
        "power" => nil,
        "toughness" => nil,
        "colors" => nil,
        "card_faces" => [
          %{
            "name" => "Human",
            "type_line" => "Token Creature — Human",
            "power" => "1",
            "toughness" => "1",
            "colors" => ["W"]
          },
          %{
            "name" => "Wolf",
            "type_line" => "Token Creature — Wolf",
            "power" => "2",
            "toughness" => "2",
            "colors" => ["G"]
          }
        ]
      }

      assert Tokens.render([{token, ["Tovolar's Huntmaster"]}]) =~
               "Human // Wolf (1/1 white Creature — Human // 2/2 green Creature — Wolf)"
    end

    test "labels a copy token, which has no type beyond being a token" do
      copy = %{"name" => "Copy", "type_line" => "Token", "colors" => []}

      assert Tokens.render([{copy, ["Faerie Artisans"]}]) =~ "Copy (copy)"
    end

    test "names every color of a multicolored token" do
      token = %{
        "name" => "Zombie Wizard",
        "type_line" => "Token Creature — Zombie Wizard",
        "power" => "2",
        "toughness" => "2",
        "colors" => ["U", "B"]
      }

      assert Tokens.render([{token, ["Wilhelt, the Rotcleaver"]}]) =~ "(2/2 blue/black"
    end
  end

  defp squirrel do
    %{
      "name" => "Squirrel",
      "type_line" => "Token Creature — Squirrel",
      "power" => "1",
      "toughness" => "1",
      "colors" => ["G"]
    }
  end
end
