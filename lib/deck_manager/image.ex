defmodule DeckManager.Image do
  @moduledoc """
  Gets a local photo into a shape the vision API will accept.

  iPhones write HEIC by default, and the Anthropic API takes only JPEG, PNG,
  GIF and WebP — so an AirDropped camera original has to be transcoded before
  it can be scanned. That is done here with macOS's built-in `sips`, which is
  also why this is the one part of the pipeline that isn't portable; on a
  machine without `sips` a HEIC file reports a clear error instead of silently
  going missing.

  Converted files are cached in the system temp directory under a name derived
  from the source's path, size and mtime, so scanning one photo across a count
  pass and a read pass transcodes it once, and editing the photo produces a new
  cache entry rather than a stale hit.
  """

  @heic_extensions ~w(.heic .heif)

  # The API resamples anything longer than this on its long edge, so converting
  # at full camera resolution would only mean uploading pixels it throws away —
  # a phone original is roughly 4000px tall against this 2576px ceiling.
  @max_edge 2576

  @doc """
  Return a reference the vision API can read. URLs and inline
  `{media_type, base64}` tuples pass through; a local HEIC is converted to JPEG
  and the converted path returned; every other local path is returned as-is.

  Returns `{:ok, ref}` or `{:error, reason}`.
  """
  def prepare("http://" <> _ = url), do: {:ok, url}
  def prepare("https://" <> _ = url), do: {:ok, url}
  def prepare({_media_type, _data} = inline), do: {:ok, inline}

  def prepare(path) when is_binary(path) do
    if heic?(path), do: to_jpeg(Path.expand(path)), else: {:ok, path}
  end

  @doc "True when the reference is a local HEIC/HEIF file path."
  def heic?(path) when is_binary(path) do
    path |> Path.extname() |> String.downcase() |> Kernel.in(@heic_extensions)
  end

  def heic?(_ref), do: false

  @doc """
  The pixel dimensions of a local image as `{:ok, width, height}`, or `:error`
  when they can't be read (a URL, an inline image, or no `sips` on the machine).
  """
  def dimensions(path) when is_binary(path) do
    with {output, 0} <- sips(["-g", "pixelWidth", "-g", "pixelHeight", Path.expand(path)]),
         [[width], [height]] <-
           Regex.scan(~r/pixel(?:Width|Height):\s*(\d+)/, output, capture: :all_but_first) do
      {:ok, String.to_integer(width), String.to_integer(height)}
    else
      _ -> :error
    end
  end

  def dimensions(_ref), do: :error

  @doc "The long-edge ceiling above which the API resamples an image down."
  def max_edge, do: @max_edge

  defp to_jpeg(path) do
    case File.stat(path) do
      {:ok, stat} ->
        target = cache_path(path, stat)
        if File.exists?(target), do: {:ok, target}, else: convert(path, target)

      {:error, reason} ->
        {:error, {:image_read, path, reason}}
    end
  end

  defp cache_path(path, %{size: size, mtime: mtime}) do
    name = Path.basename(path, Path.extname(path))
    key = :erlang.phash2({path, size, mtime})

    Path.join(System.tmp_dir!(), "deck_manager-#{name}-#{key}.jpg")
  end

  defp convert(path, target) do
    args = ["-s", "format", "jpeg"] ++ resize_args(path) ++ [path, "--out", target]

    case sips(args) do
      {_output, 0} -> {:ok, target}
      {output, status} -> {:error, {:heic_convert, path, status, String.trim(output)}}
      :unavailable -> {:error, {:heic_unsupported, path}}
    end
  end

  # `sips -Z` scales in both directions, so it is only worth passing when the
  # photo is actually oversized — otherwise a small HEIC would be upscaled into
  # more tokens without carrying any more detail.
  defp resize_args(path) do
    case dimensions(path) do
      {:ok, width, height} when max(width, height) > @max_edge -> ["-Z", to_string(@max_edge)]
      _ -> []
    end
  end

  defp sips(args) do
    System.cmd("sips", args, stderr_to_stdout: true)
  rescue
    # No `sips` on this machine — it ships with macOS and nowhere else.
    ErlangError -> :unavailable
  end
end
