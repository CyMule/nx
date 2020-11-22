defmodule Nx do
  @moduledoc """
  Numerical Elixir.

  A collection of functions and data types to work
  with Numerical Elixir.
  """

  defmodule Tensor do
    defstruct [:data, :type, :shape]
  end

  @doc """
  Builds a tensor.

  The argument is either a number or a boolean, which means the tensor is
  a scalar (zero-dimentions), a list of those (the tensor is a vector) or
  a list of n-lists of those, leading to n-dimensional tensors.

  ## Examples

  A number or a boolean returns a tensor of zero dimensions:

      iex> t = Nx.tensor(0)
      iex> Nx.to_binary(t)
      <<0::64>>
      iex> Nx.type(t)
      {:s, 64}
      iex> Nx.shape(t)
      {}

      iex> t = Nx.tensor(true)
      iex> Nx.to_binary(t)
      <<1::1>>
      iex> Nx.type(t)
      {:s, 1}
      iex> Nx.shape(t)
      {}

  Giving a list returns a vector (an one-dimensional tensor):

      iex> t = Nx.tensor([1, 2, 3])
      iex> Nx.to_binary(t)
      <<1::64, 2::64, 3::64>>
      iex> Nx.type(t)
      {:s, 64}
      iex> Nx.shape(t)
      {3}

      iex> t = Nx.tensor([1.2, 2.3, 3.4, 4.5])
      iex> Nx.to_binary(t)
      <<1.2::64-float, 2.3::64-float, 3.4::64-float, 4.5::64-float>>
      iex> Nx.type(t)
      {:f, 64}
      iex> Nx.shape(t)
      {4}

  The type can be explicitly given. Integers and floats
  bigger than the given size overlap:

      iex> t = Nx.tensor([300, 301, 302], type: {:s, 8})
      iex> Nx.to_binary(t)
      <<44::8, 45::8, 46::8>>
      iex> Nx.type(t)
      {:s, 8}

      iex> t = Nx.tensor([1.2, 2.3, 3.4], type: {:f, 32})
      iex> Nx.to_binary(t)
      <<1.2::32-float, 2.3::32-float, 3.4::32-float>>
      iex> Nx.type(t)
      {:f, 32}

  An empty list defaults to floats:

      iex> t = Nx.tensor([])
      iex> Nx.to_binary(t)
      <<>>
      iex> Nx.type(t)
      {:f, 64}

  Mixed types get the highest precision type:

      iex> t = Nx.tensor([true, 2, 3.0])
      iex> Nx.to_binary(t)
      <<1.0::float-64, 2.0::float-64, 3::float-64>>
      iex> Nx.type(t)
      {:f, 64}

  Multi-dimensional tensors are also possible:

      iex> t = Nx.tensor([[1, 2, 3], [4, 5, 6]])
      iex> Nx.to_binary(t)
      <<1::64, 2::64, 3::64, 4::64, 5::64, 6::64>>
      iex> Nx.type(t)
      {:s, 64}
      iex> Nx.shape(t)
      {2, 3}

      iex> t = Nx.tensor([[1, 2], [3, 4], [5, 6]])
      iex> Nx.to_binary(t)
      <<1::64, 2::64, 3::64, 4::64, 5::64, 6::64>>
      iex> Nx.type(t)
      {:s, 64}
      iex> Nx.shape(t)
      {3, 2}

      iex> t = Nx.tensor([[[1, 2], [3, 4], [5, 6]], [[-1, -2], [-3, -4], [-5, -6]]])
      iex> Nx.to_binary(t)
      <<1::64, 2::64, 3::64, 4::64, 5::64, 6::64, -1::64, -2::64, -3::64, -4::64, -5::64, -6::64>>
      iex> Nx.type(t)
      {:s, 64}
      iex> Nx.shape(t)
      {2, 3, 2}

  ## Options

    * `:type` - sets the type of the tensor. If one is not given,
      one is automatically inferred based on the input. Integers
      are by default signed and of size 64. Floats have size of 64.
      Booleans are integers of size 1 (also known as predicates).
      See `type/1` for more information.

  """
  def tensor(arg, opts \\ []) do
    type = opts[:type] || infer_type(arg)
    validate_type!(type)
    {dimensions, data} = flatten(arg, type)
    %Tensor{shape: dimensions, type: type, data: data}
  end

  defp infer_type(arg) do
    case infer_type(arg, -1) do
      -1 -> {:f, 64}
      0 -> {:s, 1}
      1 -> {:s, 64}
      2 -> {:f, 64}
    end
  end

  defp infer_type(arg, inferred) when is_list(arg), do: Enum.reduce(arg, inferred, &infer_type/2)
  defp infer_type(arg, inferred) when is_boolean(arg), do: max(inferred, 0)
  defp infer_type(arg, inferred) when is_integer(arg), do: max(inferred, 1)
  defp infer_type(arg, inferred) when is_float(arg), do: max(inferred, 2)

  defp flatten(list, type) when is_list(list) do
    {dimensions, acc} = flatten_list(list, type, [], [])

    {dimensions |> Enum.reverse() |> List.to_tuple(),
     acc |> Enum.reverse() |> IO.iodata_to_binary()}
  end

  defp flatten(other, type), do: {{}, scalar_to_binary(other, type)}

  defp flatten_list([], _type, dimensions, acc) do
    {[0 | dimensions], acc}
  end

  defp flatten_list([head | rest], type, parent_dimensions, acc) when is_list(head) do
    {child_dimensions, acc} = flatten_list(head, type, [], acc)

    {n, acc} =
      Enum.reduce(rest, {1, acc}, fn list, {count, acc} ->
        case flatten_list(list, type, [], acc) do
          {^child_dimensions, acc} ->
            {count + 1, acc}

          {other_dimensions, _acc} ->
            raise ArgumentError,
                  "cannot build tensor because lists have different shapes, got " <>
                    inspect(List.to_tuple(child_dimensions)) <>
                    " at position 0 and " <>
                    inspect(List.to_tuple(other_dimensions)) <> " at position #{count + 1}"
        end
      end)

    {child_dimensions ++ [n | parent_dimensions], acc}
  end

  defp flatten_list(list, type, dimensions, acc) do
    {[length(list) | dimensions], Enum.reduce(list, acc, &[scalar_to_binary(&1, type) | &2])}
  end

  defp scalar_to_binary(true, type), do: scalar_to_binary(1, type)
  defp scalar_to_binary(false, type), do: scalar_to_binary(0, type)

  defp scalar_to_binary(value, {:s, size}) when is_integer(value),
    do: <<value::size(size)-signed-integer>>

  defp scalar_to_binary(value, {:u, size}) when is_integer(value),
    do: <<value::size(size)-unsigned-integer>>

  defp scalar_to_binary(value, {:f, size}) when is_number(value),
    do: <<value::size(size)-float>>

  defp validate_type!({:s, size}) when size > 0, do: :ok
  defp validate_type!({:u, size}) when size > 0, do: :ok
  defp validate_type!({:f, size}) when size in [32, 64], do: :ok

  @doc """
  Returns the type of the tensor.

  A type is a two-element tuple. The first element is one of:

      * `:s` - signed integer
      * `:u` - unsigned integer
      * `:f` - float

  The second elemnet is a size. Integers can have any size.
  Currently only 32 and 64 bit floats are supported.
  """
  def type(%Tensor{type: type}), do: type

  @doc """
  Returns the shape of the tensor as a tuple.

  The size of this tuple gives the rank of the tensor.
  """
  def shape(%Tensor{shape: shape}), do: shape

  @doc """
  Returns the rank of a tensor.
  """
  def rank(%Tensor{shape: shape}), do: tuple_size(shape)

  @doc """
  Returns the underlying tensor as a binary.

  The binary is returned as is (which is row-major).
  """
  def to_binary(%Tensor{data: data}), do: data

  # TODO: Properly implement this.
  def add(a, b) when is_integer(a) and is_integer(b), do: :erlang.+(a, b)
  def add(a, b) when is_list(a) and is_integer(b), do: Enum.map(a, &:erlang.+(&1, b))
end