defmodule ChessresultsNotifier do
  require Logger
  @moduledoc """
  Documentation for `ChessresultsNotifier`.
  """

  defstruct [:title, :round, :round_link, :board, :color, :player_name, last_round: false]

  def fetch(url) when is_binary(url) do
    uri = URI.parse url
    fetch uri, url
  end

  def fetch(%{host: "chessresults.ru"}, url) do
    result = try do
      HTTPoison.get url
    rescue
      error -> {:error, error}
    end
    with {:ok, %{body: body, status_code: 200, headers: _headers}} <- result,
         {:ok, document} <- Floki.parse_document(body)
    do
      {title, link} = case Floki.find document, "#table-profile tr:last-child td:fl-contains(\"Турнир\") ~ td > a" do
        [] -> {nil, nil}
        a ->
          [link] = Floki.attribute(a, "href")
          link = URI.merge(url, link) |> URI.to_string()
          {Floki.text(a), link}
      end
      player_name = Floki.find(document, "#table-profile td:fl-contains(\"Фамилия Имя\") + td") |> Floki.text
      last_tour_row = Floki.find(document, "div:fl-contains(\"Соперники\") ~ table:first-of-type > tbody > tr:last-child")
      round = last_tour_row |> Floki.find("td:first-of-type") |> Floki.text() |> String.to_integer()
      board_cell = last_tour_row |> Floki.find("td:nth-of-type(2)")
      board = board_cell |> Floki.text() |> String.to_integer()
      [board_cell_class] = board_cell |> Floki.attribute("class")
      color = case board_cell_class |> String.split(" ") |> Enum.filter(& &1 != "cell") do
        ["white"] -> :white
        ["black"] -> :black
        _ -> nil
      end

      max_rounds = case Regex.run ~r/\/([0-9]+)$/, Floki.find(document, "#attr-score") |> Floki.text, capture: :all_but_first do
        [str] -> String.to_integer(str)
        _ -> 0
      end
      round_is_last = case Floki.find(document, "div:fl-contains(\"Соперники\") ~ table:first-of-type > tbody > tr") |> length do
        ^max_rounds -> true
        _ -> false
      end

      last_round_link = URI.merge(link, "##{round}") |> URI.to_string()

      {:ok,
        %__MODULE__{
          title: title,
          player_name: player_name,
          round: round,
          round_link: last_round_link,
          last_round: round_is_last,
          board: board,
          color: color,
        }}
    else
      other = {:error, _} ->
        other
      other ->
        {:error, other}
    end
  end

  def fetch(uri = %{host: "chess-results.com"}, url) do
    %{query: query} = uri
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
      player_name = case Floki.find(document, "table.CRs1>tr:first-child") do
        [{"tr", _, [{"td", _, ["Name"]}, {"td", _, [name]}]} | _] -> String.trim name
        _ -> nil
      end
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
        last_round = Regex.match? ~r/(?:Тур|Rd\.)(\d+)\/\1$/, latest_round
        {:ok, %__MODULE__{title: title, round: latest_round, round_link: latest_round_link, board: board, color: color, player_name: player_name, last_round: last_round}}
    end
    else
      other = {:error, _} ->
        other
      other ->
        {:error, other}
    end
  end

end
