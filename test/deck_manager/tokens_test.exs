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
      assert Tokens.render([squirrel()]) == "Squirrel (1/1 green Creature — Squirrel)\n"
    end

    test "gives each token a line of its own and nothing else" do
      spirit = %{squirrel() | "name" => "Spirit"}

      assert Tokens.render([squirrel(), spirit]) ==
               """
               Squirrel (1/1 green Creature — Squirrel)
               Spirit (1/1 green Creature — Squirrel)
               """
    end

    test "leaves the color off a non-creature token" do
      treasure = %{
        "name" => "Treasure",
        "type_line" => "Token Artifact — Treasure",
        "colors" => []
      }

      assert Tokens.render([treasure]) ==
               "Treasure (Artifact — Treasure)\n"
    end

    test "calls a colorless creature token colorless" do
      eldrazi = %{
        "name" => "Eldrazi Spawn",
        "type_line" => "Token Creature — Eldrazi Spawn",
        "power" => "0",
        "toughness" => "1",
        "colors" => []
      }

      assert Tokens.render([eldrazi]) =~
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

      assert Tokens.render([token]) =~
               "Human // Wolf (1/1 white Creature — Human // 2/2 green Creature — Wolf)"
    end

    test "prints the rules text that tells two same-stat tokens apart" do
      flier = %{squirrel() | "name" => "Spirit"} |> Map.put("oracle_text", "Flying")

      assert Tokens.render([flier]) =~
               "Spirit (1/1 green Creature — Squirrel) [Flying]"
    end

    test "joins a token's multiple abilities onto the one line" do
      token =
        squirrel()
        |> Map.put("oracle_text", "Flying\nWhen this creature dies, draw a card.")

      assert Tokens.render([token]) =~
               "[Flying; When this creature dies, draw a card.]"
    end

    test "drops reminder text, which is identical on every token with the keyword" do
      token =
        squirrel()
        |> Map.put("oracle_text", "Flying (This creature can't be blocked except by fliers.)")

      assert Tokens.render([token]) =~ "[Flying]"
    end

    test "says nothing where a vanilla token has nothing to say" do
      assert Tokens.render([Map.put(squirrel(), "oracle_text", "")]) =~
               "Squirrel (1/1 green Creature — Squirrel)\n"
    end

    test "attributes rules text to the face it belongs to on a double-faced token" do
      token = %{
        "name" => "Human // Wolf",
        "layout" => "double_faced_token",
        "type_line" => "Token Creature — Human // Token Creature — Wolf",
        "card_faces" => [
          %{
            "name" => "Human",
            "type_line" => "Token Creature — Human",
            "power" => "1",
            "toughness" => "1",
            "colors" => ["W"],
            "oracle_text" => ""
          },
          %{
            "name" => "Wolf",
            "type_line" => "Token Creature — Wolf",
            "power" => "2",
            "toughness" => "2",
            "colors" => ["G"],
            "oracle_text" => "Trample"
          }
        ]
      }

      assert Tokens.render([token]) =~
               "Creature — Wolf) [Wolf: Trample]"
    end

    test "leaves the boilerplate off tokens that read the same everywhere" do
      treasure = %{
        "name" => "Treasure",
        "type_line" => "Token Artifact — Treasure",
        "colors" => [],
        "oracle_text" => "{T}, Sacrifice this token: Add one mana of any color."
      }

      assert Tokens.render([treasure]) ==
               "Treasure (Artifact — Treasure)\n"
    end

    test "leaves it off a boilerplate face of a double-faced token too" do
      incubator = %{
        "name" => "Incubator // Phyrexian",
        "layout" => "double_faced_token",
        "card_faces" => [
          %{
            "name" => "Incubator",
            "type_line" => "Token Artifact — Incubator",
            "oracle_text" => "{2}: Transform this artifact."
          },
          %{
            "name" => "Phyrexian",
            "type_line" => "Token Artifact Creature — Phyrexian",
            "power" => "0",
            "toughness" => "0",
            "colors" => [],
            "oracle_text" => ""
          }
        ]
      }

      refute Tokens.render([incubator]) =~ "["
    end

    test "leaves it off a 0/0 Construct, which is always the same Karnstruct" do
      karnstruct = %{
        "name" => "Construct",
        "type_line" => "Token Artifact Creature — Construct",
        "power" => "0",
        "toughness" => "0",
        "colors" => [],
        "oracle_text" => "This creature gets +1/+1 for each artifact you control."
      }

      refute Tokens.render([karnstruct]) =~ "["
    end

    test "keeps the text on a Construct that isn't a Karnstruct" do
      construct = %{
        "name" => "Construct",
        "type_line" => "Token Artifact Creature — Construct",
        "power" => "4",
        "toughness" => "4",
        "colors" => [],
        "oracle_text" => "Trample"
      }

      assert Tokens.render([construct]) =~ "[Trample]"
    end

    test "labels a copy token, which has no type beyond being a token" do
      copy = %{"name" => "Copy", "type_line" => "Token", "colors" => []}

      assert Tokens.render([copy]) =~ "Copy (copy)"
    end

    test "names every color of a multicolored token" do
      token = %{
        "name" => "Zombie Wizard",
        "type_line" => "Token Creature — Zombie Wizard",
        "power" => "2",
        "toughness" => "2",
        "colors" => ["U", "B"]
      }

      assert Tokens.render([token]) =~ "(2/2 blue/black"
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
