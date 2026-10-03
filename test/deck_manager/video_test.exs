defmodule DeckManager.VideoTest do
  use ExUnit.Case, async: true

  alias DeckManager.Video

  @fps 30.0

  # Signals for a run of frames: `{:card, n}` is n still frames of a held card,
  # `{:moving, n}` a card on screen but in motion, `{:empty, n}` bare wall.
  defp signals(spec) do
    Enum.flat_map(spec, fn
      {:card, n} -> List.duplicate({18.0, 0.4}, n)
      {:moving, n} -> List.duplicate({16.0, 9.0}, n)
      {:empty, n} -> List.duplicate({1.5, 0.3}, n)
    end)
  end

  describe "video?/1" do
    test "recognises phone video regardless of case" do
      assert Video.video?("IMG_1815.MOV")
      assert Video.video?("clip.mp4")
      assert Video.video?("clip.m4v")
    end

    test "rejects photos and inline images" do
      refute Video.video?("IMG_1815.jpg")
      refute Video.video?({"image/png", "YmFzZTY0"})
    end
  end

  describe "segment/2" do
    test "finds one card per showing, split by the gaps between them" do
      segments =
        signals(empty: 30, card: 60, empty: 30, card: 45, empty: 30, card: 50, empty: 30)
        |> Video.segment(@fps)

      assert length(segments) == 3
      assert Enum.map(segments, & &1.first) == [30, 120, 195]
      refute Enum.any?(segments, & &1.brief)
    end

    test "keeps identical cards shown back to back apart" do
      # Nothing about the frames differs but the gap — which is the point.
      segments = signals(card: 60, empty: 15, card: 60) |> Video.segment(@fps)

      assert length(segments) == 2
    end

    test "does not split a card over a blink shorter than the gap" do
      segments = signals(card: 40, empty: 3, card: 40, empty: 30) |> Video.segment(@fps)

      assert [%{first: 0, last: 82}] = segments
    end

    test "takes the picture from a still frame, not one in motion" do
      [segment] = signals(moving: 20, card: 10, moving: 20, empty: 30) |> Video.segment(@fps)

      assert segment.frame in 20..29
      assert segment.still == 10
    end

    test "drops a glimpse that is the next card going in" do
      segments =
        signals(card: 60, empty: 10, moving: 8, empty: 9, card: 60) |> Video.segment(@fps)

      assert length(segments) == 2
    end

    test "keeps a lone brief card, marked brief" do
      segments =
        signals(card: 60, empty: 90, moving: 12, empty: 90, card: 60) |> Video.segment(@fps)

      assert [%{brief: false}, %{brief: true}, %{brief: false}] = segments
    end

    test "returns nothing for a video without cards" do
      assert Video.segment([], @fps) == []
    end
  end

  describe "locate_card/3" do
    # A light wall with a dark card at the given thumbnail rectangle, and an
    # optional unrelated dark patch elsewhere.
    defp frame({w, h}, {cx0, cy0, cx1, cy1}, patches \\ []) do
      for y <- 0..(h - 1), x <- 0..(w - 1), into: <<>> do
        inside = fn {x0, y0, x1, y1} -> x >= x0 and x <= x1 and y >= y0 and y <= y1 end

        cond do
          inside.({cx0, cy0, cx1, cy1}) -> <<30>>
          Enum.any?(patches, inside) -> <<20>>
          true -> <<200>>
        end
      end
    end

    test "boxes the card, with a small margin" do
      {x, y, w, h} = Video.locate_card(frame({100, 200}, {20, 30, 69, 99}), 100, 200)

      assert_in_delta x, 0.18, 0.01
      assert_in_delta y, 0.136, 0.005
      assert_in_delta w, 0.54, 0.01
      assert_in_delta h, 0.378, 0.01
    end

    test "ignores a separate dark patch at the edge of the frame" do
      card = {20, 30, 69, 99}
      alone = Video.locate_card(frame({100, 200}, card), 100, 200)
      with_patch = Video.locate_card(frame({100, 200}, card, [{95, 0, 99, 120}]), 100, 200)

      assert with_patch == alone
    end

    test "grows a card-shaped box upward from a dark text box alone" do
      # A borderless card with light art: only the bottom third is dark.
      {_x, y, _w, h} = Video.locate_card(frame({100, 200}, {20, 70, 69, 99}), 100, 200)

      # 50 px wide → about 70 px tall; the box now starts near y = 30.
      assert_in_delta y, 0.15, 0.02
      assert_in_delta h, 0.37, 0.02
    end

    test "falls back to the upper part of the frame when there is no card" do
      assert Video.locate_card(frame({100, 200}, {0, 0, -1, -1}), 100, 200) ==
               {0.0, 0.0, 1.0, 0.65}
    end
  end
end
