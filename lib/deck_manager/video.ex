defmodule DeckManager.Video do
  @moduledoc """
  Turns a video of cards shown one at a time into one image per card.

  The video is expected to look like a slideshow: a card is held still in front
  of a plain background, taken fully out of frame, and the next one brought in.
  That gap is the only thing that separates two cards — what is on them is never
  looked at here — so two copies of the same card shown back to back are still
  two cards.

  Finding the cards needs no model, only `ffmpeg`:

    1. **Signals.** Every frame is decoded down to a small greyscale thumbnail
       and scored for *edge density* (a card's border and text are full of hard
       edges; a wall, a soft shadow and a motion-blurred hand are not) and
       *motion* against the frame before. Edge density is used rather than
       "differs from the empty background" because a moving shadow defeats the
       latter.
    2. **Segments.** Runs of card-present frames, split wherever the card is
       gone for a moment. A *glimpse* — a card barely on screen and never held
       still, right up against another one — is that neighbour going in or out
       and is dropped; one standing on its own is kept and marked `brief`.
    3. **Frames.** The sharpest still frame of each card is pulled at full
       resolution and cropped to the card, found by its dark border.

  The decode is the slow part (roughly a fifth of real time for 4K), so the
  result is cached in the system temp directory under the video's path, size
  and mtime: a second run over the same video starts reading cards at once.
  """

  @extensions ~w(.mov .mp4 .m4v)

  # Part of the cache key: bump it when segmenting or cropping changes, so a
  # cached run made by older code isn't reused.
  @cache_version 1

  # Thumbnail the signals are computed on. Tiny on purpose: it only has to tell
  # "card" from "no card" and "still" from "moving".
  @thumb_w 108
  @thumb_h 192

  # Cards are held in the upper part of the frame; the bottom is usually the
  # table edge and the hand coming and going, which only adds noise.
  @card_band 0.65

  # Horizontal steps smaller than this are a soft shadow, not an edge.
  @edge_step 12

  # Mean absolute frame difference (0–255) below which the card is still.
  @still_motion 2.0

  # Seconds of no card that end one card and start the next.
  @gap 0.25
  # Anything on screen for less than this is a flicker, not a card.
  @min_visit 0.17
  # A glimpse: on screen for less than this, with fewer than @glimpse_still
  # still frames…
  @glimpse_length 0.8
  @glimpse_still 3
  # …and within this of another card, which it is assumed to belong to.
  @glimpse_reach 1.5

  # Card crop: margin around the detected border, as a fraction of its size.
  @crop_margin 0.04
  # The card region has to cover at least this share of the searched band, or
  # it is a speck and the whole band is sent instead.
  @min_card_area 0.02
  # Height over width of a Magic card (88 × 63 mm).
  @card_aspect 88 / 63

  @doc "True when the path has a video extension."
  def video?(path) when is_binary(path) do
    path |> Path.extname() |> String.downcase() |> Kernel.in(@extensions)
  end

  def video?(_ref), do: false

  @doc "The file extensions treated as video."
  def extensions, do: @extensions

  @doc """
  Find every card in a video. Returns `{:ok, cards}` or `{:error, reason}`,
  where each card is a map with:

    * `:image` — path to a JPEG cropped to the card
    * `:at` — seconds into the video the image was taken
    * `:brief` — true when the card was barely shown and never held still, so
      its image is likely blurred

  Options: `:cache` (default true) — reuse an earlier run over the same file.
  """
  def cards(path, opts \\ []) do
    path = Path.expand(path)

    with {:ok, stat} <- stat(path),
         dir = cache_dir(path, stat),
         manifest = Path.join(dir, "cards.json") do
      if Keyword.get(opts, :cache, true) and File.exists?(manifest) do
        read_manifest(manifest)
      else
        File.rm_rf!(dir)
        File.mkdir_p!(dir)

        with {:ok, cards} <- find_cards(path, dir) do
          File.write!(manifest, Jason.encode!(cards))
          {:ok, cards}
        end
      end
    end
  end

  defp stat(path) do
    case File.stat(path) do
      {:ok, stat} -> {:ok, stat}
      {:error, reason} -> {:error, {:video_read, path, reason}}
    end
  end

  defp cache_dir(path, %{size: size, mtime: mtime}) do
    name = Path.basename(path, Path.extname(path))
    key = :erlang.phash2({@cache_version, path, size, mtime})
    Path.join(System.tmp_dir!(), "deck_manager-video-#{name}-#{key}")
  end

  defp read_manifest(manifest) do
    cards =
      manifest
      |> File.read!()
      |> Jason.decode!()
      |> Enum.map(fn card ->
        %{image: card["image"], at: card["at"], brief: card["brief"]}
      end)

    {:ok, cards}
  end

  defp find_cards(path, dir) do
    with {:ok, fps} <- frame_rate(path),
         {:ok, signals} <- signals(path) do
      case segment(signals, fps) do
        [] ->
          {:error, {:no_cards_found, path}}

        segments ->
          frames = Enum.map(segments, & &1.frame)

          with :ok <- extract_frames(path, frames, dir) do
            segments
            |> Enum.with_index(1)
            |> Enum.map(fn {segment, index} -> crop_card(segment, index, dir, fps) end)
            |> collect()
          end
      end
    end
  end

  defp collect(results) do
    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(results, fn {:ok, card} -> card end)}
      error -> error
    end
  end

  # ---- signals ---------------------------------------------------------------

  defp frame_rate(path) do
    args =
      ~w(-v error -select_streams v:0 -show_entries stream=avg_frame_rate -of default=nw=1:nk=1) ++
        [path]

    with {output, 0} <- cmd("ffprobe", args),
         [rate | _] <- String.split(output, "\n", trim: true),
         [num, den] <- rate |> String.trim() |> String.split("/"),
         {num, ""} <- Float.parse(num),
         {den, ""} <- Float.parse(den),
         true <- den > 0 do
      {:ok, num / den}
    else
      :unavailable -> {:error, :ffmpeg_missing}
      _ -> {:error, {:no_video_stream, path}}
    end
  end

  # One `{edge, motion}` tuple per decoded frame. `passthrough` keeps ffmpeg from
  # duplicating or dropping frames to fit a constant rate — phone video is
  # variable-rate — so index n here is frame n in `extract_frames/3`.
  defp signals(path) do
    case System.find_executable("ffmpeg") do
      nil ->
        {:error, :ffmpeg_missing}

      ffmpeg ->
        args =
          ~w(-v fatal -i) ++
            [path] ++
            ~w(-vf scale=#{@thumb_w}:#{@thumb_h},format=gray -fps_mode passthrough -f rawvideo -)

        port = Port.open({:spawn_executable, ffmpeg}, [:binary, :exit_status, args: args])

        case read_frames(port, <<>>, []) do
          {:ok, frames} -> {:ok, score(frames)}
          error -> error
        end
    end
  end

  defp read_frames(port, buffer, acc) do
    receive do
      {^port, {:data, data}} ->
        {frames, rest} = split_frames(buffer <> data, [])
        read_frames(port, rest, Enum.reverse(frames, acc))

      {^port, {:exit_status, 0}} ->
        {:ok, Enum.reverse(acc)}

      {^port, {:exit_status, status}} ->
        {:error, {:ffmpeg_decode, status}}
    end
  end

  defp split_frames(buffer, acc) when byte_size(buffer) >= @thumb_w * @thumb_h do
    <<frame::binary-size(@thumb_w * @thumb_h), rest::binary>> = buffer
    split_frames(rest, [frame | acc])
  end

  defp split_frames(buffer, acc), do: {Enum.reverse(acc), buffer}

  defp score(frames) do
    rows = trunc(@thumb_h * @card_band)
    band = rows * @thumb_w

    [nil | frames]
    |> Enum.chunk_every(2, 1, :discard)
    |> Task.async_stream(
      fn [previous, frame] ->
        edge = edge_density(frame, rows)

        motion =
          if previous,
            do: abs_diff(binary_part(previous, 0, band), binary_part(frame, 0, band), 0) / band,
            else: 0.0

        {edge, motion}
      end,
      ordered: true
    )
    |> Enum.map(fn {:ok, signal} -> signal end)
  end

  @doc false
  # Mean strength of hard edges over the top `rows` rows of a greyscale
  # thumbnail: horizontal steps above @edge_step plus vertical differences.
  def edge_density(frame, rows) do
    lines = for row <- 0..(rows - 1), do: binary_part(frame, row * @thumb_w, @thumb_w)
    horizontal = Enum.reduce(lines, 0, fn line, acc -> acc + steps(line, 0) end)

    vertical =
      lines
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.reduce(0, fn [a, b], acc -> acc + abs_diff(a, b, 0) end)

    (horizontal + vertical) / (@thumb_w * rows)
  end

  defp steps(<<a, b, rest::binary>>, acc) do
    step = abs(a - b)
    steps(<<b, rest::binary>>, if(step > @edge_step, do: acc + step, else: acc))
  end

  defp steps(_line, acc), do: acc

  defp abs_diff(<<a, as::binary>>, <<b, bs::binary>>, acc), do: abs_diff(as, bs, acc + abs(a - b))
  defp abs_diff(_, _, acc), do: acc

  # ---- segments --------------------------------------------------------------

  @doc """
  Split per-frame `{edge, motion}` signals into cards. Returns one map per card
  with `:first` and `:last` frame, the `:frame` to take its picture from, the
  number of `:still` frames and `:brief`.

  "Card present" is judged against the video's own range — halfway between its
  emptiest and busiest frames — since lighting and how much of the frame a card
  fills change from one recording to the next.
  """
  def segment(signals, fps) do
    indexed = Enum.with_index(signals, fn {edge, motion}, n -> {n, edge, motion} end)
    threshold = threshold(signals)

    indexed
    |> runs(threshold, round(@gap * fps))
    |> Enum.map(&summarise/1)
    |> Enum.reject(&(&1.last - &1.first < @min_visit * fps))
    |> drop_glimpses(fps)
  end

  defp threshold([]), do: 0.0

  defp threshold(signals) do
    edges = signals |> Enum.map(&elem(&1, 0)) |> Enum.sort() |> List.to_tuple()
    at = fn q -> elem(edges, trunc(q * (tuple_size(edges) - 1))) end
    (at.(0.10) + at.(0.90)) / 2
  end

  # Runs of present frames, ended once `gap` absent frames go by. Only present
  # frames are kept, so a run's bounds are where the card actually was.
  defp runs(indexed, threshold, gap) do
    {runs, current, _absent} =
      Enum.reduce(indexed, {[], [], 0}, fn {_n, edge, _motion} = frame, {runs, current, absent} ->
        cond do
          edge > threshold -> {runs, [frame | current], 0}
          current != [] and absent + 1 >= gap -> {[Enum.reverse(current) | runs], [], 0}
          current == [] -> {runs, [], 0}
          true -> {runs, current, absent + 1}
        end
      end)

    runs = if current == [], do: runs, else: [Enum.reverse(current) | runs]
    Enum.reverse(runs)
  end

  defp summarise(frames) do
    {first, _, _} = hd(frames)
    {last, _, _} = List.last(frames)
    still = Enum.filter(frames, fn {_n, _edge, motion} -> motion < @still_motion end)

    # Of the still frames, the one with the most edge detail: motion blur and a
    # thumb over the card both cost edges. Without any still frame, the least
    # blurred one there is.
    {frame, _, _} =
      case still do
        [] -> Enum.min_by(frames, fn {_n, _edge, motion} -> motion end)
        still -> Enum.max_by(still, fn {_n, edge, _motion} -> edge end)
      end

    %{first: first, last: last, frame: frame, still: length(still), brief: false}
  end

  defp drop_glimpses(segments, fps) do
    indexed = segments |> Enum.with_index() |> Map.new(fn {segment, i} -> {i, segment} end)

    segments
    |> Enum.with_index()
    |> Enum.flat_map(fn {segment, i} ->
      cond do
        not glimpse?(segment, fps) -> [segment]
        near_neighbour?(segment, indexed[i - 1], indexed[i + 1], fps) -> []
        true -> [%{segment | brief: true}]
      end
    end)
  end

  defp glimpse?(segment, fps) do
    segment.still < @glimpse_still and segment.last - segment.first < @glimpse_length * fps
  end

  defp near_neighbour?(segment, previous, next, fps) do
    reach = @glimpse_reach * fps

    (previous != nil and segment.first - previous.last < reach) or
      (next != nil and next.first - segment.last < reach)
  end

  # ---- frames ----------------------------------------------------------------

  # One decode pass pulls every wanted frame at full resolution.
  defp extract_frames(path, frames, dir) do
    select = Enum.map_join(frames, "+", &"eq(n\\,#{&1})")

    args =
      ~w(-v error -i) ++
        [path] ++
        ["-vf", "select='#{select}'"] ++
        ~w(-fps_mode passthrough -q:v 2 -y) ++ [Path.join(dir, "frame-%03d.jpg")]

    case cmd("ffmpeg", args) do
      {_output, 0} -> check_frames(dir, length(frames))
      {output, status} -> {:error, {:ffmpeg_extract, status, String.trim(output)}}
      :unavailable -> {:error, :ffmpeg_missing}
    end
  end

  defp check_frames(dir, expected) do
    case dir |> Path.join("frame-*.jpg") |> Path.wildcard() |> length() do
      ^expected -> :ok
      found -> {:error, {:ffmpeg_extract, :frame_count, expected: expected, found: found}}
    end
  end

  defp crop_card(segment, index, dir, fps) do
    frame = Path.join(dir, "frame-#{pad(index)}.jpg")
    image = Path.join(dir, "card-#{pad(index)}.jpg")

    with {:ok, {x, y, w, h}} <- card_box(frame),
         {_output, 0} <-
           cmd(
             "ffmpeg",
             ~w(-v error -i #{frame} -vf) ++ [crop(x, y, w, h)] ++ ~w(-q:v 2 -y #{image})
           ) do
      File.rm(frame)
      {:ok, %{image: image, at: Float.round(segment.frame / fps, 1), brief: segment.brief}}
    else
      {output, status} when is_binary(output) ->
        {:error, {:ffmpeg_crop, status, String.trim(output)}}

      :unavailable ->
        {:error, :ffmpeg_missing}

      error ->
        error
    end
  end

  defp crop(x, y, w, h) do
    "crop=w=iw*#{w}:h=ih*#{h}:x=iw*#{x}:y=ih*#{y}"
  end

  defp pad(index), do: index |> to_string() |> String.pad_leading(3, "0")

  # Width of the thumbnail the card is located on; the height follows the
  # frame's own aspect so the card keeps its shape in either orientation.
  @box_w 216

  defp card_box(frame) do
    args = ~w(-v error -i #{frame} -vf scale=#{@box_w}:-2,format=gray -f rawvideo -)

    # Not merged with stderr: stdout here is raw pixels, and a warning mixed
    # into them would shift every byte after it.
    case cmd("ffmpeg", args, stderr_to_stdout: false) do
      {pixels, 0} -> {:ok, locate_card(pixels, @box_w, div(byte_size(pixels), @box_w))}
      {output, status} -> {:error, {:ffmpeg_crop, status, String.trim(output)}}
      :unavailable -> {:error, :ffmpeg_missing}
    end
  end

  @doc """
  Find the card in a greyscale image (`width` × `height` bytes) by its dark
  border against the lighter background. Returns `{x, y, w, h}` as fractions of
  the image, with a small margin. Only the upper part of the frame is searched
  (see `@card_band`); if no card-like dark region is found, that whole band is
  returned so the model still gets to look.

  The card is the largest *connected* dark region — its border joins up with
  the art and frame into one blob — so a shadowed gap at the edge of the frame
  or the corner of something behind it can't stretch the box, however dark.
  """
  def locate_card(pixels, width, height) do
    band = trunc(height * @card_band)

    wall =
      pixels |> :binary.bin_to_list() |> Enum.sort() |> Enum.at(div(byte_size(pixels) * 9, 10))

    dark =
      for y <- 0..(band - 1),
          x <- 0..(width - 1),
          :binary.at(pixels, y * width + x) < wall * 0.45,
          into: MapSet.new(),
          do: {x, y}

    case card_region(dark) do
      {size, {x0, y0, x1, y1}} when size >= width * band * @min_card_area ->
        y0 = card_top(x0, y0, x1, y1)
        box(x0 / width, y0 / height, (x1 + 1) / width, (y1 + 1) / height)

      _none ->
        {0.0, 0.0, 1.0, band / height}
    end
  end

  # The largest dark region is usually the whole card. On a card with a light
  # frame (artifacts, many lands) the black border is a thin ring cut off from
  # the dark art inside it, and the art wins on size — so a region whose box
  # encloses the largest one is preferred: that is the border around it.
  defp card_region(points) do
    regions = points |> regions([]) |> Enum.map(&{length(&1), bounds(&1)})

    case Enum.max_by(regions, &elem(&1, 0), fn -> nil end) do
      nil ->
        nil

      {size, inner} ->
        regions
        |> Enum.filter(fn {_size, outer} -> encloses?(outer, inner) end)
        |> Enum.max_by(fn {_size, {x0, y0, x1, y1}} -> (x1 - x0) * (y1 - y0) end)
        |> then(fn {_size, outer} -> {size, outer} end)
    end
  end

  # A borderless card with light art is only dark from its text box down, so
  # the region found is the bottom of the card. A box far too short for a card
  # is grown upward to card proportions — the collector line is at the bottom
  # and already inside it; this brings the name back in.
  defp card_top(x0, y0, x1, y1) do
    width = x1 - x0 + 1

    if y1 - y0 + 1 < width * @card_aspect * 0.85,
      do: max(round(y1 + 1 - width * @card_aspect), 0),
      else: y0
  end

  defp bounds(points) do
    {x0, x1} = points |> Enum.map(&elem(&1, 0)) |> Enum.min_max()
    {y0, y1} = points |> Enum.map(&elem(&1, 1)) |> Enum.min_max()
    {x0, y0, x1, y1}
  end

  defp encloses?({ox0, oy0, ox1, oy1}, {ix0, iy0, ix1, iy1}) do
    ox0 <= ix0 and oy0 <= iy0 and ox1 >= ix1 and oy1 >= iy1
  end

  defp regions(unvisited, acc) do
    case Enum.at(unvisited, 0) do
      nil ->
        acc

      seed ->
        {region, unvisited} = flood([seed], MapSet.delete(unvisited, seed), [seed])
        regions(unvisited, [region | acc])
    end
  end

  # 8-connected flood fill; the card's border can be a single thumbnail pixel
  # wide on a tilted card, so diagonal neighbours have to count.
  defp flood([], unvisited, region), do: {region, unvisited}

  defp flood([{x, y} | queue], unvisited, region) do
    neighbours =
      for dx <- -1..1,
          dy <- -1..1,
          {dx, dy} != {0, 0},
          MapSet.member?(unvisited, {x + dx, y + dy}),
          do: {x + dx, y + dy}

    flood(
      neighbours ++ queue,
      MapSet.difference(unvisited, MapSet.new(neighbours)),
      neighbours ++ region
    )
  end

  defp box(x0, y0, x1, y1) do
    mx = (x1 - x0) * @crop_margin
    my = (y1 - y0) * @crop_margin
    left = max(x0 - mx, 0.0)
    top = max(y0 - my, 0.0)
    right = min(x1 + mx, 1.0)
    bottom = min(y1 + my, 1.0)

    {Float.round(left, 4), Float.round(top, 4), Float.round(right - left, 4),
     Float.round(bottom - top, 4)}
  end

  defp cmd(command, args, opts \\ [stderr_to_stdout: true]) do
    System.cmd(command, args, opts)
  rescue
    ErlangError -> :unavailable
  end
end
