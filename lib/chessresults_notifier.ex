defmodule ChessresultsNotifier do
  @moduledoc """
  Documentation for `ChessresultsNotifier`.
  """

  defstruct [:title, :round, :round_link]

  def fetch(url) do
    result = try do
      HTTPoison.get url
    rescue
      error -> {:error, error}
    end
    with {:ok, %{body: body, status_code: 200, headers: _headers}} <- result,
         {:ok, document} <- Floki.parse_document(body),
         rounds <- Floki.find(document, "a.CRdb[href*=\"&art=2&\"]"),
         [{_, _, [title]} | _] <- Floki.find(document, "h2")
    do
      title = String.trim title
      case rounds do
        [] -> {:ok, %__MODULE__{title: title}}
        _ ->
          {_, latest_round_data, [latest_round]} = List.last(rounds)
          {_, latest_round_link} = List.keyfind(latest_round_data, "href", 0)
          {:ok, %__MODULE__{title: title, round: latest_round, round_link: latest_round_link}}
      end
    else
      other = {:error, _} ->
        other
      other ->
        {:error, other}
    end
  end

end
