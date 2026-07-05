defmodule DeckManager.TagsTest do
  use ExUnit.Case, async: true

  alias DeckManager.Tags

  describe "validate/1" do
    test "accepts a well-formed response and returns atom keys" do
      raw = %{
        "removal" => "unconditional",
        "removal_speed" => "instant",
        "card_advantage" => "neutral",
        "role" => "standalone",
        "evasive" => false,
        "interaction" => true,
        "functions" => ["burn"],
        "archetypes" => ["control"]
      }

      assert {:ok, tags} = Tags.validate(raw)
      assert tags.removal == "unconditional"
      assert tags.functions == ["burn"]
      assert tags.interaction == true
    end

    test "drops list values outside the vocabulary but keeps valid ones" do
      raw = base(%{"functions" => ["burn", "not_a_real_function", "ramp"]})

      assert {:ok, tags} = Tags.validate(raw)
      assert tags.functions == ["burn", "ramp"]
    end

    test "de-duplicates list values" do
      raw = base(%{"archetypes" => ["control", "control", "tokens"]})

      assert {:ok, tags} = Tags.validate(raw)
      assert tags.archetypes == ["control", "tokens"]
    end

    test "rejects an out-of-range enum so the caller can retry" do
      raw = base(%{"removal" => "sometimes"})

      assert {:error, {:bad_enum, "removal", "sometimes"}} = Tags.validate(raw)
    end

    test "coerces non-boolean flags to false" do
      raw = base(%{"evasive" => "yes"})

      assert {:ok, tags} = Tags.validate(raw)
      assert tags.evasive == false
    end

    test "defaults missing list fields to empty" do
      raw = base(%{}) |> Map.drop(["functions", "archetypes"])

      assert {:ok, tags} = Tags.validate(raw)
      assert tags.functions == []
      assert tags.archetypes == []
    end

    test "rejects non-map input" do
      assert {:error, :not_a_map} = Tags.validate("nope")
    end
  end

  # A minimally valid response, overridden per test.
  defp base(overrides) do
    Map.merge(
      %{
        "removal" => "none",
        "removal_speed" => "none",
        "card_advantage" => "neutral",
        "role" => "standalone",
        "evasive" => false,
        "interaction" => false,
        "functions" => [],
        "archetypes" => []
      },
      overrides
    )
  end
end
