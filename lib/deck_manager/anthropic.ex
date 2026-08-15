defmodule DeckManager.Anthropic do
  @moduledoc """
  Minimal Anthropic Messages API client (raw HTTP via Req — Elixir has no official
  SDK). Used for the once-per-pool archetype synthesis, where a frontier model's
  judgment is worth the per-call cost; the bulk per-card tagging stays local.

  Reads the key from `ANTHROPIC_API_KEY`, falling back to `~/.config/anthropic/token`
  (matching the repo's convention for other service tokens). Uses adaptive thinking
  + high effort for the reasoning, and structured outputs (`output_config.format`)
  to guarantee the response is valid JSON matching the caller's schema.
  """

  @url "https://api.anthropic.com/v1/messages"
  @version "2023-06-01"
  @default_model "claude-opus-5"
  @token_file "~/.config/anthropic/token"

  @doc """
  Run a single completion. Returns `{:ok, text}` (the response's text block) or
  `{:error, reason}`. Options: `:model`, `:max_tokens`, `:effort`, `:format`
  (a JSON schema map to constrain the output), `:images` (a list of image
  references — each an http(s) URL, a local file path, or a `{media_type, base64}`
  tuple — sent alongside the text prompt for vision requests).
  """
  def generate(prompt, opts \\ []) do
    case api_key() do
      {:ok, key} -> request(prompt, key, opts)
      error -> error
    end
  end

  @doc """
  Build an Anthropic image content block from a reference. An http(s) URL is
  downloaded here (rather than handed to Anthropic to fetch — many hosts block
  its fetcher) and base64-encoded; a `{media_type, base64}` tuple is used as-is;
  anything else is treated as a local file path. Returns `{:ok, block}` or
  `{:error, reason}`.
  """
  def image_block("http://" <> _ = url), do: fetch_url_block(url)
  def image_block("https://" <> _ = url), do: fetch_url_block(url)

  def image_block({media_type, data}) when is_binary(data),
    do: {:ok, base64_block(media_type, data)}

  def image_block(path) when is_binary(path) do
    case File.read(Path.expand(path)) do
      {:ok, bytes} -> {:ok, base64_block(media_type_for(path), Base.encode64(bytes))}
      {:error, reason} -> {:error, {:image_read, path, reason}}
    end
  end

  # Download the image and infer its media type from the Content-Type header,
  # falling back to the URL's extension.
  defp fetch_url_block(url) do
    case Req.get(url, headers: [{"user-agent", "deck_manager/0.1"}]) do
      {:ok, %{status: 200, body: body, headers: headers}} ->
        media_type =
          case headers["content-type"] || headers["Content-Type"] do
            [type | _] -> type |> String.split(";") |> hd() |> String.trim()
            _ -> media_type_for(url)
          end

        {:ok, base64_block(media_type, Base.encode64(body))}

      {:ok, %{status: status}} ->
        {:error, {:image_fetch, url, status}}

      {:error, exception} ->
        {:error, {:image_fetch, url, Exception.message(exception)}}
    end
  end

  defp base64_block(media_type, data) do
    %{type: "image", source: %{type: "base64", media_type: media_type, data: data}}
  end

  defp media_type_for(path) do
    case path |> Path.extname() |> String.downcase() do
      ext when ext in [".jpg", ".jpeg"] -> "image/jpeg"
      ".png" -> "image/png"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      _ -> "image/jpeg"
    end
  end

  defp api_key do
    case System.get_env("ANTHROPIC_API_KEY") do
      key when is_binary(key) and key != "" ->
        {:ok, key}

      _ ->
        case File.read(Path.expand(@token_file)) do
          {:ok, contents} -> {:ok, String.trim(contents)}
          {:error, _} -> {:error, :missing_api_key}
        end
    end
  end

  defp request(prompt, key, opts) do
    output_config =
      %{effort: Keyword.get(opts, :effort, "high")}
      |> maybe_put_format(Keyword.get(opts, :format))

    body = %{
      model: Keyword.get(opts, :model, @default_model),
      max_tokens: Keyword.get(opts, :max_tokens, 16_000),
      thinking: %{type: "adaptive"},
      output_config: output_config,
      messages: [%{role: "user", content: content(prompt, Keyword.get(opts, :images, []))}]
    }

    headers = [
      {"x-api-key", key},
      {"anthropic-version", @version},
      {"content-type", "application/json"}
    ]

    case Req.post(@url, json: body, headers: headers, receive_timeout: 300_000) do
      {:ok, %{status: 200, body: resp}} -> extract_text(resp)
      {:ok, %{status: status, body: resp}} -> {:error, {:anthropic_status, status, resp}}
      {:error, exception} -> {:error, {:anthropic, Exception.message(exception)}}
    end
  end

  # No images: send the bare string (backward compatible). With images: send a
  # content-block list — the images first, then the text prompt.
  defp content(prompt, []), do: prompt

  defp content(prompt, images) when is_list(images) do
    images ++ [%{type: "text", text: prompt}]
  end

  defp maybe_put_format(config, nil), do: config

  defp maybe_put_format(config, schema) do
    Map.put(config, :format, %{type: "json_schema", schema: schema})
  end

  # Skip thinking blocks (empty text under the default display) and return the
  # answer text block; a refusal has no text block.
  defp extract_text(%{"content" => blocks}) do
    case Enum.find(blocks, fn b -> b["type"] == "text" end) do
      %{"text" => text} -> {:ok, text}
      _ -> {:error, {:no_text_block, blocks}}
    end
  end

  defp extract_text(other), do: {:error, {:unexpected_response, other}}
end
