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

    test "includes videos alongside photos", %{dir: dir} do
      for name <- ["IMG_1815.MOV", "a.jpg"], do: File.touch!(Path.join(dir, name))

      assert CardScanner.expand_refs(dir) == [
               Path.join(dir, "IMG_1815.MOV"),
               Path.join(dir, "a.jpg")
             ]
    end

    test "returns an empty list for a directory holding no images", %{dir: dir} do
      File.touch!(Path.join(dir, "notes.txt"))

      assert CardScanner.expand_refs(dir) == []
    end
  end

  describe "to_csv/1" do
    defp row(attrs) do
      Map.merge(
        %{
          position: 1,
          set: "hob",
          collector_number: "44",
          name: "A Card",
          foil: false,
          resolved: true
        },
        Map.new(attrs)
      )
    end

    test "merges identical printings into one line with a count" do
      csv = CardScanner.to_csv([row(position: 1), row(position: 2)])

      assert [_headers, line] = String.split(csv, "\n")
      assert line =~ ~s("2","2","A Card","hob")
    end

    test "keeps foil and non-foil copies of one printing apart" do
      csv = CardScanner.to_csv([row(position: 1), row(position: 2, foil: true)])

      assert [_headers, first, second] = String.split(csv, "\n")
      assert first =~ ~s("1","1")
      assert second =~ ~s("1","1")
      assert Enum.count([first, second], &(&1 =~ ~s(,"foil",))) == 1
    end

    test "leaves out rows that never resolved against Scryfall" do
      csv = CardScanner.to_csv([row(position: 1), row(position: 2, resolved: false)])

      assert [_headers, _line] = String.split(csv, "\n")
    end

    test "writes the row's language, and keeps languages of one printing apart" do
      csv = CardScanner.to_csv([row(position: 1, language: "de"), row(position: 2)])

      assert [_headers | lines] = String.split(csv, "\n")
      assert Enum.count(lines, &(&1 =~ ~s("German"))) == 1
      assert Enum.count(lines, &(&1 =~ ~s("English"))) == 1
    end

    test "sorts lines by card name" do
      rows = [
        row(position: 1, name: "Zealot"),
        row(position: 2, name: "Aardvark", collector_number: "9")
      ]

      assert [_headers, first, second] = CardScanner.to_csv(rows) |> String.split("\n")
      assert first =~ "Aardvark"
      assert second =~ "Zealot"
    end
  end

  describe "card_rows/2" do
    defp batch(n), do: Enum.map(1..n, fn i -> {"card-#{i}.jpg", 40 + i} end)

    defp read(label, attrs \\ %{}) do
      Map.merge(
        %{
          "card" => label,
          "printed_name" => "Trommelfell-Traktiererin",
          "collector_number" => "0081",
          "set" => "FRA",
          "foil_mark" => "dot",
          "language" => "DE"
        },
        attrs
      )
    end

    test "reads set, number and language, keeping the video position" do
      assert [row] = CardScanner.card_rows(batch(1), [read(1)])

      assert %{position: 41, set: "fra", collector_number: "0081", language: "de", foil: false} =
               row

      assert row.notes == []
    end

    test "marks a card foil only from a ★" do
      rows = CardScanner.card_rows(batch(2), [read(1, %{"foil_mark" => "star"}), read(2)])

      assert Enum.map(rows, & &1.foil) == [true, false]
    end

    test "notes an unreadable foil mark rather than guessing" do
      [row] = CardScanner.card_rows(batch(1), [read(1, %{"foil_mark" => "unreadable"})])

      refute row.foil
      assert [note] = row.notes
      assert note =~ "foil mark"
    end

    test "matches entries by label, so a skipped card is a blank row, not a shift" do
      rows = CardScanner.card_rows(batch(3), [read(3, %{"collector_number" => "3"}), read(1)])

      assert Enum.map(rows, & &1.collector_number) == ["0081", "", "3"]
      assert Enum.map(rows, & &1.position) == [41, 42, 43]
      assert [note] = Enum.at(rows, 1).notes
      assert note =~ "not read"
    end

    test "falls back to English for an unknown language, and says so" do
      [row] = CardScanner.card_rows(batch(1), [read(1, %{"language" => "XX"})])

      assert row.language == "en"
      assert row.notes == ["unknown language XX"]
    end
  end

  describe "low_resolution_warning/1" do
    setup do
      dir = Path.join(System.tmp_dir!(), "card_scanner_res_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      {:ok, dir: dir}
    end

    test "warns about a messaging-app sized photo", %{dir: dir} do
      path = Path.join(dir, "small.jpg")
      File.write!(path, String.duplicate("x", 170_000))

      assert CardScanner.low_resolution_warning(path) =~ "166 KB"
    end

    test "stays quiet about a full-resolution photo", %{dir: dir} do
      path = Path.join(dir, "big.jpg")
      File.write!(path, String.duplicate("x", 900_000))

      assert CardScanner.low_resolution_warning(path) == nil
    end

    test "stays quiet about URLs and inline images" do
      assert CardScanner.low_resolution_warning("https://example.com/cards.jpg") == nil
      assert CardScanner.low_resolution_warning({"image/png", "YmFzZTY0"}) == nil
    end
  end
end
