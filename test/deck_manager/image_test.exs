defmodule DeckManager.ImageTest do
  use ExUnit.Case, async: true

  alias DeckManager.Image

  describe "heic?/1" do
    test "recognises HEIC and HEIF paths regardless of case" do
      assert Image.heic?("IMG_1536.heic")
      assert Image.heic?("photo.HEIC")
      assert Image.heic?("photo.heif")
    end

    test "rejects other images, URLs and inline references" do
      refute Image.heic?("photo.jpg")
      refute Image.heic?("https://example.com/photo.heic.png")
      refute Image.heic?({"image/png", "YmFzZTY0"})
    end
  end

  describe "prepare/1" do
    test "passes URLs, inline images and non-HEIC paths through untouched" do
      inline = {"image/png", "YmFzZTY0"}

      assert Image.prepare("https://example.com/cards.jpg") ==
               {:ok, "https://example.com/cards.jpg"}

      assert Image.prepare("http://example.com/cards.jpg") ==
               {:ok, "http://example.com/cards.jpg"}

      assert Image.prepare(inline) == {:ok, inline}
      assert Image.prepare("photos/cards.jpg") == {:ok, "photos/cards.jpg"}
    end

    test "reports a missing HEIC rather than pretending it converted" do
      assert {:error, {:image_read, _path, :enoent}} = Image.prepare("nope.heic")
    end
  end

  # `sips` is macOS-only and is what does the transcoding, so the round trip is
  # only meaningful — and only compiled — where it exists.
  if System.find_executable("sips") do
    describe "prepare/1 with a real HEIC" do
      setup do
        dir = Path.join(System.tmp_dir!(), "image_test_#{System.unique_integer([:positive])}")
        File.mkdir_p!(dir)
        on_exit(fn -> File.rm_rf!(dir) end)

        # A tall source, so the conversion has something to resize down.
        source = Path.join(dir, "source.png")

        File.write!(
          source,
          Base.decode64!(
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
          )
        )

        heic = Path.join(dir, "card.heic")

        {_out, 0} =
          System.cmd("sips", ["-s", "format", "heic", "-z", "4000", "1500", source, "--out", heic])

        on_exit(fn ->
          Path.wildcard(Path.join(System.tmp_dir!(), "deck_manager-card-*.jpg"))
          |> Enum.each(&File.rm/1)
        end)

        {:ok, heic: heic}
      end

      test "converts to a JPEG the API will accept", %{heic: heic} do
        assert {:ok, jpeg} = Image.prepare(heic)
        assert Path.extname(jpeg) == ".jpg"
        assert File.exists?(jpeg)
      end

      test "resamples down to the long edge the API actually uses", %{heic: heic} do
        {:ok, jpeg} = Image.prepare(heic)

        assert {:ok, width, height} = Image.dimensions(jpeg)
        assert max(width, height) == Image.max_edge()
      end

      test "reuses the converted file on a second call", %{heic: heic} do
        assert {:ok, jpeg} = Image.prepare(heic)
        converted_at = File.stat!(jpeg).mtime

        assert {:ok, ^jpeg} = Image.prepare(heic)
        assert File.stat!(jpeg).mtime == converted_at
      end
    end
  end
end
