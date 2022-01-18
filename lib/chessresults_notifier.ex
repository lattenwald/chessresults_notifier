defmodule ChessresultsNotifier do
  require Logger
  @moduledoc """
  Documentation for `ChessresultsNotifier`.
  """

  defstruct [:title, :round, :round_link, :board, :color]

  def fetch(url) do
    %{query: query} = URI.parse url
    query = Map.merge URI.decode_query(query), %{"lan" => "1"}
    url = URI.merge(url, "?" <> URI.encode_query(query)) |> URI.to_string

    result = try do
      HTTPoison.get url
    rescue
      error -> {:error, error}
    end
    with {:ok, %{body: body, status_code: 200, headers: _headers}} <- result,
         {:ok, document} <- Floki.parse_document(body),
         rounds <- Floki.find(document, "a.CRdb[href*=\"&art=2&\"]"),
         headers <- Floki.find(document, "h2"),
         [{_, _, [title]} | _] <- headers
    do
      title = String.trim title
      {board, color} =
        case Enum.find headers, fn {_,_,["Player info"]} -> true; _ -> false end do
          nil -> {nil, nil}
          _ ->
            case Floki.find(document, "table.CRs1:last-child>tr:last-child") do
              [] -> {nil, nil}
              last_row ->
                [{_,_,[board]}|_] = Floki.find(last_row, "td:nth-child(2)")
                [{_, attrs, _}|_] = Floki.find(last_row, "table div")
                color = case List.keyfind(attrs, "class", 0) do
                  nil -> nil
                  {_, "FarbewT"} -> :white
                  {_, "FarbesT"} -> :black
                end
                {board, color}
            end
        end
    case rounds do
      [] -> {:ok, %__MODULE__{title: title}}
      _ ->
        {_, latest_round_data, [latest_round]} = List.last(rounds)
        {_, latest_round_link} = List.keyfind(latest_round_data, "href", 0)
        {:ok, %__MODULE__{title: title, round: latest_round, round_link: latest_round_link, board: board, color: color}}
    end
    else
      other = {:error, _} ->
        other
      other ->
        {:error, other}
    end
  end

end
