defmodule DeckManager.LanguageTest do
  use ExUnit.Case, async: true

  alias DeckManager.Language

  test "maps the printed collector-line code to Scryfall's" do
    assert Language.scryfall_code("DE") == "de"
    assert Language.scryfall_code(" jp ") == "ja"
    assert Language.scryfall_code("CS") == "zhs"
  end

  test "returns nil for a blank or unknown code" do
    assert Language.scryfall_code("") == nil
    assert Language.scryfall_code("XX") == nil
    assert Language.scryfall_code(nil) == nil
  end

  test "names the language the way Moxfield's import expects" do
    assert Language.moxfield_name("de") == "German"
    assert Language.moxfield_name("ja") == "Japanese"
    assert Language.moxfield_name(nil) == "English"
    assert Language.moxfield_name("xx") == "English"
  end
end
