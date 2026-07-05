defmodule DeckManager.Tagger do
  @moduledoc """
  Extracts functional tags for cards using a **local** model (Qwen via Ollama) by
  default. The work is high-volume, per-card, and needs no agentic loop or tool
  orchestration, which makes it a poor fit for a paid API and an ideal fit for
  local inference — tagging ~30k cards would otherwise be a real, recurring cost.

  Tags are cached to a JSONL file (`data/tags/tags.jsonl`, one `{name, tags}` per
  line), so a run is resumable: re-running only tags cards not already present,
  and a crash mid-run loses nothing already written.

  Backends are pluggable via the `:backend` option (`:ollama` default). The
  `:anthropic` backend is reserved for the small subset of genuinely subjective
  judgments we may later route off the local model.
  """

  alias DeckManager.{Card, Tags}

  require Logger

  @tags_path "data/tags/tags.jsonl"
  @ollama_url "http://localhost:11434/api/generate"
  @default_model "qwen2.5-coder:7b"
  @max_retries 2

  # Worked examples covering the mistakes a small model makes here: a sweeper (not
  # "unconditional"), single-target removal as neutral (not negative) card
  # advantage, a real synergy enabler, and a vanilla card that should be tagged
  # empty. Kept concrete so the model copies the discipline, not just the format.
  @examples """
  Examples of correct output:

  Wrath of God (Sorcery) — "Destroy all creatures. They can't be regenerated."
  {"removal":"sweeper","removal_speed":"sorcery","card_advantage":"strong","evasive":false,"interaction":true,"functions":[],"archetypes":[],"role":"standalone"}

  Doom Blade (Instant) — "Destroy target nonblack creature."
  {"removal":"conditional","removal_speed":"instant","card_advantage":"neutral","evasive":false,"interaction":true,"functions":[],"archetypes":[],"role":"standalone"}

  Bitterblossom (Enchantment) — "At the beginning of your upkeep, you lose 1 life and create a 1/1 black Faerie Rogue creature token with flying."
  {"removal":"none","removal_speed":"none","card_advantage":"strong","evasive":false,"interaction":false,"functions":[],"archetypes":["tokens","go_wide","sacrifice"],"role":"enabler"}

  Grizzly Bears (Creature) — vanilla 2/2 with no abilities.
  {"removal":"none","removal_speed":"none","card_advantage":"neutral","evasive":false,"interaction":false,"functions":[],"archetypes":[],"role":"standalone"}
  """

  @doc """
  Tag every card not already in the cache, writing results as they complete.

  Options:
    * `:backend` — `:ollama` (default) or `:anthropic`
    * `:model` — Ollama model tag (default `#{@default_model}`)
    * `:max_concurrency` — default `2`; 16 GB can't feed many more without
      thrashing the KV cache, so keep it low

  Returns `%{tagged: n, failed: n, skipped: n}`.
  """
  def tag_all(cards, opts \\ []) do
    already_tagged = loaded_names()
    concurrency = Keyword.get(opts, :max_concurrency, 2)
    {to_tag, skipped} = Enum.split_with(cards, fn card -> card.name not in already_tagged end)

    File.mkdir_p!(Path.dirname(@tags_path))

    counts =
      to_tag
      |> Task.async_stream(fn card -> {card.name, tag_card(card, opts)} end,
        max_concurrency: concurrency,
        timeout: :infinity,
        ordered: false
      )
      |> Enum.reduce(%{tagged: 0, failed: 0}, fn {:ok, {name, result}}, acc ->
        case result do
          {:ok, tags} ->
            append(name, tags)
            Map.update!(acc, :tagged, &(&1 + 1))

          {:error, reason} ->
            Logger.warning("Tagging failed for #{name}: #{inspect(reason)}")
            Map.update!(acc, :failed, &(&1 + 1))
        end
      end)

    Map.put(counts, :skipped, length(skipped))
  end

  @doc "Tag a single card, retrying on invalid output. Returns `{:ok, tags} | {:error, reason}`."
  def tag_card(card, opts \\ [], attempt \\ 1) do
    backend = Keyword.get(opts, :backend, :ollama)
    # Temperature 0 is deterministic, so retrying with it reproduces the same
    # invalid output. Nudge it up each attempt to shake loose a valid response.
    attempt_opts = Keyword.put(opts, :temperature, (attempt - 1) * 0.3)

    with {:ok, raw} <- generate(backend, prompt(card), attempt_opts),
         {:ok, tags} <- Tags.validate(raw) do
      {:ok, tags}
    else
      {:error, _reason} when attempt <= @max_retries ->
        tag_card(card, opts, attempt + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Load the tag cache as a `name => tags` map (atom-keyed tags)."
  def load_tags do
    case File.read(@tags_path) do
      {:ok, contents} ->
        contents
        |> String.split("\n", trim: true)
        |> Map.new(fn line ->
          %{"name" => name, "tags" => tags} = Jason.decode!(line)
          {name, atomize(tags)}
        end)

      {:error, _} ->
        %{}
    end
  end

  defp loaded_names, do: load_tags() |> Map.keys() |> MapSet.new()

  defp append(name, tags) do
    File.write!(@tags_path, Jason.encode!(%{name: name, tags: tags}) <> "\n", [:append])
  end

  # --- backends ---

  defp generate(:ollama, prompt, opts) do
    body = %{
      model: Keyword.get(opts, :model, @default_model),
      prompt: prompt,
      stream: false,
      format: "json",
      options: %{temperature: Keyword.get(opts, :temperature, 0), num_ctx: 4096}
    }

    case Req.post(@ollama_url, json: body, receive_timeout: 120_000) do
      {:ok, %{status: 200, body: %{"response" => text}}} -> decode(text)
      {:ok, %{status: status}} -> {:error, {:ollama_status, status}}
      {:error, exception} -> {:error, {:ollama, Exception.message(exception)}}
    end
  end

  defp generate(:anthropic, _prompt, _opts) do
    {:error, :anthropic_backend_not_implemented}
  end

  defp decode(text) do
    case Jason.decode(text) do
      {:ok, map} -> {:ok, map}
      {:error, _} -> {:error, :invalid_json}
    end
  end

  defp prompt(%Card{} = card) do
    """
    You are a Magic: the Gathering card function extractor. Read the card's rules
    text and output ONLY a JSON object describing what the card FUNCTIONALLY does.
    Do NOT judge how strong the card is (except for the card_advantage field). Use
    only the allowed values below; empty arrays are fine and are often correct.

    Field spec:
    #{Tags.schema_doc()}
    #{@examples}
    Each field must use ONLY its own allowed values listed above. In particular,
    card_advantage is ALWAYS one of "negative"/"neutral"/"positive"/"strong" — never
    a function or archetype name (a ramp or lifegain creature still has a
    card_advantage of "neutral"). removal is ALWAYS one of
    "none"/"conditional"/"unconditional"/"sweeper".

    Now tag this card. Output only the JSON object, nothing else.
    Name: #{card.name}
    Type: #{card.type_line}
    Mana value: #{card.cmc}
    Keywords: #{Enum.join(card.keywords, ", ")}
    Text:
    #{card.oracle_text}
    """
  end

  defp atomize(tags) do
    %{
      removal: tags["removal"],
      removal_speed: tags["removal_speed"],
      card_advantage: tags["card_advantage"],
      role: tags["role"],
      evasive: tags["evasive"],
      interaction: tags["interaction"],
      functions: tags["functions"] || [],
      archetypes: tags["archetypes"] || []
    }
  end
end
