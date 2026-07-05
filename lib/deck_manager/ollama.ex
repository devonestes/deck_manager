defmodule DeckManager.Ollama do
  @moduledoc """
  Thin client for a local Ollama model. Two very different callers use it: the
  bulk per-card tagger (small fast model, tiny context) and the once-per-pool
  archetype synthesis (larger model, big context). Hence model/context/format are
  all per-call options.
  """

  @url "http://localhost:11434/api/generate"

  @doc """
  Run a single completion. Returns `{:ok, response_text} | {:error, reason}`.

  Options: `:model`, `:num_ctx`, `:temperature`, `:format` ("json" or a JSON
  schema map), `:receive_timeout`.
  """
  def generate(prompt, opts \\ []) do
    body = %{
      model: Keyword.get(opts, :model, "qwen2.5-coder:7b"),
      prompt: prompt,
      stream: false,
      format: Keyword.get(opts, :format, "json"),
      options: %{
        temperature: Keyword.get(opts, :temperature, 0),
        num_ctx: Keyword.get(opts, :num_ctx, 4096)
      }
    }

    timeout = Keyword.get(opts, :receive_timeout, 300_000)

    case Req.post(@url, json: body, receive_timeout: timeout) do
      {:ok, %{status: 200, body: %{"response" => text}}} -> {:ok, text}
      {:ok, %{status: status}} -> {:error, {:ollama_status, status}}
      {:error, exception} -> {:error, {:ollama, Exception.message(exception)}}
    end
  end
end
