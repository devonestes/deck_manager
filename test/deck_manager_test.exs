defmodule DeckManagerTest do
  use ExUnit.Case
  doctest DeckManager

  test "greets the world" do
    assert DeckManager.hello() == :world
  end
end
