defmodule Windshield do
  @moduledoc """
  Windshield keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  # supports BSON.Id prints
  defimpl String.Chars, for: BSON.ObjectId do
    def to_string(object_id), do: Base.encode16(object_id.value, case: :lower)
  end

  # supports BSON.Id on JSON responses
  defimpl Poison.Encoder, for: BSON.ObjectId do
    def encode(id, options) do
      id |> BSON.ObjectId.encode!() |> Poison.Encoder.encode(options)
    end
  end
end
