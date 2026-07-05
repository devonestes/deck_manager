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
  @default_model "claude-opus-4-8"
  @token_file "~/.config/anthropic/token"

  @doc """
  Run a single completion. Returns `{:ok, text}` (the response's text block) or
  `{:error, reason}`. Options: `:model`, `:max_tokens`, `:effort`, `:format`
  (a JSON schema map to constrain the output).
  """
  def generate(prompt, opts \\ []) do
    case api_key() do
      {:ok, key} -> request(prompt, key, opts)
      error -> error
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
      max_tokens: Keyword.get(opts, :max_tokens, 4096),
      thinking: %{type: "adaptive"},
      output_config: output_config,
      messages: [%{role: "user", content: prompt}]
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
