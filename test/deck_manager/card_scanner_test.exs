defmodule DeckManager.CardScannerTest do
  use ExUnit.Case, async: true

  alias DeckManager.CardScanner

  describe "expand_refs/1" do
    setup do
      dir =
        Path.join(System.tmp_dir!(), "card_scanner_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(Path.join(dir, "nested"))
      on_exit(fn -> File.rm_rf!(dir) end)
      {:ok, dir: dir}
    end

    test "replaces a directory with the image files inside it, sorted", %{dir: dir} do
      for name <- ["b.jpg", "a.png", "c.JPEG"], do: File.touch!(Path.join(dir, name))

      assert CardScanner.expand_refs(dir) == [
               Path.join(dir, "a.png"),
               Path.join(dir, "b.jpg"),
               Path.join(dir, "c.JPEG")
             ]
    end

    test "ignores non-images and subdirectories", %{dir: dir} do
      File.touch!(Path.join(dir, "photo.jpg"))
      File.touch!(Path.join(dir, "notes.txt"))
      File.touch!(Path.join(dir, "nested/deep.jpg"))

      assert CardScanner.expand_refs(dir) == [Path.join(dir, "photo.jpg")]
    end

    test "passes files, URLs and inline images through untouched", %{dir: dir} do
      File.touch!(Path.join(dir, "one.jpg"))
      file = Path.join(dir, "one.jpg")
      inline = {"image/png", "YmFzZTY0"}

      assert CardScanner.expand_refs([file, "https://example.com/cards.jpg", inline]) ==
               [file, "https://example.com/cards.jpg", inline]
    end

    test "mixes expanded directories with individually named images", %{dir: dir} do
      for name <- ["a.jpg", "b.jpg"], do: File.touch!(Path.join(dir, name))

      assert CardScanner.expand_refs(["front.jpg", dir]) == [
               "front.jpg",
               Path.join(dir, "a.jpg"),
               Path.join(dir, "b.jpg")
             ]
    end

    test "returns an empty list for a directory holding no images", %{dir: dir} do
      File.touch!(Path.join(dir, "notes.txt"))

      assert CardScanner.expand_refs(dir) == []
    end
  end
end
