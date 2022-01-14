defmodule ChessresultsNotifier do
  @moduledoc """
  Documentation for `ChessresultsNotifier`.
  """

  def fetch(url) do
    result = try do
      HTTPoison.get url
    rescue
      error -> {:error, error}
    end
    with {:ok, %{body: body, status_code: 200, headers: _headers}} <- result,
         {:ok, document} <- Floki.parse_document(body),
         tours <- Floki.find(document, "a.CRdb[href*=\"&art=2&\"]"),
         [{_, _, [title]} | _] <- Floki.find(document, "h2")
    do
      title = String.trim title
      case tours do
        [] -> {:ok, title, nil, nil}
        _ ->
          {_, latest_tour_data, [latest_tour]} = List.last(tours)
          {_, latest_tour_link} = List.keyfind(latest_tour_data, "href", 0)
          {:ok, String.trim(title), latest_tour, URI.merge(url, latest_tour_link)}
      end
    else
      other = {:error, _} ->
        other
      other ->
        {:error, other}
    end
  end

end
